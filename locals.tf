/*----------------------------------------------------------------------*/
/* Locals Definition                                                    */
/*----------------------------------------------------------------------*/

locals {

  # Default Subnet Name
  default_private_subnet_name = "${local.common_name_prefix}-private*"
  default_public_subnet_name  = "${local.common_name_prefix}-public*"

  # Create flags. Key: cluster id from eks_parameters.
  cluster_enabled = {
    for k, v in try(var.eks_parameters, {}) :
    k => try(v.create, var.eks_defaults.create, true)
  }

  karpenter_enabled = {
    for k, v in try(var.eks_parameters, {}) :
    k => local.cluster_enabled[k] && try(v.karpenter.create, var.eks_defaults.karpenter.create, false)
  }

  aws_load_balancer_controller_enabled = {
    for k, v in try(var.eks_parameters, {}) :
    k => local.cluster_enabled[k] && try(v.aws_load_balancer_controller.create, false)
  }

  pod_identities_enabled = {
    for k, v in try(var.eks_parameters, {}) :
    k => local.cluster_enabled[k] && length(try(v.pod_identities, {})) > 0
  }

  components_enabled = {
    for k, v in try(var.eks_parameters, {}) :
    k => local.cluster_enabled[k] && length(try(v.components, {})) > 0
  }

}

# output "debug_cluster_enabled" {
#   value = local.cluster_enabled
# }
#
# output "debug_karpenter_enabled" {
#   value = local.karpenter_enabled
# }
#
# output "debug_aws_load_balancer_controller_enabled" {
#   value = local.aws_load_balancer_controller_enabled
# }
#
# output "debug_pod_identities_enabled" {
#   value = local.pod_identities_enabled
# }
#
# output "debug_components_enabled" {
#   value = local.components_enabled
# }
