data "aws_subnets" "elb_private" {
  for_each = var.eks_parameters

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this[each.key].id]
  }

  tags = {
    Name = try(each.value.aws_load_balancer_controller.private_subnet_name, local.default_private_subnet_name)
  }
}

data "aws_subnets" "elb_public" {
  for_each = var.eks_parameters

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this[each.key].id]
  }

  tags = {
    Name = try(each.value.aws_load_balancer_controller.public_subnet_name, local.default_public_subnet_name)
  }
}

locals {
  # Tags por defecto para el AWS Load Balancer Controller
  aws_load_balancer_controller_internal_default_tag = {
    "kubernetes.io/role/internal-elb" = 1 # Para LB internos
  }

  aws_load_balancer_controller_internet_default_tag = {
    "kubernetes.io/role/elb" = 1 # Para ELB externos
  }

  # Flattened private subnet tags. Key: "${subnet_id}-${tag_key}"
  aws_load_balancer_controller_private_subnet_tags_tmp = [
    for cluster, values in try(var.eks_parameters, {}) : [
      for subnet_id in data.aws_subnets.elb_private[cluster].ids : [
        for tag_key, tag_value in try(
          values.aws_load_balancer_controller.aws_load_balancer_controller_vpc_private_subnet_tags,
          local.aws_load_balancer_controller_internal_default_tag
          ) : {
          "${subnet_id}-${tag_key}" = {
            subnet_id = subnet_id
            tag_key   = tag_key
            tag_value = tag_value
          }
        }
      ] if try(values.aws_load_balancer_controller.private_ingress_create, false)
    ] if local.aws_load_balancer_controller_enabled[cluster]
  ]

  # Flattened public subnet tags. Key: "${subnet_id}-${tag_key}"
  aws_load_balancer_controller_public_subnet_tags_tmp = [
    for cluster, values in try(var.eks_parameters, {}) : [
      for subnet_id in data.aws_subnets.elb_public[cluster].ids : [
        for tag_key, tag_value in try(
          values.aws_load_balancer_controller.aws_load_balancer_controller_vpc_public_subnet_tags,
          local.aws_load_balancer_controller_internet_default_tag
          ) : {
          "${subnet_id}-${tag_key}" = {
            subnet_id = subnet_id
            tag_key   = tag_key
            tag_value = tag_value
          }
        }
      ] if try(values.aws_load_balancer_controller.public_ingress_create, false)
    ] if local.aws_load_balancer_controller_enabled[cluster]
  ]

  aws_load_balancer_controller_subnet_tags = merge(flatten(concat(
    local.aws_load_balancer_controller_private_subnet_tags_tmp,
    local.aws_load_balancer_controller_public_subnet_tags_tmp,
  ))...)
}

# output "debug_aws_load_balancer_controller_subnet_tags" {
#   value = local.aws_load_balancer_controller_subnet_tags
# }

# Key: "${subnet_id}-${tag_key}"
resource "aws_ec2_tag" "aws_load_balancer_controller_subnet_extra_tags" {
  for_each    = local.aws_load_balancer_controller_subnet_tags
  resource_id = each.value.subnet_id
  key         = each.value.tag_key
  value       = each.value.tag_value
}
