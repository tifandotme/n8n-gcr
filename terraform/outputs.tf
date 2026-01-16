output "ci_sa_key" {
  description = "CI Service Account Key"
  value       = google_service_account_key.ci_sa_key.private_key
  sensitive   = true
}
