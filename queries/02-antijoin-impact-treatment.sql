-- 02-antijoin-impact-treatment.sql
-- Simulates the f2p anti-join behavior to quantify how many Starter
-- f2p conversions are incorrectly excluded for treatment cohorts.
--
-- Result (treatment1): 86 of 115 conversions ($9,957 of $13,329) EXCLUDED
-- Result (treatment2): 78 of 99 conversions ($9,433 of $11,851) EXCLUDED
-- Run in: Athena, primary workgroup

WITH latest_eo AS (
    SELECT *
    FROM hivemind_analytics.experiment_order
    WHERE record_create_mst_date = (
        SELECT MAX(record_create_mst_date)
        FROM hivemind_analytics.experiment_order
    )
),

-- Find Starter free trials in this experiment
this_exp_trials AS (
    SELECT DISTINCT
        order_id,
        row_id,
        cohort_id,
        gcr_usd_amt
    FROM latest_eo
    WHERE experiment_id = 'merch_precheck_gdexp_14156_AAB_99'
      AND product_free_trial_flag = true
      AND product_pnl_subline_name = 'Starter'
),

-- Find their paid conversions via free_entitlement
f2p_candidates AS (
    SELECT
        t.cohort_id,
        fe.paid_bill_id,
        fe.paid_bill_line_num,
        fb.gcr_usd_amt AS conversion_gcr
    FROM enterprise.free_entitlement fe
    INNER JOIN this_exp_trials t
        ON fe.free_bill_id = t.order_id
        AND fe.free_bill_line_num = t.row_id
    INNER JOIN enterprise.fact_bill_line fb
        ON fe.paid_bill_id = fb.bill_id
        AND fe.paid_bill_line_num = fb.bill_line_num
    WHERE fe.paid_bill_mst_date >= DATE '2026-08-01'
),

-- Simulate the anti-join: check if conversion order exists ANYWHERE in experiment_order
anti_join_check AS (
    SELECT
        f.cohort_id,
        f.conversion_gcr,
        CASE
            WHEN eo2.order_id IS NOT NULL THEN 'EXCLUDED_BY_ANTIJOIN'
            ELSE 'INCLUDED'
        END AS status
    FROM f2p_candidates f
    LEFT JOIN (
        SELECT DISTINCT order_id, row_id
        FROM latest_eo
    ) eo2
        ON f.paid_bill_id = eo2.order_id
        AND f.paid_bill_line_num = eo2.row_id
)

SELECT
    cohort_id,
    status,
    COUNT(*) AS conversions,
    ROUND(SUM(conversion_gcr), 2) AS gcr
FROM anti_join_check
WHERE cohort_id IN ('treatment1', 'treatment2')
GROUP BY cohort_id, status
ORDER BY cohort_id, status;
