terraform {
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 7.0"
    }
  }

  backend "gcs" {
    bucket = "n8n-terraform-state-bucket"
    prefix = "n8n"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# APIs

resource "google_project_service" "run" {
  service            = "run.googleapis.com"
  disable_on_destroy = true
}

resource "google_project_service" "secretmanager" {
  service            = "secretmanager.googleapis.com"
  disable_on_destroy = true
}

resource "google_project_service" "cloudresourcemanager" {
  service            = "cloudresourcemanager.googleapis.com"
  disable_on_destroy = true
}

resource "google_project_service" "cloudscheduler" {
  service            = "cloudscheduler.googleapis.com"
  disable_on_destroy = true
}

resource "google_project_service" "serviceusage" {
  service            = "serviceusage.googleapis.com"
  disable_on_destroy = true
}

resource "google_project_service" "iam" {
  service            = "iam.googleapis.com"
  disable_on_destroy = true
}

resource "google_project_service" "artifactregistry" {
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = true
}

resource "google_project_service" "gmail" {
  service            = "gmail.googleapis.com"
  disable_on_destroy = true
}

resource "google_project_service" "pubsub" {
  service            = "pubsub.googleapis.com"
  disable_on_destroy = true
}

# REGISTRY

resource "google_artifact_registry_repository" "n8n_repo" {
  project                = var.project_id
  location               = var.region
  repository_id          = "n8n-repo"
  description            = "Repository for n8n workflow images"
  format                 = "DOCKER"
  cleanup_policy_dry_run = false
  cleanup_policies {
    id     = "delete-untagged"
    action = "DELETE"
    condition {
      tag_state = "UNTAGGED"
    }
  }
  cleanup_policies {
    id     = "keep-new-untagged"
    action = "KEEP"
    condition {
      tag_state  = "UNTAGGED"
      newer_than = "7d"
    }
  }
  cleanup_policies {
    id     = "delete-old-tagged"
    action = "DELETE"
    condition {
      tag_state  = "TAGGED"
      older_than = "30d"
    }
  }
  cleanup_policies {
    id     = "keep-minimum-versions"
    action = "KEEP"
    most_recent_versions {
      keep_count = 5
    }
  }
  depends_on = [google_project_service.artifactregistry]
}

# PUBSUB

resource "google_pubsub_topic" "n8n_gmail_notifications" {
  name       = "n8n-gmail-notifications"
  project    = var.project_id
  depends_on = [google_project_service.pubsub]
}

resource "google_pubsub_topic_iam_member" "gmail_push_publisher" {
  topic   = google_pubsub_topic.n8n_gmail_notifications.name
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:gmail-api-push@system.gserviceaccount.com"
  project = var.project_id
}

resource "google_pubsub_subscription" "n8n_push_subscription" {
  name  = "n8n-push-subscription"
  topic = google_pubsub_topic.n8n_gmail_notifications.name

  push_config {
    push_endpoint = "https://${local.domain}/webhook/gmail-event?key=${var.webhook_auth_key}"
  }

  project = var.project_id

  depends_on = [google_pubsub_topic.n8n_gmail_notifications]
}

resource "google_pubsub_subscription" "n8n_push_subscription_test" {
  name  = "n8n-push-subscription-test"
  topic = google_pubsub_topic.n8n_gmail_notifications.name

  push_config {
    push_endpoint = "https://${local.domain}/webhook-test/gmail-event?key=${var.webhook_auth_key}"
  }

  project = var.project_id

  depends_on = [google_pubsub_topic.n8n_gmail_notifications]
}

# SECRETS

resource "google_secret_manager_secret" "actual_password_secret" {
  secret_id = "n8n-actual-password"
  project   = var.project_id
  replication {
    auto {}
  }
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "actual_password_secret_version" {
  secret      = google_secret_manager_secret.actual_password_secret.id
  secret_data = var.actual_password
}

resource "google_secret_manager_secret" "db_password_secret" {
  secret_id = "n8n-db-password"
  project   = var.project_id
  replication {
    auto {}
  }
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "db_password_version" {
  secret      = google_secret_manager_secret.db_password_secret.id
  secret_data = var.db_password
}

resource "random_password" "n8n_encryption_key" {
  length  = 32
  special = false
}

resource "google_secret_manager_secret" "encryption_key_secret" {
  secret_id = "n8n-encryption-key"
  project   = var.project_id
  replication {
    auto {}
  }
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "encryption_key_secret_version" {
  secret      = google_secret_manager_secret.encryption_key_secret.id
  secret_data = random_password.n8n_encryption_key.result
}

resource "google_secret_manager_secret" "license_activation_key_secret" {
  secret_id = "n8n-license-activation-key"
  project   = var.project_id
  replication {
    auto {}
  }
  depends_on = [google_project_service.secretmanager]
}

resource "google_secret_manager_secret_version" "license_activation_key_secret_version" {
  secret      = google_secret_manager_secret.license_activation_key_secret.id
  secret_data = var.license_activation_key
}

# CLOUD RUN SERVICE ACCOUNT

resource "google_service_account" "n8n_sa" {
  account_id   = "n8n-service-account"
  display_name = "n8n Service Account for Cloud Run"
  project      = var.project_id
}

resource "google_service_account_iam_member" "ci_sa_n8n_sa_user" {
  service_account_id = google_service_account.n8n_sa.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.ci_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "actual_password_secret_accessor" {
  project   = google_secret_manager_secret.actual_password_secret.project
  secret_id = google_secret_manager_secret.actual_password_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.n8n_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "db_password_secret_accessor" {
  project   = google_secret_manager_secret.db_password_secret.project
  secret_id = google_secret_manager_secret.db_password_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.n8n_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "encryption_key_secret_accessor" {
  project   = google_secret_manager_secret.encryption_key_secret.project
  secret_id = google_secret_manager_secret.encryption_key_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.n8n_sa.email}"
}

resource "google_secret_manager_secret_iam_member" "license_activation_key_secret_accessor" {
  project   = google_secret_manager_secret.license_activation_key_secret.project
  secret_id = google_secret_manager_secret.license_activation_key_secret.secret_id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.n8n_sa.email}"
}

# CI SERVICE ACCOUNT

resource "google_service_account" "ci_sa" {
  account_id   = "n8n-ci-sa"
  display_name = "CI Service Account"
  project      = var.project_id
}

resource "google_project_iam_member" "ci_sa_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

resource "google_project_iam_member" "ci_sa_artifact_writer" {
  project = var.project_id
  role    = "roles/artifactregistry.repoAdmin"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

resource "google_project_iam_member" "ci_sa_storage_admin" {
  project = var.project_id
  role    = "roles/storage.admin"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

resource "google_project_iam_member" "ci_sa_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

resource "google_project_iam_member" "ci_sa_service_usage_admin" {
  project = var.project_id
  role    = "roles/serviceusage.serviceUsageAdmin"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

resource "google_project_iam_member" "ci_sa_iam_admin" {
  project = var.project_id
  role    = "roles/iam.serviceAccountAdmin"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

resource "google_project_iam_member" "ci_sa_secret_viewer" {
  project = var.project_id
  role    = "roles/secretmanager.viewer"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

resource "google_project_iam_member" "ci_sa_project_iam_admin" {
  project = var.project_id
  role    = "roles/resourcemanager.projectIamAdmin"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

resource "google_project_iam_member" "ci_sa_cloudscheduler_viewer" {
  project = var.project_id
  role    = "roles/cloudscheduler.viewer"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

resource "google_project_iam_member" "ci_sa_secret_version_manager" {
  project = var.project_id
  role    = "roles/secretmanager.secretVersionManager"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

resource "google_project_iam_member" "ci_sa_sa_key_admin" {
  project = var.project_id
  role    = "roles/iam.serviceAccountKeyAdmin"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

resource "google_project_iam_member" "ci_sa_pubsub_admin" {
  project = var.project_id
  role    = "roles/pubsub.admin"
  member  = "serviceAccount:${google_service_account.ci_sa.email}"
}

resource "google_service_account_key" "ci_sa_key" {
  service_account_id = google_service_account.ci_sa.name
}

# CLOUD RUN

locals {
  domain         = "n8n.tifan.me"
  container_port = "5678"
  n8n_port       = "443" // 443 if using custom image, else 5678
}

resource "google_cloud_run_v2_service" "n8n" {
  name     = "n8n"
  location = var.region
  project  = var.project_id

  ingress             = "INGRESS_TRAFFIC_ALL"
  deletion_protection = false

  template {
    service_account = google_service_account.n8n_sa.email
    scaling {
      max_instance_count = 1
      min_instance_count = 0
    }
    containers {
      image = "${var.region}-docker.pkg.dev/${var.project_id}/n8n-repo/n8n:latest"

      ports {
        container_port = local.container_port
      }
      resources {
        limits = {
          cpu    = "1"
          memory = "512Mi"
        }
        startup_cpu_boost = true
        cpu_idle          = false # This is --no-cpu-throttling
      }

      env {
        name  = "N8N_PATH"
        value = "/"
      }
      env {
        name  = "N8N_PORT"
        value = local.n8n_port
      }
      env {
        name  = "N8N_PROTOCOL"
        value = "https"
      }
      env {
        name  = "DB_TYPE"
        value = "postgresdb"
      }
      env {
        name  = "DB_POSTGRESDB_DATABASE"
        value = "neondb"
      }
      env {
        name  = "DB_POSTGRESDB_USER"
        value = "neondb_owner"
      }
      env {
        name  = "DB_POSTGRESDB_HOST"
        value = "ep-plain-mountain-afhf98oq-pooler.c-2.us-west-2.aws.neon.tech"
      }
      env {
        name  = "DB_POSTGRESDB_PORT"
        value = "5432"
      }
      env {
        name  = "DB_POSTGRESDB_SCHEMA"
        value = "public"
      }
      env {
        name  = "DB_POSTGRESDB_SSL"
        value = "require"
      }
      env {
        name  = "DB_POSTGRESDB_SSL_REJECT_UNAUTHORIZED"
        value = "false"
      }
      env {
        name  = "N8N_USER_FOLDER"
        value = "/home/node"
      }
      env {
        name  = "GENERIC_TIMEZONE"
        value = "Asia/Jakarta"
      }
      env {
        name  = "QUEUE_HEALTH_CHECK_ACTIVE"
        value = "true"
      }
      env {
        name = "DB_POSTGRESDB_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.db_password_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "N8N_ENCRYPTION_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.encryption_key_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "N8N_LICENSE_ACTIVATION_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.license_activation_key_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "N8N_HIDE_USAGE_PAGE"
        value = "true"
      }
      env {
        name  = "N8N_HOST"
        value = local.domain
      }
      env {
        name  = "WEBHOOK_URL"
        value = "https://${local.domain}"
      }
      env {
        name  = "N8N_EDITOR_BASE_URL"
        value = "https://${local.domain}"
      }
      env {
        name  = "N8N_RUNNERS_ENABLED"
        value = "true"
      }
      env {
        name  = "N8N_PROXY_HOPS"
        value = "1"
      }
      env {
        name  = "NODE_FUNCTION_ALLOW_EXTERNAL"
        value = "@actual-app/api"
      }
      env {
        # Enabled insecure mode if using ALLOW_EXTERNAL, else Code executions hangs
        name  = "N8N_RUNNERS_INSECURE_MODE"
        value = "true"
      }
      env {
        name  = "N8N_RUNNERS_ALLOW_PROTOTYPE_MUTATION"
        value = "true"
      }
      env {
        name  = "NODE_FUNCTION_ALLOW_BUILTIN"
        value = "*"
      }

      env {
        name  = "ACTUAL_SERVER_URL"
        value = "https://budget.tifan.me"
      }
      env {
        name  = "ACTUAL_SYNC_ID"
        value = "278a95d3-2467-4941-8125-24765283a859"
      }
      env {
        name = "ACTUAL_PASSWORD"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.actual_password_secret.secret_id
            version = "latest"
          }
        }
      }

      # Disable diagnostics
      env {
        name  = "N8N_DIAGNOSTICS_ENABLED"
        value = "false"
      }
      env {
        name  = "N8N_VERSION_NOTIFICATIONS_ENABLED"
        value = "false"
      }
      env {
        name  = "EXTERNAL_FRONTEND_HOOKS_URLS"
        value = ""
      }
      env {
        name  = "N8N_DIAGNOSTICS_CONFIG_FRONTEND"
        value = ""
      }
      env {
        name  = "N8N_DIAGNOSTICS_CONFIG_BACKEND"
        value = ""
      }

      # Security
      env {
        name  = "N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS"
        value = "true"
      }
      env {
        name  = "N8N_BLOCK_ENV_ACCESS_IN_NODE	"
        value = "false" # default is true
      }
      env {
        name  = "N8N_GIT_NODE_DISABLE_BARE_REPOS	"
        value = "true"
      }

      env {
        # https://docs.n8n.io/hosting/configuration/environment-variables/endpoints/
        # The interval (in seconds) at which the insights data should be flushed to the database.
        # Defaults to 30 seconds, which triggers the runtime
        name  = "N8N_INSIGHTS_FLUSH_INTERVAL_SECONDS"
        value = "1800"
      }
      env {
        # https://docs.n8n.io/hosting/configuration/environment-variables/logs/#n8n-logs
        # Output logs without ANSI colors
        name  = "NO_COLOR"
        value = "true"
      }
      env {
        name  = "NODES_EXCLUDE"
        value = "[]"
      }

      startup_probe {
        initial_delay_seconds = 30
        timeout_seconds       = 240
        period_seconds        = 240
        failure_threshold     = 3
        http_get {
          path = "/healthz/readiness"
          port = local.container_port
        }
      }
    }
  }

  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  depends_on = [
    google_project_service.run,
    google_secret_manager_secret_iam_member.actual_password_secret_accessor,
    google_secret_manager_secret_iam_member.db_password_secret_accessor,
    google_secret_manager_secret_iam_member.encryption_key_secret_accessor,
    google_secret_manager_secret_iam_member.license_activation_key_secret_accessor
  ]
}

resource "google_cloud_run_v2_service_iam_member" "n8n_public_invoker" {
  project  = google_cloud_run_v2_service.n8n.project
  location = google_cloud_run_v2_service.n8n.location
  name     = google_cloud_run_v2_service.n8n.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# DOMAIN MAPPING

resource "google_cloud_run_domain_mapping" "n8n_domain" {
  count    = 1
  name     = local.domain
  location = var.region
  metadata {
    namespace = var.project_id
  }
  spec {
    route_name = google_cloud_run_v2_service.n8n.name
  }
}

# CLOUD SCHEDULER

resource "google_cloud_scheduler_job" "n8n_wake_up" {
  for_each = { for idx, time in ["55 5 * * 0"] : idx => time }

  description = "Wake up n8n at specified times"
  name        = "n8n-wake-up-${each.key}"
  schedule    = each.value
  time_zone   = "Asia/Jakarta"

  http_target {
    uri         = "https://${local.domain}"
    http_method = "GET"
  }

  retry_config {
    retry_count = 3
  }

  depends_on = [google_project_service.cloudscheduler]
}
