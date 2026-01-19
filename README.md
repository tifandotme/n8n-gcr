# n8n on Cloud Run

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
7. URL: Check in GCP Console or visit https://<DOMAIN>
8. Images: `gcloud artifacts docker images list --location=us-west1 --repository=n8n-repo --project <PROJECT>`
9. DB Connect: `psql "postgresql://neondb_owner:<PASSWORD>@<NEON_HOST>/neondb?sslmode=require"`

## Backups & Recovery (Neon)

- Automated: Point-in-time recovery (7 days free tier).
- Manual: `pg_dump "postgresql://neondb_owner:<PASSWORD>@<NEON_HOST>/neondb?sslmode=require" > backup.sql`
- Restore: Import to new Neon project/branch.
- Test: Periodically verify restores.

## Security Hardening

- Least privilege on service accounts.
- Audit logs; HTTPS enforced.
- Diagnostics disabled: No telemetry sent to n8n servers.
- Enforce settings file permissions, block env access in node (false), disable bare repos in git node.
- Runners enabled with insecure mode for external modules.

## Disaster Recovery

1. DB loss: Restore from Neon PITR/dump.
2. Service broken: Rollback image tag in TF, `terraform apply`.
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
7. TF destroy: `terraform destroy` (pass to user)
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
