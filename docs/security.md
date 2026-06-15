# Security Model

This document describes the security architecture and IAM configuration for the ai-talent module.

## Public Cloud Run Services

All Cloud Run services are deployed with `allUsers` as an invoker. This is intentional:

| Service | Why Public | Authentication |
|---------|-----------|----------------|
| **mcp-agileday** | MCP protocol endpoint for AI clients | API key via `X-API-Key` header |
| **Pyry** | Slack webhook endpoint | Slack signing secret verification |
| **mcp-talent-network** | MCP protocol endpoint for federation | API key via `X-API-Key` header |
| **Minna** | Slack webhook endpoint | Slack signing secret verification |
| **Topi** | Slack webhook endpoint | Slack signing secret verification |

**Why not use IAM for Cloud Run?**

- Slack webhooks require unauthenticated HTTPS endpoints — Slack doesn't support GCP IAM tokens
- MCP clients (Claude Desktop, Cursor, etc.) use API keys, not IAM

**How requests are authenticated:**

1. **Slack bots (Pyry, Minna, Topi):** Every request is verified against the Slack signing secret before processing. Invalid signatures are rejected with 401.

2. **MCP servers (mcp-agileday, mcp-talent-network):** API key authentication via `X-API-Key` header, validated against the secret stored in Secret Manager.

## Secret Management

Secrets are stored in Google Secret Manager and mounted as environment variables at runtime. Cloud Run's service account has `secretmanager.secretAccessor` role.

| Secret | Purpose | Who Sets It |
|--------|---------|-------------|
| `ai-talent-search-mcp-api-key` | API key for mcp-agileday | Auto-generated |
| `pyry-bot-token` | Slack bot token | User (Phase 5) |
| `pyry-slack-signing-secret` | Slack request verification | User (Phase 5) |
| `ai-talent-network-mcp-api-key` | API key for federation node | Auto-generated |

**Auto-generated secrets** use `random_password` with 64 characters, no special characters. They rotate when the corresponding `image_tag` changes (via `keepers`).

## Data Storage

Each partner's data stays in their own GCP project:

| Bucket | Contents | Access |
|--------|----------|--------|
| `{project}-search_mcp-db` | Consultant profiles, embeddings, search index | Service account only |
| `{project}-talent-network-db` | Anonymized consultant data for federation | Service account only |

Buckets have:
- Uniform bucket-level access (no ACLs)
- Versioning enabled
- Service account has `storage.objectAdmin`

## Federation Privacy

When a partner joins the Minna federation:

1. Their `mcp-talent-network` node exposes **anonymized** search results
2. Minna queries all partner nodes and aggregates results
3. Full consultant details are only visible within the partner's own Slack (via Pyry)
4. Cross-company searches show skills/experience but not names or contact info

Rakettitiede does not have access to partner consultant databases — only the anonymized results that partners choose to expose.

## IAM Roles Required

The service account needs these roles:

| Role | Purpose |
|------|---------|
| `roles/run.admin` | Deploy and manage Cloud Run services |
| `roles/artifactregistry.reader` | Pull container images |
| `roles/storage.admin` | Create and manage GCS buckets |
| `roles/secretmanager.admin` | Create secrets (Terraform) |
| `roles/secretmanager.secretAccessor` | Read secrets at runtime (Cloud Run) |
| `roles/aiplatform.user` | Access Vertex AI for embeddings/LLM |
| `roles/iam.serviceAccountUser` | Allow Cloud Run to use the service account |

## Recommendations

1. **Rotate API keys periodically** by updating `image_tags` (triggers new random password)
2. **Monitor Cloud Run logs** for authentication failures
3. **Use VPC Service Controls** if you need to restrict data egress
