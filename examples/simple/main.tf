terraform {
  required_version = ">= 1.7"

  backend "gcs" {
    bucket = "YOUR_PROJECT_ID-terraform-state"
    prefix = "talent-network"
  }
}

provider "google" {
  project = "YOUR_PROJECT_ID"
  region  = "europe-north1"
}

module "ai_talent" {
  source  = "rakettitiede/talent-network/google"
  version = "~> 0.0"

  project_id        = "your-gcp-project-id"
  service_account   = "terraform-deployer@your-gcp-project-id.iam.gserviceaccount.com"
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
