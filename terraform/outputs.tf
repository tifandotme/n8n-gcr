output "base64_encoded_service_account_json" {
  description = "CI Service Account Key"
  value       = google_service_account_key.ci_sa_key.private_key
  sensitive   = true
}
