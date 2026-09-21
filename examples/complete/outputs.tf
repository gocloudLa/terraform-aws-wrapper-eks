output "cluster_endpoint" {
  description = "EKS API endpoint"
  value       = module.wrapper_eks.cluster_endpoints
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.wrapper_eks.oidc_provider_arns
}

output "pod_identity_role_arns" {
  description = "IAM role ARNs created for EKS Pod Identity"
  value       = module.wrapper_eks.pod_identity_role_arns
}

output "pod_identity_associations" {
  description = "EKS Pod Identity associations created by the wrapper"
  value       = module.wrapper_eks.pod_identity_associations
}

output "components" {
  description = "EKS components apply results keyed by cluster"
  value       = module.wrapper_eks.components
}
