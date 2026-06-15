output "search_mcp_url" {
  description = "mcp-agileday service URL"
  value       = google_cloud_run_v2_service.search_mcp.uri
}

output "pyry_url" {
  description = "ai-talent-search-pyry service URL"
  value       = google_cloud_run_v2_service.pyry.uri
}

output "network_mcp_url" {
  description = "mcp-talent-network service URL"
  value       = google_cloud_run_v2_service.network_mcp.uri
}

output "minna_url" {
  description = "ai-talent-network-minna service URL (Rakettitiede only)"
  value       = length(google_cloud_run_v2_service.minna) > 0 ? google_cloud_run_v2_service.minna[0].uri : null
}

output "bench_mcp_url" {
  description = "ai-talent-bench-mcp service URL (Rakettitiede only)"
  value       = length(google_cloud_run_v2_service.bench_mcp) > 0 ? google_cloud_run_v2_service.bench_mcp[0].uri : null
}

output "topi_url" {
  description = "ai-talent-bench-topi service URL (Rakettitiede only)"
  value       = length(google_cloud_run_v2_service.topi) > 0 ? google_cloud_run_v2_service.topi[0].uri : null
}
