variable "project_id" {
  description = "Google Cloud project ID."
  type        = string
}

variable "region" {
  description = "Google Cloud region for deployment."
  type        = string
}

variable "db_password" {
  description = "External database password."
  type        = string
  sensitive   = true
}

variable "license_activation_key" {
  description = "Activation key for n8n license."
  type        = string
  sensitive   = true
}



variable "actual_password" {
  description = "Password for Actual server."
  type        = string
  sensitive   = true
}
