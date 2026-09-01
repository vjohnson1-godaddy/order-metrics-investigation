# Example Order Trace: 4170626077 → 4171198448

End-to-end trace of one f2p conversion to prove the pipeline linkage.

## Trial order: 4170626077

Found in `hivemind_analytics.experiment_order` for this experiment:

| Field | Value |
|-------|-------|
| experiment_id | merch_precheck_gdexp_14156_AAB_99 |
| cohort_id | treatment1 |
| order_id | 4170626077 |
| row_id | 0 |
| product_pnl_subline_name | Starter |
| product_free_trial_flag | true |
| gcr_usd_amt | $0.46 |
| point_of_purchase_name | Web |

## Conversion order: 4171198448

NOT in `experiment_order` for this experiment (it's the paid conversion, not the original trial).
IS in `enterprise.fact_bill_line`:

| Field | Value |
|-------|-------|
| bill_id | 4171198448 |
| bill_line_num | 0 |
| gcr_usd_amt | $119.88 |

## Linkage: enterprise.free_entitlement

| Field | Value |
|-------|-------|
| free_bill_id | 4170626077 |
| free_bill_line_num | 0 |
| paid_bill_id | 4171198448 |
| paid_bill_line_num | 0 |
| paid_bill_mst_date | 2026-08-25 |

## The bug in action

Order 4171198448 exists in `experiment_order` for **39 other experiments** (verified via `queries/01-order-experiment-overlap.sql`). In the cube path, the f2p anti-join sees it globally and excludes this $119.88 conversion from the f2p CTE. The trial order's $0.46 GCR survives (it's a direct order), but the $119.88 conversion GCR is lost.

## Verification query

```sql
-- Confirm the trial exists in experiment_order
SELECT order_id, row_id, product_pnl_subline_name, product_free_trial_flag, gcr_usd_amt
FROM hivemind_analytics.experiment_order
WHERE experiment_id = 'merch_precheck_gdexp_14156_AAB_99'
  AND order_id = '4170626077'
  AND record_create_mst_date = (
      SELECT MAX(record_create_mst_date) FROM hivemind_analytics.experiment_order
  );

-- Confirm the conversion does NOT exist as a direct order for this experiment
SELECT COUNT(*)
FROM hivemind_analytics.experiment_order
WHERE experiment_id = 'merch_precheck_gdexp_14156_AAB_99'
  AND order_id = '4171198448'
  AND record_create_mst_date = (
      SELECT MAX(record_create_mst_date) FROM hivemind_analytics.experiment_order
  );
-- Expected: 0

-- Confirm the conversion DOES exist for other experiments (the global leak)
SELECT COUNT(DISTINCT experiment_id)
FROM hivemind_analytics.experiment_order
WHERE order_id = '4171198448'
  AND record_create_mst_date = (
      SELECT MAX(record_create_mst_date) FROM hivemind_analytics.experiment_order
  );
-- Expected: 39
```
