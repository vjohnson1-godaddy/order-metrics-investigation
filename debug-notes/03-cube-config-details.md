# MetricCubeJob Configuration Details

Extracted from `hivemind-pyspark-etl/hivemind_etl/jobs/metric_cube_job.py:32-95`.

## METRIC_CONFIG for order_metrics

```python
"order_metrics": {
    "SCORECARD_TEMPLATE_NAME": "none",   # sentinel — stripped by rewrite
    "cached_tables": [
        "experiment_order_cache",
        "users_cache",
        "f2p"
    ],
    "extra_segments": [
        "o.product_pnl_line_name",
        "o.product_pnl_subline_name",
        "o.product_pnl_version_name",
        "o.product_pnl_new_renewal_name",
        "o.product_free_trial_flag",
        "o.product_free_trial_conversion_flag",
        "o.product_pnl_market_name",
        "o.product_pnl_platform_name",
        "o.product_pnl_group_name",
        "o.product_pnl_segment_name",
        "o.product_hosting_type_name",
        "o.product_type_name",
        "o.point_of_purchase_name",
        "o.reseller_type_name",
        "o.transaction_currency_code",
        "o.payment_currency_code",
        "o.product_namespace_name",
        "o.duration",
        "o.product_pnl_package_name",
        "o.product_pnl_tier_name",
        "o.is_min_inflated",
        "o.product_pnl_brand_name"
    ]
}
```

## What SCORECARD_TEMPLATE_NAME = "none" does

The SQL template uses `${hiveconf:SCORECARD_TEMPLATE_NAME}` in WHERE clauses on `experiment_order_cache` and `users_cache`. When MetricCubeJob sets it to `"none"`, these WHERE clauses become `scorecard_template_name = 'none'` — matching nothing.

But `rewrite_full_sql()` then calls `strip_scorecard_filters()` which removes ALL `scorecard_template_name` conditions entirely. The sentinel value is never actually evaluated.

## SQL execution flow (metric_cube_job.py:207-244)

```python
def _execute_sql_queries(self, config, sql_content):
    statements = sql_content.split(";")
    for stmt in statements:
        if stmt.strip():
            rewritten = rewrite_full_sql(stmt, config["extra_segments"])
            self.spark.sql(rewritten)
```

Each CACHE TABLE and CTE statement is rewritten independently. The three cached tables (`experiment_order_cache`, `users_cache`, `f2p`) are Spark temp views that persist for the session. The final SELECT reads from them.

## Cube output location

```
s3://gd-gxcoreservices-prod-hivemind-shared-data/deep-research/order-metrics-ads
```

Partitioned by: `experiment_id`, `record_create_mst_date`, `cohort_id`

One row per user × PNL dimension combo (because the 22 extra_segments columns are added to GROUP BY by `inject_segments()`).

## Stats engine read config

From `hivemind-analysis/configs/production.json`:

```json
{
  "metric_cube": {
    "order_metrics": "s3://gd-gxcoreservices-prod-hivemind-shared-data/deep-research/order-metrics-ads"
  }
}
```
