-- 05-f2p-conversion-candidates.sql
-- Raw f2p conversion join simulation — shows all f2p conversion candidates
-- by cohort and trial subline, before anti-join exclusion.
--
-- Run in: Athena, primary workgroup

WITH latest_eo AS (
    SELECT *
    FROM hivemind_analytics.experiment_order
    WHERE experiment_id = 'merch_precheck_gdexp_14156_AAB_99'
      AND record_create_mst_date = (
          SELECT MAX(record_create_mst_date)
          FROM hivemind_analytics.experiment_order
      )
),

trials AS (
    SELECT DISTINCT
        order_id,
        row_id,
        cohort_id,
        product_pnl_subline_name AS trial_subline
    FROM latest_eo
    WHERE product_free_trial_flag = true
)

SELECT
    t.cohort_id,
    t.trial_subline,
    COUNT(DISTINCT fe.paid_bill_id) AS conversion_orders,
    ROUND(SUM(fb.gcr_usd_amt), 2) AS conversion_gcr
FROM enterprise.free_entitlement fe
INNER JOIN trials t
    ON fe.free_bill_id = t.order_id
    AND fe.free_bill_line_num = t.row_id
INNER JOIN enterprise.fact_bill_line fb
    ON fe.paid_bill_id = fb.bill_id
    AND fe.paid_bill_line_num = fb.bill_line_num
WHERE fe.paid_bill_mst_date >= DATE '2026-08-01'
GROUP BY t.cohort_id, t.trial_subline
ORDER BY t.cohort_id, t.trial_subline;
