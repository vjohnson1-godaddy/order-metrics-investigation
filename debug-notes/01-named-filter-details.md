# Named Filter: new_airo_builder_paid_plan_order

This is the stats engine filter that determines which rows from the data cube contribute to the GCR metric for this experiment.

## Filter SQL (from experiment_order_filters.sql:4393)

```sql
WHERE product_pnl_line_name = 'Airo'
  AND product_pnl_version_name = 'AI Builder'
  AND product_pnl_subline_name NOT IN ('AddOn', 'Free')
  AND gcr_usd_amt > 0
  AND product_pnl_new_renewal_name = 'New Purchase'
```

## How it's applied

The stats engine in `hivemind-analysis` applies this as both:
1. **Pushdown filter** on the Parquet read (for partition pruning / predicate pushdown)
2. **Pandas filter** post-read (for conditions that can't be pushed down)

Column name mapping: `gcr_usd_amt` in the filter maps to `gcr_amt` in the cube via `COLUMN_NAME_MAPPING` in `sql_parser.py:15-19`.

Code: `hivemind-analysis/hivemind_analysis/sql_parser.py:887-1014` (`get_experiment_order_filter()`)

## Why this matters for the bug

The `product_pnl_subline_name NOT IN ('AddOn', 'Free')` condition is what makes the anti-join bug asymmetric:

- **Treatment** Starter trials (`product_pnl_subline_name = 'Starter'`) PASS this filter → f2p exclusions are visible in the scorecard
- **Control** Free trials (`product_pnl_subline_name = 'Free'`) are EXCLUDED by this filter → f2p exclusions are invisible

Both cohorts lose f2p conversions to the over-scoped anti-join, but only treatment's loss shows up in the reported numbers.

## Where to find experiment filter definitions

All named filters live in:
```
hivemind-business-analytics/queries/experiment_order_filters.sql
```

Search for the filter name (e.g. `new_airo_builder_paid_plan_order`) to find its SQL definition.
