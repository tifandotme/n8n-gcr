# Maintenance Notes

## Quick Facts

- Service: `n8n` (public)
- Image: `us-west1-docker.pkg.dev/<PROJECT>/n8n-repo/n8n:latest` (custom, includes @actual-app/api)
- DB: Neon serverless PostgreSQL (free tier: 512MB storage, 100 compute hours/month)

## Daily / On-Demand Checks

1. Health: Visit service URL; test workflows.
2. Logs: `mise run logs`
3. Revisions: Ensure latest is Ready in Cloud Run.
4. DB Metrics: Check usage in Neon Console (compute hours, storage).
5. Neon Status: Ensure DB is active (not suspended).
6. Monitoring: Use GCP Console > Monitoring for built-in Cloud Run metrics/logs; n8n /metrics enabled for external scraping if desired.
7. URL: `terraform output -raw cloud_run_service_url`
8. Images: `gcloud artifacts docker images list --location=us-west1 --repository=n8n-repo --project <PROJECT>`
9. DB Connect: `psql "postgresql://neondb_owner:<PASSWORD>@<NEON_HOST>/neondb?sslmode=require"`
10. Mise: `mise run terraform:plan`, `mise run update-n8n`, `mise run terraform:validate`

## Backups & Recovery (Neon)

- Automated: Point-in-time recovery (7 days free tier).
- Manual: `pg_dump "postgresql://neondb_owner:<PASSWORD>@<NEON_HOST>/neondb?sslmode=require" > backup.sql`
- Restore: Import to new Neon project/branch.
- Test: Periodically verify restores.

## Upgrading n8n

1. Run `mise run update-n8n` (pulls latest, builds/pushes custom image, redeploys).
2. Monitor logs; rollback if needed (change image tag in TF, apply).
3. For manual: Test locally, build/push with `mise run build-and-push`, deploy with `mise run terraform:deploy`.

## Building Custom Image

- `mise run build-and-push` (includes auth, installs @actual-app/api)
- Manual: `docker buildx build --platform linux/amd64 -t us-west1-docker.pkg.dev/<PROJECT>/n8n-repo/n8n:<TAG> --push .`
- Auth: `mise run configure-docker`

## Terraform Workflow

- Remote Backend: State stored in GCS bucket "n8n-terraform-state-bucket" with prefix "n8n". Created with `mise run create-state-bucket`.
- Plan: `mise run terraform:plan`
- Apply: `mise run terraform:deploy` (never run apply/destroy directly; pass to user)
- Validate: `mise run terraform:validate` or `mise run terraform:check`
- Output URL: `terraform output -raw cloud_run_service_url`
- Clean: `mise run terraform:clean`

## Automation & CI/CD

- Integrate GitHub Actions for auto-deploys: Push to main triggers `mise run terraform:deploy`. State is remote, avoiding sync issues.
- Alerts: Slack/webhooks for failures; test for false positives.

## Scaling & Cost Control

- Cloud Run: Adjust `cloud_run_max_instances`, CPU/memory.
- Neon: Monitor free tier (100 hours/month); upgrade if exceeded.
- Mise: Installs terraform.
- Budget Alerts: Set up GCP Billing budgets with alerts for overruns; monitor egress costs. Use n8n workflows to query GCP Billing API for costs or trigger on Pub/Sub alerts.
- Refer to `COSTS.md` for detailed cost analysis.

## Security Hardening

- Least privilege on service accounts.
- Audit logs; HTTPS enforced.
- Diagnostics disabled: No telemetry sent to n8n servers.
- Enforce settings file permissions, block env access in node (false), disable bare repos in git node.
- Runners enabled with insecure mode for external modules.

## Troubleshooting

- Image not found: Check push/IAM; run `mise run build-and-push`. If Terraform apply fails with "Image '...' not found", run `mise run build-and-push` then re-run `terraform apply`.
- Crashes: Check logs, DB connectivity (ensure Neon active).
- SSL errors: Verify `DB_POSTGRESDB_SSL=require`.
- Compute exceeded: Upgrade Neon plan.
- Cold starts: Cloud Scheduler wakes service.
- Mise issues: `mise --version`; ensure tools installed.
- Domain mapping: Ensure domain is mapped in Cloud Run.

## Disaster Recovery

1. DB loss: Restore from Neon PITR/dump.
2. Service broken: Rollback image tag in TF, `mise run terraform:deploy`.
3. Compromised: Rotate secrets in Secret Manager, redeploy.

### Test Recovery

- Simulate failures monthly: Mock DB loss or service outage.
- Steps: Export data, delete resources, restore; verify workflows.

## Decommission Checklist

1. Remove public access: `gcloud run services remove-iam-policy-binding n8n --region=us-west1 --member="allUsers" --role="roles/run.invoker"`
2. Export data: `pg_dump ... > export.sql`; export workflows from UI.
3. Delete secrets: `gcloud secrets delete n8n-encryption-key n8n-db-password n8n-actual-password n8n-license-activation-key`
4. Delete images: `gcloud artifacts docker images delete ...`
5. Delete service: `gcloud run services delete n8n --region=us-west1`
6. Delete domain mapping: `gcloud run domain-mappings delete <DOMAIN> --region=us-west1`
7. TF destroy: `mise run terraform:destroy` (if added)
8. Clean up: GCS, IAM, Neon project.

## Weekly Checklist

- Health: Visit URL, test flows.
- Logs: Check for errors.
- DB: Verify Neon usage.
- Backups: Confirm recent exports.
- Rotate creds quarterly.

## Notes

- Offline: Export DB, delete project; keep backups.
- Neon: Auto-suspends after 5 min; monitor limits.
- Diagnostics: Disabled for privacy; no telemetry.
- Custom image: Includes startup.sh for DB delay and port mapping, installs @actual-app/api globally.
- Timezone: Asia/Jakarta.
- Actual Budget integration: Server URL https://budget.tifan.me, sync ID set.

## Known Issues

- Cold starts may delay workflows; mitigated with Cloud Scheduler wake-ups.
- Image push failures: Check IAM permissions before retrying.
- SSL errors: Ensure `DB_POSTGRESDB_SSL=require` in env vars.
- Runners insecure mode enabled for external modules like @actual-app/api.
