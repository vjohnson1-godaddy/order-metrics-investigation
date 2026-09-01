# Order Metrics F2P Anti-Join Investigation

**Date:** 2026-09-01
**Experiment:** `merch_precheck_gdexp_14156_AAB_99`
**Scorecard:** `dpp-e2e-precheck`
**Reporter:** Shashi Gupta (#hivemind-contrib)

## Summary

Treatment GCR is under-reported in Hivemind vs manual calculation. Control matches.

| Cohort | Hivemind | Manual | Delta |
|--------|----------|--------|-------|
| control1 | $16,911 | $16,911 | match |
| treatment1 | $15,414 | $23,184 | **-$7,770** |

**Root cause:** The f2p (free-to-paid) anti-join in `order_metrics.sql` is globally scoped in the data cube path. When `MetricCubeJob` strips scorecard filters, `experiment_order_cache` contains orders from ALL experiments. The anti-join then excludes any paid conversion order that exists as a direct order in *any* experiment — not just the current one.

A typical paid conversion order exists in `experiment_order` for ~39 other experiments (users are bucketed into many experiments simultaneously), so ~75% of treatment's Starter f2p conversions are incorrectly excluded.

**This is a platform-level bug** affecting all experiments with f2p conversions through the data cube. As of 2026-09-01, **549 experiments** have f2p conversion data in `experiment_order` — all are potentially affected.

## Investigation structure

```
├── README.md                          # This file
├── FINDINGS.md                        # Detailed root cause analysis
├── queries/
│   ├── 01-order-experiment-overlap.sql    # Proves a single order appears in 39 experiments
│   ├── 02-antijoin-impact-treatment.sql   # Quantifies excluded Starter f2p conversions
│   ├── 03-antijoin-impact-control.sql     # Shows control is equally affected but invisible
│   ├── 04-trial-distribution.sql          # Free vs Starter trial counts by cohort
│   ├── 05-f2p-conversion-candidates.sql   # Raw f2p conversion join simulation
│   └── 06-platform-impact-scope.sql       # Count of all experiments with f2p conversions
├── code-refs/
│   ├── antijoin-before.sql                # Current buggy anti-join (order_metrics.sql:181-194)
│   ├── antijoin-after.sql                 # Proposed fix with experiment_id scoping
│   ├── data-path.md                       # How stats engine reads order metrics (cube, not L4)
│   └── sql-rewrite.md                     # How MetricCubeJob strips scorecard filters
├── evidence/
│   └── summary-tables.md                  # Query result tables from Athena
└── report.html                            # Standalone HTML investigation report
```

## Proposed fix

Scope the anti-join subquery by `experiment_id` + `cohort_id`:

```sql
-- Before (order_metrics.sql:181-194)
LEFT JOIN (
    SELECT order_id, row_id
    FROM experiment_order_cache
    GROUP BY order_id, row_id
) eeo
ON fe.paid_bill_id = eeo.order_id
AND fe.paid_bill_line_num = eeo.row_id

-- After
LEFT JOIN (
    SELECT order_id, row_id, experiment_id, cohort_id
    FROM experiment_order_cache
    GROUP BY order_id, row_id, experiment_id, cohort_id
) eeo
ON fe.paid_bill_id = eeo.order_id
AND fe.paid_bill_line_num = eeo.row_id
AND eo.experiment_id = eeo.experiment_id
AND eo.cohort_id = eeo.cohort_id
```

This is a no-op in the Level 4 SQL path (already scoped by scorecard) but correctly scopes the anti-join per experiment in the cube path.

**Note on `cohort_id` scoping:** The `cohort_id` join is technically redundant — a user can only be in one cohort per experiment (deterministic MD5 bucketing), so `experiment_id` alone is sufficient. Including `cohort_id` is harmless and makes the intent explicit. No re-bucketing scenario can put the same user in two cohorts for one experiment.

**Target file:** `hivemind-business-analytics/queries/experiment_kpis/order_metrics.sql:181-194`
**Draft PR:** [hivemind-business-analytics#678](https://github.com/gdcorp-dna/hivemind-business-analytics/pull/678)

## Ruled-out hypotheses

1. **Billing Agent orders excluded** — No `point_of_purchase` filter exists at the ETL level
2. **CACHE TABLE parse failure** — sqlglot correctly handles CACHE TABLE in Spark dialect
3. **Level 4 SQL path** — Red herring; stats engine reads from the data cube, not L4 parquet
