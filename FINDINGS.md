# Detailed Findings

## 1. Data path discovery

The stats engine does **not** read from Level 4 SQL parquet output for order metrics. It reads from a **data cube** built by `MetricCubeJob`:

```
MetricCubeJob (hivemind-pyspark-etl)
  → executes order_metrics.sql (with f2p logic) against ALL experiments
  → SQL rewrite: strip_scorecard_filters() + inject_segments()
  → writes to s3://gd-gxcoreservices-prod-hivemind-shared-data/deep-research/order-metrics-ads
  → partitioned by: experiment_id, record_create_mst_date, cohort_id

Stats engine (hivemind-analysis)
  → reads from that cube (production.json: metric_cube.order_metrics)
  → applies named filter (new_airo_builder_paid_plan_order) as pushdown + pandas filters
  → filter: product_pnl_line_name='Airo', version='AI Builder',
    subline NOT IN ('AddOn','Free'), gcr_amt > 0, new_renewal='New Purchase'
```

### Key code references

| File | Lines | Role |
|------|-------|------|
| `hivemind-analysis/configs/production.json` | `metric_cube.order_metrics` | S3 URI for cube |
| `hivemind-analysis/hivemind_analysis/query_results_reader.py` | 184-187, 206-268 | Reads from cube, applies filters |
| `hivemind-analysis/hivemind_analysis/sql_parser.py` | 15-19 | `COLUMN_NAME_MAPPING: gcr_usd_amt → gcr_amt` |
| `hivemind-analysis/hivemind_analysis/analysis/variables/factory/downloader_mixin.py` | 55-60 | Special `order_metrics` path |
| `hivemind-pyspark-etl/hivemind_etl/jobs/metric_cube_job.py` | 32-95, 207-244 | Cube config + SQL execution |
| `hivemind-pyspark-etl/hivemind_etl/utils/sql_glot_util.py` | 42-114, 158-188 | `inject_segments()` + `strip_scorecard_filters()` |
| `hivemind-business-analytics/queries/experiment_kpis/order_metrics.sql` | 133-194, 249-305 | The SQL with the buggy anti-join |

## 2. How the cube SQL rewrite works

`MetricCubeJob` sets `SCORECARD_TEMPLATE_NAME = "none"` (sentinel). Each SQL statement goes through `rewrite_full_sql()`:

1. **`inject_segments()`** — adds 22 PNL dimension columns (`o.product_pnl_subline_name`, `o.product_free_trial_flag`, etc.) to SELECT and GROUP BY of CTE nodes only. Skips CACHE TABLE inner queries and derived tables.

2. **`strip_scorecard_filters()`** — removes ALL `scorecard_template_name` WHERE conditions from all nodes.

Result: `CACHE TABLE experiment_order_cache AS (SELECT * FROM right WHERE scorecard_template_name = 'none')` becomes `SELECT * FROM right` — all orders from all experiments, no scorecard filter.

## 3. The f2p anti-join bug

### What the anti-join does

In `order_metrics.sql`, the `f2p` CACHE TABLE (lines 151-195) identifies free-to-paid conversions: trial orders that later convert to paid subscriptions. It uses `enterprise.free_entitlement` to link free trials to their paid conversions, then an **anti-join** to exclude conversions that already exist as direct orders (to prevent double-counting):

```sql
LEFT JOIN (
    SELECT order_id, row_id
    FROM experiment_order_cache
    GROUP BY order_id, row_id
) eeo
ON fe.paid_bill_id = eeo.order_id
AND fe.paid_bill_line_num = eeo.row_id
WHERE ...
AND eeo.order_id IS NULL    -- exclude if paid order is already a direct order
AND eeo.row_id IS NULL
```

### Why it breaks in the cube path

| Path | `experiment_order_cache` contains | Anti-join scope | Behavior |
|------|-----------------------------------|-----------------|----------|
| **Level 4 SQL** (normal) | Orders for one scorecard | Same scorecard only | Correct |
| **Cube** (MetricCubeJob) | ALL orders, ALL experiments, ALL scorecards | Global | **Over-excludes** |

In the cube path, `strip_scorecard_filters()` removes the scorecard filter. A paid conversion order that exists as a direct order in *any* experiment gets excluded from f2p for *every* experiment.

### Why treatment is affected more than control

This experiment's precheck flow shifts trial orders from `Free` subline to `Starter` subline in treatment groups:

| Cohort | Free trials | Starter trials |
|--------|------------|----------------|
| control1 | 4,302 | 4 |
| treatment1 | 3,717 | **2,403** |
| treatment2 | 3,813 | **2,045** |

- **Treatment** Starter conversions are real paid products that commonly appear in `experiment_order` for other experiments → anti-joined out → **visible GCR loss**
- **Control** Free conversions are also anti-joined out, but `product_pnl_subline_name = 'Free'` is already filtered by the stats engine → **invisible loss**

## 4. Data verification

### Example: Order 4171198448

This $119.88 paid conversion from Starter trial 4170626077 exists in `experiment_order` for **39 different experiments** on the latest partition. See `queries/01-order-experiment-overlap.sql`.

### Quantified impact on treatment1 Starter f2p

| Status | Conversions | GCR |
|--------|------------|-----|
| EXCLUDED by anti-join | 86 | **$9,957.11** |
| INCLUDED | 29 | $3,371.97 |

75% of Starter f2p conversions ($9,957 of $13,329) are incorrectly excluded. See `queries/02-antijoin-impact-treatment.sql`.

### Control Free f2p (confirming asymmetric visibility)

| Status | Conversions | GCR |
|--------|------------|-----|
| EXCLUDED by anti-join | 162 | $15,260.01 |
| INCLUDED | 9 | $762.96 |

95% excluded — but invisible because Free subline is filtered out by the named filter. See `queries/03-antijoin-impact-control.sql`.

### Gap reconciliation

$9,957 excluded Starter f2p GCR vs Shashi's ~$7,770 gap. Difference because:
1. The named filter further narrows which f2p rows contribute (not all Starter conversions are `product_pnl_line_name='Airo'`)
2. Shashi's manual calc may use different date ranges or dedup logic

## 5. Scope of impact

This is a **platform-level bug** affecting ALL experiments that rely on f2p conversions through the data cube path (MetricCubeJob). An experiment is affected when:

1. Users sign up for free/trial products that later convert to paid
2. Those paid conversion orders also exist as direct orders in other experiments (very common — 39+ experiment overlap per user)
3. The metric's named filter includes the trial's PNL subline (making the loss visible)

Severity scales with experiment overlap in the user population. On GoDaddy's platform, a typical user is bucketed into 30-40 experiments simultaneously.

## 6. Ruled-out hypotheses

### H1: Billing Agent orders excluded
**Ruled out.** No `point_of_purchase` filter exists at the ETL level. The trial order has `point_of_purchase_name='Web'`.

### H2: CACHE TABLE parse failure in sqlglot
**Ruled out.** Tested locally: sqlglot correctly parses `CACHE TABLE f2p AS (...)` as a `Cache` node in Spark dialect. `rewrite_full_sql()` passes it through without corruption. The anti-join subquery's GROUP BY is unchanged. `inject_segments` only operates on `exp.CTE` nodes, so CACHE TABLE inner queries and derived tables in FROM clauses are correctly skipped.

### H3: Level 4 SQL path
**Red herring.** The stats engine reads from the data cube, not Level 4 parquet output. Level 4 `order_metrics_<hash>` variants have `query.sql` files but produce no parquet for this scorecard. Only `llc_order_metrics` produces output. This is expected — `order_metrics` metadata_id always routes through the cube.
