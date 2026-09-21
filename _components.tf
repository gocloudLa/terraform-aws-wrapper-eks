# Clusters with a non-empty components map and create = true. Key: cluster id.
locals {
  eks_components_tmp = [
    for cluster, values in try(var.eks_parameters, {}) : [
      {
        "${cluster}" = {
          cluster    = cluster
          components = values.components
        }
      }
    ] if local.components_enabled[cluster]
  ]

  eks_components = merge(flatten(local.eks_components_tmp)...)
}

# output "debug_eks_components" {
#   value = local.eks_components
# }

# Key: cluster id. Access entry for the task role is created inside the child so
# the Fargate waiter cannot race RBAC.
module "eks_components" {
  source = "./modules/terraform-aws-eks-components"

  for_each = local.eks_components

  create = local.cluster_enabled[each.key]
  name   = "${local.common_name}-${each.key}-components"
  tags   = merge(local.common_tags, try(var.eks_parameters[each.key].tags, var.eks_defaults.tags, null))

  cluster_name              = module.eks[each.key].cluster_name
  cluster_arn               = module.eks[each.key].cluster_arn
  region                    = data.aws_region.current.region
  vpc_id                    = data.aws_vpc.this[each.key].id
  subnet_ids                = length(try(var.eks_parameters[each.key].subnet_ids, var.eks_defaults.subnet_ids, [])) > 0 ? try(var.eks_parameters[each.key].subnet_ids, var.eks_defaults.subnet_ids) : data.aws_subnets.this[each.key].ids
  cluster_security_group_id = module.eks[each.key].cluster_security_group_id
  components                = each.value.components
  pod_identity_role_arns = [
    for k, v in local.pod_identities : module.pod_identity[k].iam_role_arn
    if v.cluster == each.key
  ]
}
