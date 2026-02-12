output "cluster_endpoints" {
  description = "Endpoints for the EKS clusters"
  value       = { for k, v in module.wrapper_eks : k => v.cluster_endpoint }
}

output "cluster_certificate_authority_data" {
  description = "Certificate Authority Data for the EKS clusters"
  value       = { for k, v in module.wrapper_eks : k => v.cluster_certificate_authority_data }
}

output "cluster_names" {
  description = "Names of the EKS clusters"
  value       = { for k, v in module.wrapper_eks : k => v.cluster_name }
}

output "oidc_provider_arns" {
  description = "OIDC Provider ARNs for IRSA for each cluster"
  value       = { for k, v in module.wrapper_eks : k => v.oidc_provider_arn }
}

output "node_security_group_ids" {
  description = "Node security group IDs for each cluster"
  value       = { for k, v in module.wrapper_eks : k => v.node_security_group_id }
}

output "cluster_security_group_ids" {
  description = "Cluster security group IDs for each cluster"
  value       = { for k, v in module.wrapper_eks : k => v.cluster_security_group_id }
}