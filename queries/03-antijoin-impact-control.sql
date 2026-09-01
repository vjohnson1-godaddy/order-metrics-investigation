-- 03-antijoin-impact-control.sql
-- Shows that control's Free f2p conversions are equally affected by the
-- over-scoped anti-join (~95% excluded), but invisible in the scorecard
-- because product_pnl_subline_name='Free' is filtered by the named filter.
--
-- Result (control1): 162 of 171 conversions EXCLUDED ($15,260 of $16,023)
-- Run in: Athena, primary workgroup

WITH latest_eo AS (
    SELECT *
    FROM hivemind_analytics.experiment_order
    WHERE record_create_mst_date = (
        SELECT MAX(record_create_mst_date)
        FROM hivemind_analytics.experiment_order
    )
),

-- Find Free trials in control
this_exp_trials AS (
    SELECT DISTINCT
        order_id,
        row_id,
        cohort_id,
        gcr_usd_amt
    FROM latest_eo
    WHERE experiment_id = 'merch_precheck_gdexp_14156_AAB_99'
      AND product_free_trial_flag = true
      AND product_pnl_subline_name = 'Free'
      AND cohort_id = 'control1'
),

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
GROUP BY cohort_id, status
ORDER BY cohort_id, status;
