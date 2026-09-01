# Scope Assessment: Which experiments are affected?

## Conditions for an experiment to be affected

All three must be true:

1. **Experiment has f2p conversions** — users sign up for free/trial products that later convert to paid orders
2. **Paid conversion orders exist in other experiments** — the conversion order appears in `experiment_order` for at least one other experiment (extremely common; a single order appeared in 39 experiments)
3. **The named filter includes the trial's PNL subline** — so the f2p loss is visible in the scorecard (e.g., Starter passes the filter; Free is already excluded)

## Why most experiments are NOT visibly affected

Most experiments don't have condition 3. The typical free trial is subline=`Free`, which is already excluded by most named filters (`NOT IN ('AddOn', 'Free')`). The f2p anti-join drops Free conversions too, but since they were never going to appear in the scorecard anyway, the loss is invisible.

This experiment is special because the precheck flow changes trial subline from Free to Starter. Starter passes the named filter, making the anti-join loss visible.

## Experiments that ARE likely affected

Any experiment where:
- The product flow creates non-Free trial sublines (Starter, Basic, etc.)
- Those trials convert to paid
- The named filter includes that subline

To find potentially affected experiments, query for experiments with significant Starter/Basic/etc free trials:

```sql
SELECT
    experiment_id,
    product_pnl_subline_name,
    COUNT(*) AS trial_count,
    SUM(CASE WHEN product_free_trial_conversion_flag = true THEN 1 ELSE 0 END) AS conversions
FROM hivemind_analytics.experiment_order
WHERE product_free_trial_flag = true
  AND product_pnl_subline_name NOT IN ('Free', 'AddOn')
  AND record_create_mst_date = (
      SELECT MAX(record_create_mst_date) FROM hivemind_analytics.experiment_order
  )
GROUP BY experiment_id, product_pnl_subline_name
HAVING COUNT(*) > 100
ORDER BY conversions DESC;
```

## Impact on past experiment decisions

If any past experiment had treatment arms that created non-Free trials, their GCR may have been under-reported. Historical results through the cube path should be treated as suspect for f2p-heavy experiments.

The Level 4 SQL path (used by `SqlScriptsJob` for some scorecards) is NOT affected — it retains the scorecard filter. Only experiments whose metrics route through MetricCubeJob are impacted.

## How to tell if a metric routes through the cube

Check `hivemind-analysis/configs/production.json` for `metric_cube` entries. Any `metadata_id` listed there reads from a cube. Currently:
- `order_metrics` → reads from cube (AFFECTED)
- Others may exist — check the config

Within the stats engine, `downloader_mixin.py:55-60` has the special-case routing for `order_metrics`.
