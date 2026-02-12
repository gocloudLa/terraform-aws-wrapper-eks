output "cluster_name" {
  description = "EKS cluster name"
  value       = module.wrapper_eks.cluster_names
}

output "cluster_endpoint" {
  description = "EKS API endpoint"
  value       = module.wrapper_eks.cluster_endpoints
}

output "cluster_certificate_authority_data" {
  description = "Cluster CA for kubeconfig generation"
  value       = module.wrapper_eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN for IRSA"
  value       = module.wrapper_eks.oidc_provider_arns
}

output "node_security_group_id" {
  description = "Shared node security group"
  value       = module.wrapper_eks.node_security_group_ids
}

output "region" {
  description = "AWS region used by the deployment"
  value       = local.metadata.aws_region
}
