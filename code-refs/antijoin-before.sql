-- Current anti-join in order_metrics.sql (lines 181-194)
-- Source: hivemind-business-analytics/queries/experiment_kpis/order_metrics.sql
--
-- BUG: No experiment_id scoping. In the cube path (MetricCubeJob),
-- experiment_order_cache is unfiltered (all experiments, all scorecards).
-- This anti-join checks paid_bill_id against ALL order_ids globally,
-- causing paid conversions that exist as direct orders in ANY other
-- experiment to be excluded from f2p.

LEFT JOIN (
    SELECT order_id, row_id
    FROM experiment_order_cache
    GROUP BY order_id, row_id
) eeo
ON fe.paid_bill_id = eeo.order_id
AND fe.paid_bill_line_num = eeo.row_id

-- Then in the WHERE clause:
-- AND eeo.order_id IS NULL
-- AND eeo.row_id IS NULL
