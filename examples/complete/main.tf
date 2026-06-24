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

  # Required
  project_id                   = "your-gcp-project-id"
  service_account              = "terraform-deployer@your-gcp-project-id.iam.gserviceaccount.com"
  partner                      = "your-company"
  agileday_base_url            = "https://api.agileday.io"
  artifact_registry_project_id = "ai-cv-match-471207" # Rakettitiede's registry

  # Optional: override region (default: europe-north1)
  region = "europe-west1"

  # Optional: override LLM model for Slack bots (default: gemini-3.5-flash)
  llm_model = "gemini-2.0-flash"

  # Optional: pin specific service versions instead of module defaults
  image_tags = {
    search_mcp  = "v3.12.4"
    pyry        = "v1.4.4"
    network_mcp = "v0.9.4"
  }

  # Optional: override Cloud Run resource limits (applies to all services)
  cloud_run_cpu           = "2"
  cloud_run_memory        = "1Gi"
  cloud_run_min_instances = 1
  cloud_run_max_instances = 20

  # Optional: override service names (useful for multi-environment deployments)
  # service_names = {
  #   search_mcp  = "prod-mcp-agileday"
  #   pyry        = "prod-pyry"
  #   network_mcp = "prod-mcp-talent-network"
  # }

  # Optional: self-host images in your own Artifact Registry (overrides the default above)
  # artifact_registry_project_id = "your-artifact-registry-project"

  # Rakettitiede only: federation partner URLs for Minna
  # partner_mcp_urls = {
  #   partner-a = "https://mcp-talent-network-xxxx.europe-north1.run.app"
  #   partner-b = "https://mcp-talent-network-yyyy.europe-north1.run.app"
  # }
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

# Rakettitiede only
output "minna_url" {
  description = "Minna federated Slack bot URL (Rakettitiede only)"
  value       = module.ai_talent.minna_url
}

output "topi_url" {
  description = "Topi bench Slack bot URL (Rakettitiede only)"
  value       = module.ai_talent.topi_url
}
