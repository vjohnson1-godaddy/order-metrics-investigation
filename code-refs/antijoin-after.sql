-- Proposed fix: add experiment_id + cohort_id scoping to the anti-join
-- Target: hivemind-business-analytics/queries/experiment_kpis/order_metrics.sql:181-194
--
-- This is a no-op in the Level 4 SQL path (experiment_order_cache is already
-- scoped by scorecard_template_name). In the cube path, it correctly scopes
-- the anti-join per experiment so that a conversion order is only excluded
-- if it exists as a direct order for the SAME experiment.
--
-- The eo.experiment_id and eo.cohort_id references come from the outer query's
-- join to experiment_order_cache (aliased as eo), which is available in scope.
--
-- Note: cohort_id scoping is technically redundant — deterministic MD5 bucketing
-- means a user is in exactly one cohort per experiment, so experiment_id alone
-- is sufficient. Including cohort_id is harmless and makes the intent explicit.
-- Draft PR: hivemind-business-analytics#678

LEFT JOIN (
    SELECT order_id, row_id, experiment_id, cohort_id
    FROM experiment_order_cache
    GROUP BY order_id, row_id, experiment_id, cohort_id
) eeo
ON fe.paid_bill_id = eeo.order_id
AND fe.paid_bill_line_num = eeo.row_id
AND eo.experiment_id = eeo.experiment_id
AND eo.cohort_id = eeo.cohort_id

-- WHERE clause unchanged:
-- AND eeo.order_id IS NULL
-- AND eeo.row_id IS NULL
