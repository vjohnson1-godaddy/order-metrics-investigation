# How MetricCubeJob rewrites SQL

## MetricCubeJob config (metric_cube_job.py:32-95)

```python
METRIC_CONFIG = {
    "order_metrics": {
        "SCORECARD_TEMPLATE_NAME": "none",   # sentinel — triggers strip
        "cached_tables": ["experiment_order_cache", "users_cache", "f2p"],
        "extra_segments": [
            "o.product_pnl_line_name",
            "o.product_pnl_subline_name",
            "o.product_pnl_version_name",
            "o.product_pnl_new_renewal_name",
            "o.product_free_trial_flag",
            "o.product_free_trial_conversion_flag",
            # ... 22 columns total
        ]
    }
}
```

## SQL rewrite pipeline (sql_glot_util.py)

### rewrite_full_sql() (lines 179-188)

Called on each SQL statement (split by ";"):

```python
def rewrite_full_sql(sql, extra_columns):
    tree = sqlglot.parse_one(sql, dialect="spark")
    tree = inject_segments(tree, extra_columns)    # add PNL columns
    tree = strip_scorecard_filters(tree)            # remove scorecard WHERE
    return tree.sql(dialect="spark")
```

### inject_segments() (lines 42-114)

Only operates on `exp.CTE` nodes (WITH clause definitions). Adds each extra column to both SELECT and GROUP BY. **Correctly skips:**
- CACHE TABLE inner queries (parsed as `Cache` nodes, not CTEs)
- Derived tables in FROM clauses (not CTEs)

### strip_scorecard_filters() (lines 158-176)

Walks all nodes. Removes any WHERE/HAVING condition referencing `scorecard_template_name`. Works across all node types — CTEs, CACHE TABLE inner queries, subqueries.

## The consequence

After rewrite:
- `experiment_order_cache` = ALL orders from ALL experiments (scorecard filter gone)
- `users_cache` = ALL users from ALL experiments
- `f2p` CACHE TABLE = f2p conversions computed against the global `experiment_order_cache`
- The f2p anti-join checks paid orders against ALL `order_id` values globally
