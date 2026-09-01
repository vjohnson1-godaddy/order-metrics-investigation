-- 06-platform-impact-scope.sql
-- Counts how many experiments have f2p conversion data in experiment_order.
-- All of these are potentially affected by the globally-scoped anti-join bug.
--
-- Result (2026-09-01): 549 experiments
-- Run in: Athena, primary workgroup, hivemind_analytics database

SELECT
    COUNT(DISTINCT experiment_id) AS experiments_with_f2p_conversions
FROM hivemind_analytics.experiment_order
WHERE product_free_trial_conversion_flag = true
  AND record_create_mst_date = (
      SELECT MAX(record_create_mst_date)
      FROM hivemind_analytics.experiment_order
  );
