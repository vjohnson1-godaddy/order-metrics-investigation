# Investigation Timeline

## How we got here

### Initial report (2026-09-01)

Shashi Gupta in #hivemind-contrib reported treatment GCR mismatch for `merch_precheck_gdexp_14156_AAB_99`. Hypothesis: Hivemind excludes "Billing Agent" orders.

### Dead ends and redirects

1. **Billing Agent hypothesis** — Searched for `point_of_purchase` filters across `hivemind-pyspark-etl` and `hivemind-business-analytics`. No such filter exists at the ETL level. The trial order itself has `point_of_purchase_name='Web'`. Ruled out.

2. **Level 4 SQL path** — Initially assumed the stats engine reads from Level 4 SQL parquet output (the normal ETL path). Spent time tracing `SqlScriptsJob` output for `dpp-e2e-precheck`. Found that `order_metrics_<hash>` variants produce NO parquet for this scorecard — only `llc_order_metrics` does. This was a red herring.

3. **Discovering the cube path** — The breakthrough was tracing the stats engine read path in `hivemind-analysis`. `downloader_mixin.py:55-60` has a special case for `order_metrics` metadata_id that routes to `query_results_reader.py`, which reads from `production.json`'s `metric_cube.order_metrics` S3 URI. This pointed to `MetricCubeJob`, not `SqlScriptsJob`.

4. **sqlglot CACHE TABLE concern** — Worried that `rewrite_full_sql()` might corrupt the f2p CACHE TABLE SQL. Tested locally: sqlglot correctly parses `CACHE TABLE` as a `Cache` node in Spark dialect. `inject_segments()` only operates on `exp.CTE` nodes so CACHE TABLE inner queries are skipped. The rewrite is clean. The bug is in the SQL itself, not the rewriter.

### Root cause identification

Once the cube path was understood, the bug became clear: `strip_scorecard_filters()` makes `experiment_order_cache` global, but the f2p anti-join implicitly assumes it's scoped to one scorecard.

### Data verification

Ran Athena queries to confirm:
- Order 4171198448 exists in 39 experiments (proves global scope)
- 86/115 treatment1 Starter f2p conversions excluded ($9,957)
- Control equally affected but invisible (Free subline filtered)

### Gotchas encountered during Athena queries

- **Workgroup:** `hivemind` workgroup not found. Use `primary` with explicit `--result-configuration OutputLocation=s3://...`
- **Column types:** `order_id` is varchar, not bigint. Must quote: `order_id = '4171198448'` not `order_id = 4171198448` (TYPE_MISMATCH error)
- **Async results:** Athena queries are async. Must poll `get-query-execution` until state is `SUCCEEDED` before reading results. Initial attempts to read results while `RUNNING` returned empty JSON.
