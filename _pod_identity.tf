# Flattened pod_identities. Key: "${cluster}-${identity}".
locals {
  pod_identities_tmp = [
    for cluster, values in try(var.eks_parameters, {}) : [
      for id_key, id in try(values.pod_identities, {}) : {
        "${cluster}-${id_key}" = merge(id, {
          cluster = cluster
          key     = id_key
        })
      }
    ] if local.pod_identities_enabled[cluster]
  ]

  pod_identities = merge(flatten(local.pod_identities_tmp)...)
}

# output "debug_pod_identities" {
#   value = local.pod_identities
# }

# Key: "${cluster}-${identity}"
module "pod_identity" {
  source  = "terraform-aws-modules/eks-pod-identity/aws"
  version = "2.9.0"

  for_each = local.pod_identities

  create          = true
  name            = try(each.value.iam_role_name, "${local.common_name}-${each.value.cluster}-${each.value.key}")
  use_name_prefix = false
  tags            = merge(local.common_tags, try(each.value.tags, var.eks_defaults.tags, null))

  attach_aws_lb_controller_policy    = try(each.value.attach_aws_lb_controller_policy, false)
  attach_aws_ebs_csi_policy          = try(each.value.attach_aws_ebs_csi_policy, false)
  aws_ebs_csi_kms_arns               = try(each.value.aws_ebs_csi_kms_arns, [])
  attach_aws_efs_csi_policy          = try(each.value.attach_aws_efs_csi_policy, false)
  attach_aws_vpc_cni_policy          = try(each.value.attach_aws_vpc_cni_policy, false)
  aws_vpc_cni_enable_ipv4            = try(each.value.aws_vpc_cni_enable_ipv4, false)
  aws_vpc_cni_enable_ipv6            = try(each.value.aws_vpc_cni_enable_ipv6, false)
  attach_mountpoint_s3_csi_policy    = try(each.value.attach_mountpoint_s3_csi_policy, false)
  mountpoint_s3_csi_bucket_arns      = try(each.value.mountpoint_s3_csi_bucket_arns, [])
  mountpoint_s3_csi_bucket_path_arns = try(each.value.mountpoint_s3_csi_bucket_path_arns, [])

  attach_custom_policy   = length(try(each.value.policy_statements, [])) > 0
  policy_statements      = try(each.value.policy_statements, null)
  additional_policy_arns = try(each.value.additional_policy_arns, {})

  associations = {
    this = {
      cluster_name    = module.eks[each.value.cluster].cluster_name
      namespace       = each.value.namespace
      service_account = each.value.service_account
    }
  }
}
