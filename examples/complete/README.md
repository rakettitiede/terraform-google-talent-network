# Complete Example

Full configuration showing all available options.

## What This Deploys

**All partners:**
- **mcp-agileday** — search backend that indexes consultants from AgileDay
- **Pyry** — Slack bot for internal talent searches
- **mcp-talent-network** — federation node for cross-company searches

**Rakettitiede only** (when `partner = "rakettitiede"`):
- **Minna** — federated Slack bot that queries all partner nodes
- **Topi** — bench management Slack bot
- **ai-talent-bench-mcp** — bench data backend

## Configuration Options

| Variable | Description | Default |
|----------|-------------|---------|
| `project_id` | Your GCP project ID | Required |
| `service_account` | Service account for Cloud Run | Required |
| `partner` | Your partner identifier | Required |
| `agileday_base_url` | AgileDay API URL | Required |
| `region` | GCP region | `europe-north1` |
| `llm_model` | LLM for Slack bots | `gemini-3.5-flash` |
| `image_tags` | Pin specific service versions | Module defaults |
| `artifact_registry_project_id` | Self-host images | Rakettitiede registry |
| `partner_mcp_urls` | Federation partners (Rakettitiede only) | `{}` |

## Usage

1. Copy this directory
2. Update all placeholder values
3. Run:

```bash
terraform init
terraform apply
```

4. Populate secrets — see [Partner Onboarding Guide](../../docs/partner-onboarding.md)
