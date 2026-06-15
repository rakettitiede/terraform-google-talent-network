variable "project_id" {
  description = "GCP project ID — required, no default. Each partner uses their own project."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "Project ID must be 6-30 lowercase letters, digits, or hyphens, starting with a letter and ending with a letter or digit."
  }
}

variable "region" {
  description = "GCP region"
  type        = string
  default     = "europe-north1"

  validation {
    condition     = can(regex("^[a-z]+-[a-z]+[0-9]$", var.region))
    error_message = "Region must be a valid GCP region (e.g., europe-north1, us-central1)."
  }
}

variable "service_account" {
  description = "Service account email for all Cloud Run services. Must have roles: run.admin, artifactregistry.reader, storage.admin, secretmanager.secretAccessor, aiplatform.user."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*@[a-z][a-z0-9-]*\\.iam\\.gserviceaccount\\.com$", var.service_account))
    error_message = "Service account must be a valid GCP service account email (name@project.iam.gserviceaccount.com)."
  }
}

variable "partner" {
  description = "Partner identifier — unique per company. Used to prefix OpenAPI operationIds and to conditionally deploy Rakettitiede-specific services (Minna, Topi)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.partner))
    error_message = "Partner must be lowercase alphanumeric with hyphens, starting with a letter."
  }
}

variable "image_tags" {
  description = "Per-service Docker image tags. Defaults match this module version. Override to pin specific releases."
  type = object({
    search_mcp  = optional(string, "v3.12.4")
    pyry        = optional(string, "v1.4.4")
    network_mcp = optional(string, "v0.9.4")
    minna       = optional(string, "v1.9.0")
    bench_mcp   = optional(string, "v1.5.0")
    topi        = optional(string, "v1.5.0")
  })
  default = {}
}

variable "artifact_registry_project_id" {
  description = "GCP project hosting Docker images in Artifact Registry. Use 'ai-cv-match-471207' (Rakettitiede's registry) unless self-hosting images."
  type        = string
}

variable "agileday_base_url" {
  description = "Base URL for the AgileDay API that mcp-agileday queries."
  type        = string

  validation {
    condition     = can(regex("^https://", var.agileday_base_url))
    error_message = "AgileDay base URL must start with https://."
  }
}

variable "llm_model" {
  description = "LLM model name used by all Slack bots"
  type        = string
  default     = "gemini-3.5-flash"
}

variable "partner_mcp_urls" {
  description = "Map of OTHER partners' mcp-talent-network nodes that Minna federates over (Rakettitiede deployment only). Format: { partner = url }. The local node (keyed by var.partner) is added automatically."
  type        = map(string)
  default     = {}
}
