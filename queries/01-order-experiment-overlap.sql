-- 01-order-experiment-overlap.sql
-- Proves that a single paid conversion order exists in experiment_order
-- for many different experiments. This is why the globally-scoped anti-join
-- incorrectly excludes it from f2p.
--
-- Result: Order 4171198448 appears in 39 different experiments.
-- Run in: Athena, primary workgroup, hivemind_analytics database

SELECT
    experiment_id,
    scorecard_template_name,
    cohort_id,
    order_id,
    gcr_usd_amt
FROM hivemind_analytics.experiment_order
WHERE order_id = '4171198448'
  AND record_create_mst_date = (
      SELECT MAX(record_create_mst_date)
      FROM hivemind_analytics.experiment_order
  )
ORDER BY experiment_id;
