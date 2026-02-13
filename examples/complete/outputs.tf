output "cluster_endpoint" {
  description = "EKS API endpoint"
  value       = module.wrapper_eks.cluster_endpoints
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.wrapper_eks.oidc_provider_arns
}
