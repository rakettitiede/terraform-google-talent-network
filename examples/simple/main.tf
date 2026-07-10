locals {
  project_id        = "YOUR_PROJECT_ID"
  region            = "europe-north1"
  deployer_sa_email = "terraform-deployer@${local.project_id}.iam.gserviceaccount.com"
}

terraform {
  required_version = ">= 1.7"

  backend "gcs" {
    bucket                      = "YOUR_PROJECT_ID-terraform-state"
    prefix                      = "talent-network"
    impersonate_service_account = "terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com"
  }
}

provider "google" {
  project = local.project_id
  region  = local.region
}

provider "google" {
  alias                       = "deployer"
  project                     = local.project_id
  region                      = local.region
  impersonate_service_account = local.deployer_sa_email
}

module "ai_talent" {
  source  = "rakettitiede/talent-network/google"
  version = "~> 0.0"

  providers = {
    google = google.deployer
  }

  project_id        = local.project_id
  partner           = "your-company"
  agileday_base_url = "https://api.agileday.io"

  # Rakettitiede's Artifact Registry — contains pre-built Docker images
  artifact_registry_project_id = "ai-cv-match-471207"
}

output "pyry_url" {
  description = "Slack bot URL — configure in Slack app Event Subscriptions"
  value       = module.ai_talent.pyry_url
}

output "search_mcp_url" {
  description = "Internal search MCP server URL"
  value       = module.ai_talent.search_mcp_url
}

output "network_mcp_url" {
  description = "Federation node URL — share with Rakettitiede to join Minna network"
  value       = module.ai_talent.network_mcp_url
}
