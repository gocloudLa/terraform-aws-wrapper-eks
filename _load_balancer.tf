data "aws_subnets" "elb_private" {
  for_each = var.eks_parameters

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this[each.key].id]
  }

  tags = {
    Name = try(each.value.aws_load_balancer_controller.private_subnet_name, local.default_subnet_private_name)
  }
}

data "aws_subnets" "elb_public" {
  for_each = var.eks_parameters

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.this[each.key].id]
  }

  tags = {
    Name = try(each.value.aws_load_balancer_controller.public_subnet_name, local.default_subnet_public_name)
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

  # Filtrar solo los clusters que tienen habilitado aws_load_balancer_controller.
  # Se itera sobre var.eks_parameters y se mantienen solo aquellos en los que
  # values.aws_load_balancer_controller.create es true.
  aws_load_balancer_controller_clusters = {
    for cluster, values in var.eks_parameters :
    cluster => values
    if try(values.aws_load_balancer_controller.create, false)
  }

  # Para cada cluster filtrado, obtenemos las subnets privadas y le asignamos el tag correspondiente.
  aws_load_balancer_controller_private_subnets = flatten([
    for cluster, values in local.aws_load_balancer_controller_clusters : [
      for subnet_id in data.aws_subnets.elb_private[cluster].ids : {
        cluster   = cluster
        subnet_id = subnet_id
        # Se busca, en la configuración del cluster, los tags para el controlador.
        # Si no se definen, se usa el valor por defecto para LB internos.
        tags = lookup(
          try(values.aws_load_balancer_controller, {}),
          "aws_load_balancer_controller_vpc_private_subnet_tags",
          local.aws_load_balancer_controller_internal_default_tag
        )
      } if try(values.aws_load_balancer_controller.private_ingress_create, false)
    ]
  ])

  # Para cada cluster filtrado, obtenemos las subnets públicas y le asignamos el tag correspondiente.
  aws_load_balancer_controller_public_subnets = flatten([
    for cluster, values in local.aws_load_balancer_controller_clusters : [
      for subnet_id in data.aws_subnets.elb_public[cluster].ids : {
        cluster   = cluster
        subnet_id = subnet_id
        # Se usa la configuración específica para subnets públicas o el valor por defecto.
        tags = lookup(
          try(values.aws_load_balancer_controller, {}),
          "aws_load_balancer_controller_vpc_public_subnet_tags",
          local.aws_load_balancer_controller_internet_default_tag
        )
      } if try(values.aws_load_balancer_controller.public_ingress_create, false)
    ]
  ])

  # Unificamos la lista de subnets privadas y públicas, y aplanamos el mapa de tags para iterar de forma individual.
  aws_load_balancer_controller_subnet_tags = merge([
    for subnet in concat(
      local.aws_load_balancer_controller_private_subnets,
      local.aws_load_balancer_controller_public_subnets
      ) : {
      for tag_key, tag_value in subnet.tags :
      "${subnet.subnet_id}::${tag_key}" => {
        subnet_id = subnet.subnet_id
        tag_key   = tag_key
        tag_value = tag_value
      }
    }
  ]...)
}

resource "aws_ec2_tag" "aws_load_balancer_controller_subnet_extra_tags" {
  for_each    = local.aws_load_balancer_controller_subnet_tags
  resource_id = each.value.subnet_id
  key         = each.value.tag_key
  value       = each.value.tag_value

}
