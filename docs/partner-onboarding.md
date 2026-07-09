# Partner Onboarding Guide

Deploy Pyry (Slack talent search) and join the Minna federation (cross-company search).

## Prerequisites

- GCP project with billing
- AgileDay account
- Slack workspace admin access
- Terraform >= 1.7, gcloud CLI

---

## Phase 1: GCP Setup

Services run on Google Cloud. This phase enables required APIs and creates a service account for Terraform.

The module creates a **runtime service account** (`talent-network-runtime`) with minimal permissions for Cloud Run services. You run Terraform by impersonating a dedicated `terraform-deployer` service account — this keeps AR access scoped to the SA, not your personal account.

```bash
gcloud config set project YOUR_PROJECT_ID

# Enable Service Usage API first (required to enable other APIs)
gcloud services enable serviceusage.googleapis.com

gcloud services enable \
  run.googleapis.com \
  secretmanager.googleapis.com \
  aiplatform.googleapis.com \
  storage.googleapis.com \
  iam.googleapis.com

# Create the terraform-deployer service account
gcloud iam service-accounts create terraform-deployer \
  --display-name="Terraform Deployer"

SA_EMAIL=terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com

# Grant terraform-deployer the roles it needs
for role in roles/run.admin roles/storage.admin \
  roles/secretmanager.admin roles/iam.serviceAccountAdmin \
  roles/serviceusage.serviceUsageConsumer; do
  gcloud projects add-iam-policy-binding YOUR_PROJECT_ID \
    --member="serviceAccount:$SA_EMAIL" --role="$role"
done

# Grant yourself permission to impersonate terraform-deployer
gcloud iam service-accounts add-iam-policy-binding $SA_EMAIL \
  --member="user:YOUR_EMAIL" \
  --role="roles/iam.serviceAccountTokenCreator"
```

---

## Phase 2: Request Image Access

Container images are hosted in Rakettitiede's Artifact Registry. Two identities need read access:

1. **Cloud Run Service Agent** — pulls images at runtime
2. **terraform-deployer service account** — validates images during `terraform plan/apply`

**Bootstrap the Cloud Run Service Agent** (it doesn't exist until you create it):

```bash
gcloud beta services identity create --service=run.googleapis.com --project=YOUR_PROJECT_ID
```

**Get your project number:**

```bash
gcloud projects describe YOUR_PROJECT_ID --format="value(projectNumber)"
```

**Contact Rakettitiede (via Slack) with:**

- Partner identifier (lowercase): e.g., `acme`
- GCP project number (numeric, e.g., `107604611556`)
- terraform-deployer email: `terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com`

**What Rakettitiede does:** Grants `roles/artifactregistry.reader` on each container repository to:
- Your Cloud Run Service Agent (`service-PROJECT_NUMBER@serverless-robot-prod.iam.gserviceaccount.com`)
- Your terraform-deployer service account

**Wait for confirmation:** partner ID and image access granted.

---

## Phase 3: Create Terraform State Bucket

Terraform stores infrastructure state remotely in GCS. This enables team collaboration and state locking.

```bash
gcloud storage buckets create gs://YOUR_PROJECT_ID-terraform-state \
  --location=europe-north1 \
  --uniform-bucket-level-access \
  --pap

# Grant terraform-deployer access to manage state
gcloud storage buckets add-iam-policy-binding gs://YOUR_PROJECT_ID-terraform-state \
  --member="serviceAccount:terraform-deployer@YOUR_PROJECT_ID.iam.gserviceaccount.com" \
  --role="roles/storage.objectAdmin"
```

---

## Phase 4: Deploy

This deploys three Cloud Run services: mcp-agileday (search backend), Pyry (Slack bot), and your federation node (for cross-company search).

```bash
mkdir talent-network && cd talent-network
```

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

```bash
terraform init
terraform apply
```

The first apply creates secrets but Cloud Run deployment will fail because secrets have no versions yet. Add placeholder values:

```bash
for secret in pyry-bot-token pyry-slack-signing-secret; do
  echo -n "PLACEHOLDER" | gcloud secrets versions add "$secret" --data-file=-
done
```

Apply again to complete Cloud Run deployment:

```bash
terraform apply
```

Services will deploy but Pyry won't respond to Slack until you add real credentials in Phase 5.

---

## Phase 5: Create Slack App

Pyry needs a Slack app to receive messages and respond. This creates the app, configures permissions, and connects it to your deployed service.

1. [https://api.slack.com/apps](https://api.slack.com/apps) → Create New App → From scratch
2. Name: `Pyry`, select workspace

**OAuth & Permissions → Bot Token Scopes:**

- `chat:write`, `im:history`, `im:read`, `im:write`

Click **Install to Workspace**.

**App Home** — enable all:

- Home Tab
- Messages Tab
- Allow users to send Slash commands and messages from the messages tab

**Store credentials** (replace the placeholders with real values):

```bash
echo -n "xoxb-your-bot-token" | gcloud secrets versions add pyry-bot-token --data-file=-
echo -n "your-signing-secret" | gcloud secrets versions add pyry-slack-signing-secret --data-file=-
```

Redeploy to pick up the new credentials:

```bash
terraform apply
```

**Event Subscriptions** (tells Slack where to send messages):

- Enable Events
- Request URL: `https://PYRY_URL/slack/events`
- Bot events: `message.im`, `app_home_opened`

---

## Phase 6: Initialize Database

The search backend starts with an empty database. This fetches your consultant data from AgileDay and builds the search index.

Get AgileDay token: Browser DevTools → Application → Cookies → copy session cookie.

```bash
API_KEY=$(gcloud secrets versions access latest --secret=ai-talent-search-mcp-api-key)
curl -X POST "$(terraform output -raw search_mcp_url)/api/v1/refresh" \
  -H "X-API-Key: $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"token": "YOUR_AGILEDAY_TOKEN"}'
```

---

## Phase 7: Verify Pyry

Confirm Pyry can search your consultants.

DM Pyry in Slack: "Find a senior React developer"

---

## Phase 8: Join Federation

Your federation node allows Minna to include your consultants in cross-company searches. Minna returns anonymized results to protect consultant identity across companies.

**Contact Rakettitiede (via Slack) with your network URL:**

```bash
terraform output -raw network_mcp_url
```

Rakettitiede will:

1. Add your node to Minna's federation
2. Send you the Minna install link

**Install Minna:**

1. Have a workspace admin click the install link
2. Authorize Minna for your workspace
3. After authorization, send the redirect URL (contains a `code` parameter) back to Rakettitiede
4. Rakettitiede will complete the token exchange and enable Minna for your workspace

Test Minna: "Find a consultant with Kubernetes experience"

---

## Maintenance

**Refresh database** (run periodically to sync new consultants and profile updates):

```bash
API_KEY=$(gcloud secrets versions access latest --secret=ai-talent-search-mcp-api-key)
curl -X POST "$(terraform output -raw search_mcp_url)/api/v1/refresh" \
  -H "X-API-Key: $API_KEY" -H "Content-Type: application/json" \
  -d '{"token": "FRESH_AGILEDAY_TOKEN"}'
```

**Update versions:** Edit image_tags, run `terraform apply`.