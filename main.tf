# talent-network — full ecosystem deployment
# Deploys internal search (Pyry), federation node (ai-talent-network-mcp),
# and for Rakettitiede: Minna (federated Slack bot) + Topi (bench Slack bot)

locals {
  is_rakettitiede = var.partner == "rakettitiede"
}

# ── Runtime service account ──────────────────────────────────────────────────
# Minimal permissions for Cloud Run services. Separate from terraform-deployer
# to reduce blast radius if a service is compromised.

resource "google_service_account" "runtime" {
  project      = var.project_id
  account_id   = "talent-network-runtime"
  display_name = "Talent Network Runtime"
  description  = "Service account for Cloud Run services with minimal permissions"
}

resource "google_project_iam_member" "runtime_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_project_iam_member" "runtime_vertex_user" {
  project = var.project_id
  role    = "roles/aiplatform.user"
  member  = "serviceAccount:${google_service_account.runtime.email}"
}

# ── Internal search ──────────────────────────────────────────────────────────

resource "google_artifact_registry_repository" "search_mcp" {
  project       = var.project_id
  repository_id = var.service_names.search_mcp
  format        = "DOCKER"
  location      = var.region
}

resource "google_cloud_run_v2_service" "search_mcp" {
  project             = var.project_id
  name                = var.service_names.search_mcp
  location            = var.region
  deletion_protection = false

  template {
    service_account                  = google_service_account.runtime.email
    max_instance_request_concurrency = 80
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    containers {
      image = "${var.region}-docker.pkg.dev/${var.artifact_registry_project_id}/${var.service_names.search_mcp}/${var.service_names.search_mcp}:${var.image_tags.search_mcp}"
      resources {
        cpu_idle = true
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
      }
      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "PARTNER"
        value = var.partner
      }
      env {
        name  = "GCS_BUCKET"
        value = google_storage_bucket.search_mcp_db.name
      }
      env {
        name  = "AGILEDAY_BASE_URL"
        value = var.agileday_base_url
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GCP_LOCATION"
        value = var.region
      }
      env {
        name = "GOOGLE_CLIENT_ID"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.search_mcp_client_id.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "GOOGLE_CLIENT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.search_mcp_client_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.search_mcp_api_key.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "PARTNER_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.partner_secret.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_iam_member.runtime_secret_accessor,
    google_secret_manager_secret_version.search_mcp_client_id,
    google_secret_manager_secret_version.search_mcp_client_secret,
    google_secret_manager_secret_version.search_mcp_api_key,
    google_secret_manager_secret_version.partner_secret
  ]
}

resource "google_cloud_run_v2_service_iam_member" "search_mcp_public" {
  project  = var.project_id
  name     = google_cloud_run_v2_service.search_mcp.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_storage_bucket" "search_mcp_db" {
  project                     = var.project_id
  name                        = "${var.project_id}-search-mcp-db"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  versioning { enabled = true }
}

resource "google_storage_bucket_iam_member" "search_mcp_db" {
  bucket = google_storage_bucket.search_mcp_db.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret" "search_mcp_client_id" {
  project   = var.project_id
  secret_id = "search-mcp-google-client-id"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "search_mcp_client_id" {
  secret      = google_secret_manager_secret.search_mcp_client_id.id
  secret_data = "unused"
}

resource "google_secret_manager_secret" "search_mcp_client_secret" {
  project   = var.project_id
  secret_id = "search-mcp-google-client-secret"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "search_mcp_client_secret" {
  secret      = google_secret_manager_secret.search_mcp_client_secret.id
  secret_data = "unused"
}

resource "random_password" "search_mcp_api_key" {
  length  = 64
  special = false

  keepers = {
    image_tag = var.image_tags.search_mcp
  }
}

resource "google_secret_manager_secret" "search_mcp_api_key" {
  project   = var.project_id
  secret_id = "ai-talent-search-mcp-api-key"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "search_mcp_api_key" {
  secret      = google_secret_manager_secret.search_mcp_api_key.id
  secret_data = random_password.search_mcp_api_key.result
}

# Partner secret — shared between mcp-agileday and ai-talent-network-mcp
# Used for deterministic anonymous candidate IDs (HMAC-SHA256)
resource "random_password" "partner_secret" {
  length  = 64
  special = false
}

resource "google_secret_manager_secret" "partner_secret" {
  project   = var.project_id
  secret_id = "partner-secret"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "partner_secret" {
  secret      = google_secret_manager_secret.partner_secret.id
  secret_data = random_password.partner_secret.result
}

# ── Pyry (internal Slack bot) ─────────────────────────────────────────────────

resource "google_artifact_registry_repository" "pyry" {
  project       = var.project_id
  repository_id = var.service_names.pyry
  format        = "DOCKER"
  location      = var.region
}

resource "google_cloud_run_v2_service" "pyry" {
  project             = var.project_id
  name                = var.service_names.pyry
  location            = var.region
  deletion_protection = false

  template {
    service_account                  = google_service_account.runtime.email
    max_instance_request_concurrency = 80
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    containers {
      image = "${var.region}-docker.pkg.dev/${var.artifact_registry_project_id}/${var.service_names.pyry}/${var.service_names.pyry}:${var.image_tags.pyry}"
      resources {
        cpu_idle = true
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
      }
      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GCP_LOCATION"
        value = var.region
      }
      env {
        name  = "LLM_MODEL"
        value = var.llm_model
      }
      env {
        name  = "MCP_API_URL"
        value = google_cloud_run_v2_service.search_mcp.uri
      }
      env {
        name = "SLACK_BOT_TOKEN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.pyry_bot_token.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "SLACK_SIGNING_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.pyry_signing_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name  = "PYRY_URL"
        value = google_cloud_run_v2_service.pyry.uri
      }
      env {
        name  = "API_ALLOWED_CALLERS"
        value = var.pyry_api_allowed_callers
      }
    }
  }

  depends_on = [
    google_project_iam_member.runtime_secret_accessor,
    google_secret_manager_secret.pyry_bot_token,
    google_secret_manager_secret.pyry_signing_secret
  ]
}

resource "google_cloud_run_v2_service_iam_member" "pyry_public" {
  project  = var.project_id
  name     = google_cloud_run_v2_service.pyry.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_secret_manager_secret" "pyry_bot_token" {
  project   = var.project_id
  secret_id = "pyry-bot-token"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret" "pyry_signing_secret" {
  project   = var.project_id
  secret_id = "pyry-slack-signing-secret"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

# ── Federation node ───────────────────────────────────────────────────────────

resource "google_artifact_registry_repository" "network_mcp" {
  project       = var.project_id
  repository_id = var.service_names.network_mcp
  format        = "DOCKER"
  location      = var.region
}

resource "google_cloud_run_v2_service" "network_mcp" {
  project             = var.project_id
  name                = var.service_names.network_mcp
  location            = var.region
  deletion_protection = false

  template {
    service_account                  = google_service_account.runtime.email
    max_instance_request_concurrency = 80
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    containers {
      image = "${var.region}-docker.pkg.dev/${var.artifact_registry_project_id}/${var.service_names.network_mcp}/${var.service_names.network_mcp}:${var.image_tags.network_mcp}"
      resources {
        cpu_idle = true
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
      }
      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GCP_LOCATION"
        value = var.region
      }
      env {
        name  = "PARTNER"
        value = var.partner
      }
      env {
        name  = "GCS_BUCKET"
        value = google_storage_bucket.network_db.name
      }
      env {
        name  = "AGILEDAY_BASE_URL"
        value = var.agileday_base_url
      }
      env {
        name = "GOOGLE_CLIENT_ID"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.network_client_id.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "GOOGLE_CLIENT_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.network_client_secret.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.network_mcp_api_key.secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "PARTNER_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.partner_secret.secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_iam_member.runtime_secret_accessor,
    google_secret_manager_secret_version.network_client_id,
    google_secret_manager_secret_version.network_client_secret,
    google_secret_manager_secret_version.network_mcp_api_key,
    google_secret_manager_secret_version.partner_secret
  ]
}

resource "google_cloud_run_v2_service_iam_member" "network_mcp_public" {
  project  = var.project_id
  name     = google_cloud_run_v2_service.network_mcp.name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_storage_bucket" "network_db" {
  project                     = var.project_id
  name                        = "${var.project_id}-talent-network-db"
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  versioning { enabled = true }
}

resource "google_storage_bucket_iam_member" "network_db" {
  bucket = google_storage_bucket.network_db.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.runtime.email}"
}

resource "google_secret_manager_secret" "network_client_id" {
  project   = var.project_id
  secret_id = "talent-network-google-client-id"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "network_client_id" {
  secret      = google_secret_manager_secret.network_client_id.id
  secret_data = "unused"
}

resource "google_secret_manager_secret" "network_client_secret" {
  project   = var.project_id
  secret_id = "talent-network-google-client-secret"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "network_client_secret" {
  secret      = google_secret_manager_secret.network_client_secret.id
  secret_data = "unused"
}

resource "random_password" "network_mcp_api_key" {
  length  = 64
  special = false

  keepers = {
    image_tag = var.image_tags.network_mcp
  }
}

resource "google_secret_manager_secret" "network_mcp_api_key" {
  project   = var.project_id
  secret_id = "ai-talent-network-mcp-api-key"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "network_mcp_api_key" {
  secret      = google_secret_manager_secret.network_mcp_api_key.id
  secret_data = random_password.network_mcp_api_key.result
}

# ── Minna (Rakettitiede only) ─────────────────────────────────────────────────

resource "google_artifact_registry_repository" "minna" {
  count         = local.is_rakettitiede ? 1 : 0
  project       = var.project_id
  repository_id = var.service_names.minna
  format        = "DOCKER"
  location      = var.region
}

resource "google_cloud_run_v2_service" "minna" {
  count               = local.is_rakettitiede ? 1 : 0
  project             = var.project_id
  name                = var.service_names.minna
  location            = var.region
  deletion_protection = false

  template {
    service_account                  = google_service_account.runtime.email
    max_instance_request_concurrency = 80
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    containers {
      image = "${var.region}-docker.pkg.dev/${var.artifact_registry_project_id}/${var.service_names.minna}/${var.service_names.minna}:${var.image_tags.minna}"
      resources {
        cpu_idle = true
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
      }
      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GCP_LOCATION"
        value = var.region
      }
      env {
        name  = "LLM_MODEL"
        value = var.llm_model
      }
      env {
        name  = "MCP_API_URL"
        value = google_cloud_run_v2_service.network_mcp.uri
      }
      env {
        name = "MCP_API_URLS"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.minna_mcp_api_urls[0].secret_id
            version = "latest"
          }
        }
      }
      env {
        # Multi-workspace bot-token map (team_id -> xoxb). Preferred over SLACK_BOT_TOKEN.
        name = "SLACK_BOT_TOKENS"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.minna_bot_tokens[0].secret_id
            version = "latest"
          }
        }
      }
      env {
        # Single-token fallback, used when a workspace is not in SLACK_BOT_TOKENS.
        name = "SLACK_BOT_TOKEN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.minna_bot_token[0].secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "SLACK_SIGNING_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.minna_signing_secret[0].secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_iam_member.runtime_secret_accessor,
    google_secret_manager_secret_version.minna_mcp_api_urls
  ]
}

resource "google_cloud_run_v2_service_iam_member" "minna_public" {
  count    = local.is_rakettitiede ? 1 : 0
  project  = var.project_id
  name     = google_cloud_run_v2_service.minna[0].name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_secret_manager_secret" "minna_bot_token" {
  count     = local.is_rakettitiede ? 1 : 0
  project   = var.project_id
  secret_id = "minna-bot-token"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

# Multi-workspace bot-token map: JSON object of { team_id: "xoxb-..." }. Value added manually.
resource "google_secret_manager_secret" "minna_bot_tokens" {
  count     = local.is_rakettitiede ? 1 : 0
  project   = var.project_id
  secret_id = "minna-bot-tokens"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret" "minna_signing_secret" {
  count     = local.is_rakettitiede ? 1 : 0
  project   = var.project_id
  secret_id = "minna-slack-signing-secret"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret" "minna_mcp_api_urls" {
  count     = local.is_rakettitiede ? 1 : 0
  project   = var.project_id
  secret_id = "minna-mcp-api-urls"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "minna_mcp_api_urls" {
  count  = local.is_rakettitiede ? 1 : 0
  secret = google_secret_manager_secret.minna_mcp_api_urls[0].id
  secret_data = jsonencode(merge(
    { (var.partner) = google_cloud_run_v2_service.network_mcp.uri },
    var.partner_mcp_urls
  ))
}

# ── Topi + bench (Rakettitiede only) ─────────────────────────────────────────

resource "google_artifact_registry_repository" "bench_mcp" {
  count         = local.is_rakettitiede ? 1 : 0
  project       = var.project_id
  repository_id = var.service_names.bench_mcp
  format        = "DOCKER"
  location      = var.region
}

resource "google_cloud_run_v2_service" "bench_mcp" {
  count               = local.is_rakettitiede ? 1 : 0
  project             = var.project_id
  name                = var.service_names.bench_mcp
  location            = var.region
  deletion_protection = false

  template {
    service_account                  = google_service_account.runtime.email
    max_instance_request_concurrency = 80
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    containers {
      image = "${var.region}-docker.pkg.dev/${var.artifact_registry_project_id}/${var.service_names.bench_mcp}/${var.service_names.bench_mcp}:${var.image_tags.bench_mcp}"
      resources {
        cpu_idle = true
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
      }
      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name = "API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.bench_mcp_api_key[0].secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_iam_member.runtime_secret_accessor
  ]
}

resource "google_cloud_run_v2_service_iam_member" "bench_mcp_public" {
  count    = local.is_rakettitiede ? 1 : 0
  project  = var.project_id
  name     = google_cloud_run_v2_service.bench_mcp[0].name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_artifact_registry_repository" "topi" {
  count         = local.is_rakettitiede ? 1 : 0
  project       = var.project_id
  repository_id = var.service_names.topi
  format        = "DOCKER"
  location      = var.region
}

resource "google_cloud_run_v2_service" "topi" {
  count               = local.is_rakettitiede ? 1 : 0
  project             = var.project_id
  name                = var.service_names.topi
  location            = var.region
  deletion_protection = false

  template {
    service_account                  = google_service_account.runtime.email
    max_instance_request_concurrency = 80
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }
    containers {
      image = "${var.region}-docker.pkg.dev/${var.artifact_registry_project_id}/${var.service_names.topi}/${var.service_names.topi}:${var.image_tags.topi}"
      resources {
        cpu_idle = true
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
      }
      env {
        name  = "NODE_ENV"
        value = "production"
      }
      env {
        name  = "GCP_PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "GCP_LOCATION"
        value = var.region
      }
      env {
        name  = "LLM_MODEL"
        value = var.llm_model
      }
      env {
        name  = "BENCH_MCP_URL"
        value = google_cloud_run_v2_service.bench_mcp[0].uri
      }
      env {
        name = "SLACK_BOT_TOKEN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.topi_bot_token[0].secret_id
            version = "latest"
          }
        }
      }
      env {
        name = "SLACK_SIGNING_SECRET"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.topi_signing_secret[0].secret_id
            version = "latest"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_iam_member.runtime_secret_accessor
  ]
}

resource "google_cloud_run_v2_service_iam_member" "topi_public" {
  count    = local.is_rakettitiede ? 1 : 0
  project  = var.project_id
  name     = google_cloud_run_v2_service.topi[0].name
  location = var.region
  role     = "roles/run.invoker"
  member   = "allUsers"
}

resource "google_secret_manager_secret" "topi_bot_token" {
  count     = local.is_rakettitiede ? 1 : 0
  project   = var.project_id
  secret_id = "topi-bot-token"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret" "topi_signing_secret" {
  count     = local.is_rakettitiede ? 1 : 0
  project   = var.project_id
  secret_id = "topi-slack-signing-secret"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "random_password" "bench_mcp_api_key" {
  count   = local.is_rakettitiede ? 1 : 0
  length  = 64
  special = false

  keepers = {
    image_tag = var.image_tags.bench_mcp
  }
}

resource "google_secret_manager_secret" "bench_mcp_api_key" {
  count     = local.is_rakettitiede ? 1 : 0
  project   = var.project_id
  secret_id = "ai-talent-bench-mcp-api-key"
  replication {
    user_managed {
      replicas {
        location = var.region
      }
    }
  }
}

resource "google_secret_manager_secret_version" "bench_mcp_api_key" {
  count       = local.is_rakettitiede ? 1 : 0
  secret      = google_secret_manager_secret.bench_mcp_api_key[0].id
  secret_data = random_password.bench_mcp_api_key[0].result
}
