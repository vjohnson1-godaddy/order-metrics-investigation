# Query Results (2026-09-01)

All queries run against Athena `primary` workgroup with production AWS credentials.

## Order 4171198448 — experiment overlap

Single paid conversion order ($119.88) from Starter trial 4170626077.
Exists in `experiment_order` for **39 different experiments** including:

- `commerce_catalog_baseline_aa`
- `myrenewals_good_standing_subscription`
- `serp_badges_for_expiring_names...`
- `aab_recommended_plan_uppdcx`
- `merch_precheck_gdexp_14156_AAB_99` (our experiment)
- ... and 34 others

Each row shows the same order with $119.88 GCR. The anti-join in the cube path sees all 39 entries.

## Treatment Starter f2p — anti-join impact

### treatment1

| Status | Conversions | GCR |
|--------|------------|-----|
| EXCLUDED_BY_ANTIJOIN | 86 | $9,957.11 |
| INCLUDED | 29 | $3,371.97 |
| **Total** | **115** | **$13,329.08** |

### treatment2

| Status | Conversions | GCR |
|--------|------------|-----|
| EXCLUDED_BY_ANTIJOIN | 78 | $9,433.14 |
| INCLUDED | 21 | $2,417.59 |
| **Total** | **99** | **$11,850.73** |

## Control Free f2p — confirming asymmetric visibility

### control1

| Status | Conversions | GCR |
|--------|------------|-----|
| EXCLUDED_BY_ANTIJOIN | 162 | $15,260.01 |
| INCLUDED | 9 | $762.96 |
| **Total** | **171** | **$16,022.97** |

95% excluded — but invisible because `product_pnl_subline_name = 'Free'` is filtered by the `new_airo_builder_paid_plan_order` named filter. Both Hivemind and Shashi's manual calc exclude Free subline → control matches.

## Trial distribution by cohort

| Cohort | Subline=Free | Subline=Starter |
|--------|-------------|-----------------|
| control1 | 4,302 | 4 |
| treatment1 | 3,717 | 2,403 |
| treatment2 | 3,813 | 2,045 |

The precheck flow shifts trials from Free to Starter in treatment groups.

## Raw f2p conversion candidates (before anti-join)

| Cohort | Trial Subline | Conversion Orders | Conversion GCR |
|--------|--------------|-------------------|----------------|
| control1 | Free | 206 | $18,596 |
| treatment1 | Free | 166 | $14,383 |
| treatment1 | Starter | 164 | $19,163 |
| treatment2 | Free | 176 | $15,453 |
| treatment2 | Starter | 122 | $14,608 |

Note: May contain partition duplicates from Athena scan.

## Platform-wide impact scope

Query run: 2026-09-01 (Athena execution ID: `8443251a-bab3-47f9-990d-f5fcfdad7cec`)

| Metric | Value |
|--------|-------|
| Experiments with f2p conversions | **549** |

All 549 experiments have `product_free_trial_conversion_flag = true` in `experiment_order` on the latest partition. The anti-join bug potentially affects all of them through the data cube path.
