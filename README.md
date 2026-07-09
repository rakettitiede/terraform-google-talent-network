# terraform-google-talent-network

[![Terraform Registry](https://img.shields.io/badge/terraform-registry-623CE4?logo=terraform)](https://registry.terraform.io/modules/rakettitiede/talent-network/google/latest)

Terraform module for deploying the [talent-network](https://github.com/rakettitiede/ai-talent-platform) ecosystem on GCP.

## Overview

This module deploys a talent search system that lets consultancies find the right people for projects — both internally and across partner companies.

For each partner, three services are deployed to your own GCP project:

- **mcp-agileday** — search backend that indexes your consultant data from AgileDay
- **Pyry** — Slack bot for internal searches ("Find a senior React developer with fintech experience")
- **mcp-talent-network** — federation node that exposes an anonymized view of your consultants to the Minna network

All candidate data is stored in your own GCP environment (Cloud Storage buckets). Rakettitiede does not have access to your consultant database — only the anonymized search results you choose to expose via the federation node.

**Minna (Rakettitiede only):** Aggregates search results across all partner nodes, enabling cross-company talent discovery while preserving privacy.

## Quick Start

For full setup instructions including GCP setup, Slack app configuration, and federation onboarding, see the [Partner Onboarding Guide](https://github.com/rakettitiede/terraform-google-talent-network/blob/main/docs/partner-onboarding.md).

**main.tf:**
```hcl
locals {
  project_id         = "YOUR_PROJECT_ID"
  region             = "europe-north1"
  deployer_sa_email  = "terraform-deployer@${local.project_id}.iam.gserviceaccount.com"
}

terraform {
  required_version = ">= 1.7"

  backend "gcs" {
    bucket                      = "YOUR_PROJECT_ID-terraform-state"
    prefix                      = "talent-network"
    impersonate_service_account = "terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com"
  }
}

# Default provider for other infrastructure (optional)
provider "google" {
  project = local.project_id
  region  = local.region
}

# Provider with impersonation for the talent-network module
provider "google" {
  alias                       = "deployer"
  project                     = local.project_id
  region                      = local.region
  impersonate_service_account = local.deployer_sa_email
}

module "ai_talent" {
  source  = "rakettitiede/talent-network/google"
  version = "~> X.0" # Check registry for latest version

  providers = {
    google = google.deployer
  }

  project_id                   = local.project_id
  partner                      = "your-partner-id"
  agileday_base_url            = "https://api.agileday.io"
  artifact_registry_project_id = "ai-cv-match-471207" # Rakettitiede's registry
}

output "pyry_url" { value = module.ai_talent.pyry_url }
output "search_mcp_url" { value = module.ai_talent.search_mcp_url }
output "network_mcp_url" { value = module.ai_talent.network_mcp_url }
```

**Deploy:**
```bash
terraform init
terraform apply
```

## Documentation

- [Partner Onboarding Guide](https://github.com/rakettitiede/terraform-google-talent-network/blob/main/docs/partner-onboarding.md) — full setup walkthrough
- [Security Model](https://github.com/rakettitiede/terraform-google-talent-network/blob/main/docs/security.md) — IAM, authentication, and data privacy
- [Examples](https://github.com/rakettitiede/terraform-google-talent-network/tree/main/examples) — ready-to-use configurations
