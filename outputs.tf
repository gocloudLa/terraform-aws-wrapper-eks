/*----------------------------------------------------------------------*/
/* Output Definition                                                    */
/*----------------------------------------------------------------------*/

output "cluster_endpoints" {
  description = "Endpoints for the EKS clusters"
  value       = { for k, v in module.eks : k => v.cluster_endpoint }
}

output "cluster_certificate_authority_data" {
  description = "Certificate Authority Data for the EKS clusters"
  value       = { for k, v in module.eks : k => v.cluster_certificate_authority_data }
}

output "cluster_names" {
  description = "Names of the EKS clusters"
  value       = { for k, v in module.eks : k => v.cluster_name }
}

output "oidc_provider_arns" {
  description = "OIDC Provider ARNs for IRSA for each cluster"
  value       = { for k, v in module.eks : k => v.oidc_provider_arn }
}

output "node_security_group_ids" {
  description = "Node security group IDs for each cluster"
  value       = { for k, v in module.eks : k => v.node_security_group_id }
}

output "cluster_security_group_ids" {
  description = "Cluster security group IDs for each cluster"
  value       = { for k, v in module.eks : k => v.cluster_security_group_id }
}

output "pod_identity_role_arns" {
  description = "IAM role ARNs created for EKS Pod Identity, keyed by cluster then identity"
  value = {
    for cluster, _ in var.eks_parameters : cluster => {
      for k, v in local.pod_identities : v.key => module.pod_identity[k].iam_role_arn
      if v.cluster == cluster
    }
  }
}

output "pod_identity_associations" {
  description = "Pod Identity association ARNs, keyed by cluster then identity"
  value = {
    for cluster, _ in var.eks_parameters : cluster => {
      for k, v in local.pod_identities : v.key => try(module.pod_identity[k].associations["this"].association_arn, null)
      if v.cluster == cluster
    }
  }
}

output "components" {
  description = "EKS components apply results keyed by cluster"
  value = {
    for k, v in module.eks_components : k => {
      summary        = v.summary
      task_arn       = v.task_arn
      log_group_name = v.log_group_name
    }
  }
}
