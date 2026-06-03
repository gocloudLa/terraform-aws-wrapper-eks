locals {
  node_iam_role_additional_policies = {
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  }

  iam_policy_statements = [
    {
      sid       = "ServiceLinkedRoleCreation"
      actions   = ["iam:CreateServiceLinkedRole"]
      effect    = "Allow"
      resources = ["*"]
    }
  ]
}

module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.23.0"

  for_each = var.eks_parameters

  # Parámetros generales
  create       = try(each.value.karpenter.create, false)
  tags         = try(each.value.karpenter.aws_resources_tags, local.common_tags)
  cluster_name = module.eks[each.key].cluster_name

  # Karpenter Controller IAM Role
  create_iam_role                   = try(each.value.karpenter.aws_resources_create_iam_role, true)
  iam_role_name                     = try(each.value.karpenter.aws_resources_iam_role_name, "${local.common_name}-${each.key}-karpenter-controller")
  iam_role_use_name_prefix          = try(each.value.karpenter.aws_resources_iam_role_use_name_prefix, false)
  iam_role_path                     = try(each.value.karpenter.aws_resources_iam_role_path, "/")
  iam_role_description              = try(each.value.karpenter.aws_resources_iam_role_description, "Karpenter controller IAM role")
  iam_role_max_session_duration     = try(each.value.karpenter.aws_resources_iam_role_max_session_duration, null)
  iam_role_permissions_boundary_arn = try(each.value.karpenter.aws_resources_iam_role_permissions_boundary_arn, null)
  iam_role_tags                     = try(each.value.karpenter.aws_resources_iam_role_tags, {})

  iam_policy_name            = try(each.value.karpenter.aws_resources_iam_policy_name, "${local.common_name}-${each.key}-karpenter-controller")
  iam_policy_use_name_prefix = try(each.value.karpenter.aws_resources_iam_policy_use_name_prefix, false)
  iam_policy_path            = try(each.value.karpenter.aws_resources_iam_policy_path, "/")
  iam_policy_description     = try(each.value.karpenter.aws_resources_iam_policy_description, "Karpenter controller IAM policy")
  iam_policy_statements      = try(each.value.karpenter.aws_resources_iam_policy_statements, local.iam_policy_statements)
  iam_role_policies          = try(each.value.karpenter.aws_resources_iam_role_policies, {})

  ami_id_ssm_parameter_arns = try(each.value.karpenter.aws_resources_ami_id_ssm_parameter_arns, [])

  # Pod Identity Association
  create_pod_identity_association = try(each.value.karpenter.aws_resources_create_pod_identity_association, true)
  namespace                       = try(each.value.karpenter.aws_resources_namespace, "kube-system")
  service_account                 = try(each.value.karpenter.aws_resources_service_account, "karpenter")

  # Node Termination Queue
  enable_spot_termination                 = try(each.value.karpenter.aws_resources_enable_spot_termination, true)
  queue_name                              = try(each.value.karpenter.aws_resources_queue_name, "${local.common_name}-${each.key}")
  queue_managed_sse_enabled               = try(each.value.karpenter.aws_resources_queue_managed_sse_enabled, true)
  queue_kms_master_key_id                 = try(each.value.karpenter.aws_resources_queue_kms_master_key_id, null)
  queue_kms_data_key_reuse_period_seconds = try(each.value.karpenter.aws_resources_queue_kms_data_key_reuse_period_seconds, null)

  # Node IAM Role
  create_node_iam_role               = try(each.value.karpenter.aws_resources_create_node_iam_role, true)
  cluster_ip_family                  = try(each.value.karpenter.aws_resources_cluster_ip_family, "ipv4")
  node_iam_role_arn                  = try(each.value.karpenter.aws_resources_node_iam_role_arn, null)
  node_iam_role_name                 = try(each.value.karpenter.aws_resources_node_iam_role_name, module.eks[each.key].cluster_name)
  node_iam_role_use_name_prefix      = try(each.value.karpenter.aws_resources_node_iam_role_use_name_prefix, false)
  node_iam_role_path                 = try(each.value.karpenter.aws_resources_node_iam_role_path, "/")
  node_iam_role_description          = try(each.value.karpenter.aws_resources_node_iam_role_description, null)
  node_iam_role_max_session_duration = try(each.value.karpenter.aws_resources_node_iam_role_max_session_duration, null)
  node_iam_role_permissions_boundary = try(each.value.karpenter.aws_resources_node_iam_role_permissions_boundary, null)
  node_iam_role_attach_cni_policy    = try(each.value.karpenter.aws_resources_node_iam_role_attach_cni_policy, true)
  node_iam_role_additional_policies  = try(each.value.karpenter.aws_resources_node_iam_role_additional_policies, local.node_iam_role_additional_policies)
  node_iam_role_tags                 = try(each.value.karpenter.aws_resources_node_iam_role_tags, {})

  # Access Entry
  create_access_entry = try(each.value.karpenter.aws_resources_create_access_entry, true)
  access_entry_type   = try(each.value.karpenter.aws_resources_access_entry_type, "EC2_LINUX")

  # Node IAM Instance Profile
  create_instance_profile = try(each.value.karpenter.aws_resources_create_instance_profile, true)

  # Event Bridge Rules
  rule_name_prefix = try(each.value.karpenter.aws_resources_rule_name_prefix, "Karpenter")
}

/*----------------------------------------------------------------------*/
/* Karpenter  | AWS Tags                                                */
/*----------------------------------------------------------------------*/

locals {
  # Filtrar solo los clusters que tengan habilitado karpenter (si no existe, se asume false).
  karpenter_clusters = {
    for cluster, values in var.eks_parameters :
    cluster => values
  }
  # esta validacion genera el depdendecia ciclica

  # Tags de subnets VPC por clúster (solo valor cambia, key fijo)
  karpenter_vpc_subnet_tags = {
    for cluster, values in var.eks_parameters :
    cluster => (
      try(values.karpenter.create, false)
      ? {
        "karpenter.sh/discovery" = try(values.karpenter.vpc_subnet_tag_value, "${local.common_name}-${cluster}")
      }
      : {}
    )
  }

  # Tags de grupo de seguridad de nodos Karpenter por clúster (solo valor cambia, key fijo)
  karpenter_security_group_node_tags = {
    for cluster, values in var.eks_parameters :
    cluster => (
      try(values.karpenter.create, false)
      ? {
        "karpenter.sh/discovery" = try(values.karpenter.security_group_node_tag_value, "${local.common_name}-${cluster}")
      }
      : {}
    )
  }

  # Para cada cluster filtrado, obtenemos la lista de subnets y asignamos un mapa de tags.
  karpenter_subnets = flatten([
    for cluster, values in local.karpenter_clusters : [
      for subnet_id in data.aws_subnets.this[cluster].ids : {
        cluster   = cluster
        subnet_id = subnet_id
        # Usamos los tags definidos en el bloque karpenter, o por defecto.
        tags = local.karpenter_vpc_subnet_tags[cluster]
      } if try(values.karpenter.create, false)
    ]
  ])

  # Aplanamos el mapa de tags para iterar de forma individual.
  karpenter_subnet_tags = merge([
    for subnet in local.karpenter_subnets : {
      for tag_key, tag_value in subnet.tags :
      "${subnet.subnet_id}::${tag_key}" => {
        subnet_id = subnet.subnet_id
        tag_key   = tag_key
        tag_value = tag_value
      }
    }
  ]...)
}

resource "aws_ec2_tag" "karpenter_subnet_extra_tags" {
  for_each    = local.karpenter_subnet_tags
  resource_id = each.value.subnet_id
  key         = "karpenter.sh/discovery"
  value       = each.value.tag_value
}
