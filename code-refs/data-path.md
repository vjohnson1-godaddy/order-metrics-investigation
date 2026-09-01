# How the stats engine reads order metrics

The stats engine does NOT read from Level 4 SQL parquet output. It reads from a **data cube**.

## Data flow

```
1. MetricCubeJob (hivemind-pyspark-etl/hivemind_etl/jobs/metric_cube_job.py)
   - Sets SCORECARD_TEMPLATE_NAME = "none" (sentinel value)
   - Splits order_metrics.sql by ";"
   - Each statement goes through rewrite_full_sql()
   - Executes via self.spark.sql()

2. SQL Rewrite (hivemind-pyspark-etl/hivemind_etl/utils/sql_glot_util.py)
   - inject_segments(): adds 22 PNL dimension columns to SELECT/GROUP BY of CTE nodes
   - strip_scorecard_filters(): removes ALL scorecard_template_name WHERE conditions
   - Result: experiment_order_cache contains ALL orders from ALL experiments

3. Cube Output
   - Written to: s3://gd-gxcoreservices-prod-hivemind-shared-data/deep-research/order-metrics-ads
   - Partitioned by: experiment_id, record_create_mst_date, cohort_id
   - One row per user × PNL dimension combo (because PNL columns in GROUP BY)

4. Stats Engine Read (hivemind-analysis/hivemind_analysis/query_results_reader.py:184-268)
   - Reads S3 URI from production.json: metric_cube.order_metrics
   - Applies named filter as pushdown + pandas filters
   - gcr_usd_amt mapped to gcr_amt via COLUMN_NAME_MAPPING (sql_parser.py:15-19)
```

## Why Level 4 is a red herring

For `dpp-e2e-precheck`, Level 4 `order_metrics_<hash>` variants have `query.sql` files but produce NO parquet. Only `llc_order_metrics` produces output. The stats engine never reads from Level 4 for `order_metrics` metadata_id — it always routes through the data cube via the special path in `downloader_mixin.py:55-60`.
