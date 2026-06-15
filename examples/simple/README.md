# Simple Example

Minimal configuration for a partner deployment. Deploys:

- **mcp-agileday** — search backend that indexes consultants from AgileDay
- **Pyry** — Slack bot for internal talent searches
- **mcp-talent-network** — federation node for cross-company searches via Minna

## Prerequisites

1. GCP project with billing enabled
2. Service account with required roles (see main module README)
3. Terraform state bucket created via `modules/bootstrap` or manually
4. Image access granted by Rakettitiede

## Usage

1. Copy this directory
2. Replace `YOUR_PROJECT_ID` and other placeholders in `main.tf`
3. Run:

```bash
terraform init
terraform apply
```

4. Populate secrets (see [Partner Onboarding Guide](../../docs/partner-onboarding.md))
5. Configure Slack app with the `pyry_url` output

## Next Steps

- [Partner Onboarding Guide](../../docs/partner-onboarding.md) — full setup walkthrough
- [Complete Example](../complete/) — all configuration options
