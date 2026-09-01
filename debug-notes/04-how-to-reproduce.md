# How to Reproduce

## Prerequisites

- AWS credentials for prod account (624719941071)
- Athena access via `primary` workgroup (the `hivemind` workgroup may not exist for your role)

## Running the queries

All queries are in the `queries/` directory. Run them in Athena against the `primary` workgroup.

### Via AWS CLI

```bash
# Source your AWS creds
eval $(aws-okta-processor ...)
# OR source from file
source /tmp/aws_env_for_cursor-prod.txt

# Run a query
aws athena start-query-execution \
  --query-string "$(cat queries/01-order-experiment-overlap.sql)" \
  --work-group primary \
  --result-configuration "OutputLocation=s3://gd-gxcoreservices-prod-hivemind-shared-data/athena-results/" \
  --query-execution-context "Database=hivemind_analytics" \
  --region us-west-2

# Check status (grab the QueryExecutionId from above)
aws athena get-query-execution \
  --query-execution-id <id> \
  --region us-west-2

# Get results once SUCCEEDED
aws athena get-query-results \
  --query-execution-id <id> \
  --region us-west-2
```

### Via Athena console

1. Go to https://us-west-2.console.aws.amazon.com/athena (prod account)
2. Select workgroup: `primary`
3. Select database: `hivemind_analytics`
4. Paste and run each query from `queries/`

## Gotchas

- **order_id is varchar:** Use `order_id = '4171198448'` (quoted), not `order_id = 4171198448`. Unquoted gives `TYPE_MISMATCH`.
- **Async execution:** CLI queries are async. Poll `get-query-execution` until state is `SUCCEEDED` before calling `get-query-results`.
- **Partition pruning:** Queries that scan `experiment_order` without a `record_create_mst_date` filter will be slow. All queries in this repo use `MAX(record_create_mst_date)` subqueries to hit the latest partition only.
- **free_entitlement access:** `enterprise.free_entitlement` and `enterprise.fact_bill_line` require cross-database access from the prod account. If you get permission errors, check your IAM role's Glue catalog permissions.

## What to verify

### Claim 1: Order overlap (queries/01)
- Does order 4171198448 really appear in ~39 experiments?
- Is this typical? Try a few other paid conversion orders.

### Claim 2: Anti-join impact (queries/02)
- Do 86/115 treatment1 Starter f2p conversions get excluded?
- Does the dollar amount ($9,957) account for the ~$7,770 gap after applying the named filter?

### Claim 3: Asymmetric visibility (queries/03)
- Is control equally affected (~95% excluded)?
- Confirm that Free subline exclusion by the named filter hides control's losses.

### Claim 4: Trial distribution (queries/04)
- Does treatment really shift from Free to Starter subline?
- Are the counts consistent with the experiment's precheck flow?

### Claim 5: The fix is correct
- Read the anti-join at `order_metrics.sql:181-194`
- Confirm that `eo.experiment_id` and `eo.cohort_id` are in scope from the outer JOIN to `experiment_order_cache eo` (line 172-174)
- Confirm the fix is a no-op in Level 4 path (experiment_order_cache already filtered by scorecard)
