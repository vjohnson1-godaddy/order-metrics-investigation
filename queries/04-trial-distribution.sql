-- 04-trial-distribution.sql
-- Shows how the experiment shifts trial orders from Free to Starter subline
-- in treatment groups. This is what makes the anti-join bug visible for
-- treatment (Starter passes the named filter) but invisible for control
-- (Free is excluded by the named filter).
--
-- Run in: Athena, primary workgroup

SELECT
    cohort_id,
    product_pnl_subline_name,
    COUNT(*) AS trial_count,
    ROUND(SUM(gcr_usd_amt), 2) AS total_gcr
FROM hivemind_analytics.experiment_order
WHERE experiment_id = 'merch_precheck_gdexp_14156_AAB_99'
  AND product_free_trial_flag = true
  AND record_create_mst_date = (
      SELECT MAX(record_create_mst_date)
      FROM hivemind_analytics.experiment_order
  )
GROUP BY cohort_id, product_pnl_subline_name
ORDER BY cohort_id, product_pnl_subline_name;
