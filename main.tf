module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.20.0"

  for_each = var.eks_parameters

  /*----------------------------------------------------------------------*/
  /* Common                                                               */
  /*----------------------------------------------------------------------*/

  create           = try(each.value.create, var.eks_defaults.create, true)
  tags             = try(each.value.tags, var.eks_defaults.tags, local.common_tags)
  prefix_separator = try(each.value.prefix_separator, var.eks_defaults.prefix_separator, "-") # Revisar valor default

  /*----------------------------------------------------------------------*/
  /* Cluster                                                              */
  /*----------------------------------------------------------------------*/
  name               = try(each.value.cluster_name, var.eks_defaults.cluster_name, "${local.common_name}-${each.key}")
  kubernetes_version = try(each.value.cluster_version, var.eks_defaults.cluster_version, "1.33")
  enabled_log_types  = try(each.value.cluster_enabled_log_types, var.eks_defaults.cluster_enabled_log_types, ["api", "audit", "authenticator", "controllerManager", "scheduler"])
  # The cluster will source authenticated IAM principals only from EKS access entry APIs.
  authentication_mode = try(each.value.authentication_mode, var.eks_defaults.authentication_mode, "API_AND_CONFIG_MAP")

  compute_config                     = try(each.value.cluster_compute_config, var.eks_defaults.cluster_compute_config, {})
  upgrade_policy                     = try(each.value.cluster_upgrade_policy, var.eks_defaults.cluster_upgrade_policy, { support_type = "STANDARD" })
  remote_network_config              = try(each.value.cluster_remote_network_config, var.eks_defaults.cluster_remote_network_config, null)
  zonal_shift_config                 = try(each.value.cluster_zonal_shift_config, var.eks_defaults.cluster_zonal_shift_config, { enabled = true })
  additional_security_group_ids      = try(each.value.cluster_additional_security_group_ids, var.eks_defaults.cluster_additional_security_group_ids, [])
  control_plane_subnet_ids           = try(each.value.control_plane_subnet_ids, var.eks_defaults.control_plane_subnet_ids, [])
  subnet_ids                         = length(try(each.value.subnet_ids, var.eks_defaults.subnet_ids, [])) > 0 ? try(each.value.subnet_ids, var.eks_defaults.subnet_ids) : data.aws_subnets.this[each.key].ids
  endpoint_private_access            = try(each.value.cluster_endpoint_private_access, var.eks_defaults.cluster_endpoint_private_access, true)
  endpoint_public_access             = try(each.value.cluster_endpoint_public_access, var.eks_defaults.cluster_endpoint_public_access, false)
  endpoint_public_access_cidrs       = try(each.value.cluster_endpoint_public_access_cidrs, var.eks_defaults.cluster_endpoint_public_access_cidrs, ["0.0.0.0/0"])
  ip_family                          = try(each.value.cluster_ip_family, var.eks_defaults.cluster_ip_family, "ipv4")
  service_ipv4_cidr                  = try(each.value.cluster_service_ipv4_cidr, var.eks_defaults.cluster_service_ipv4_cidr, null)
  service_ipv6_cidr                  = try(each.value.cluster_service_ipv6_cidr, var.eks_defaults.cluster_service_ipv6_cidr, null)
  outpost_config                     = try(each.value.outpost_config, var.eks_defaults.outpost_config, null)
  encryption_config                  = try(each.value.cluster_encryption_config, var.eks_defaults.cluster_encryption_config, { resources = ["secrets"] })
  attach_encryption_policy           = try(each.value.attach_cluster_encryption_policy, var.eks_defaults.attach_cluster_encryption_policy, true)
  create_primary_security_group_tags = try(each.value.create_cluster_primary_security_group_tags, var.eks_defaults.create_cluster_primary_security_group_tags, true)
  timeouts                           = try(each.value.cluster_timeouts, var.eks_defaults.cluster_timeouts, {})
  cluster_tags                       = try(each.value.cluster_tags, var.eks_defaults.cluster_tags, {})

  /*----------------------------------------------------------------------*/
  /* Access Entry                                                         */
  /*----------------------------------------------------------------------*/
  access_entries                           = try(each.value.access_entries, var.eks_defaults.access_entries, {})
  enable_cluster_creator_admin_permissions = try(each.value.enable_cluster_creator_admin_permissions, var.eks_defaults.enable_cluster_creator_admin_permissions, true)

  /*----------------------------------------------------------------------*/
  /* KMS Key                                                              */
  /*----------------------------------------------------------------------*/
  create_kms_key                    = try(each.value.create_kms_key, var.eks_defaults.create_kms_key, true)
  kms_key_description               = try(each.value.kms_key_description, var.eks_defaults.kms_key_description, null)
  kms_key_deletion_window_in_days   = try(each.value.kms_key_deletion_window_in_days, var.eks_defaults.kms_key_deletion_window_in_days, null)
  enable_kms_key_rotation           = try(each.value.enable_kms_key_rotation, var.eks_defaults.enable_kms_key_rotation, true)
  kms_key_rotation_period_in_days   = try(each.value.kms_key_rotation_period_in_days, var.eks_defaults.kms_key_rotation_period_in_days, null)
  kms_key_enable_default_policy     = try(each.value.kms_key_enable_default_policy, var.eks_defaults.kms_key_enable_default_policy, true)
  kms_key_owners                    = try(each.value.kms_key_owners, var.eks_defaults.kms_key_owners, [])
  kms_key_administrators            = try(each.value.kms_key_administrators, var.eks_defaults.kms_key_administrators, [])
  kms_key_users                     = try(each.value.kms_key_users, var.eks_defaults.kms_key_users, [])
  kms_key_service_users             = try(each.value.kms_key_service_users, var.eks_defaults.kms_key_service_users, [])
  kms_key_source_policy_documents   = try(each.value.kms_key_source_policy_documents, var.eks_defaults.kms_key_source_policy_documents, [])
  kms_key_override_policy_documents = try(each.value.kms_key_override_policy_documents, var.eks_defaults.kms_key_override_policy_documents, [])
  kms_key_aliases                   = try(each.value.kms_key_aliases, var.eks_defaults.kms_key_aliases, [])

  /*----------------------------------------------------------------------*/
  /* CloudWatch Log Group                                                 */
  /*----------------------------------------------------------------------*/
  create_cloudwatch_log_group            = try(each.value.create_cloudwatch_log_group, var.eks_defaults.create_cloudwatch_log_group, true)
  cloudwatch_log_group_retention_in_days = try(each.value.cloudwatch_log_group_retention_in_days, var.eks_defaults.cloudwatch_log_group_retention_in_days, 30)
  cloudwatch_log_group_kms_key_id        = try(each.value.cloudwatch_log_group_kms_key_id, var.eks_defaults.cloudwatch_log_group_kms_key_id, null)
  cloudwatch_log_group_class             = try(each.value.cloudwatch_log_group_class, var.eks_defaults.cloudwatch_log_group_class, "STANDARD")
  cloudwatch_log_group_tags              = try(each.value.cloudwatch_log_group_tags, var.eks_defaults.cloudwatch_log_group_tags, {})

  /*----------------------------------------------------------------------*/
  /* Cluster Security Group                                               */
  /*----------------------------------------------------------------------*/
  create_security_group           = try(each.value.create_cluster_security_group, var.eks_defaults.create_cluster_security_group, true)
  security_group_id               = try(each.value.cluster_security_group_id, var.eks_defaults.cluster_security_group_id, "")
  vpc_id                          = data.aws_vpc.this[each.key].id
  security_group_name             = try(each.value.cluster_security_group_name, var.eks_defaults.cluster_security_group_name, null)
  security_group_use_name_prefix  = try(each.value.cluster_security_group_use_name_prefix, var.eks_defaults.cluster_security_group_use_name_prefix, false)
  security_group_description      = try(each.value.cluster_security_group_description, var.eks_defaults.cluster_security_group_description, "EKS cluster security group")
  security_group_additional_rules = try(each.value.cluster_security_group_additional_rules, var.eks_defaults.cluster_security_group_additional_rules, {})
  security_group_tags             = try(each.value.cluster_security_group_tags, var.eks_defaults.cluster_security_group_tags, {})

  /*----------------------------------------------------------------------*/
  /* EKS IPV6 CNI Policy                                                  */
  /*----------------------------------------------------------------------*/
  create_cni_ipv6_iam_policy = try(each.value.create_cni_ipv6_iam_policy, var.eks_defaults.create_cni_ipv6_iam_policy, false)

  /*----------------------------------------------------------------------*/
  /* Node Security Group                                                  */
  /*----------------------------------------------------------------------*/
  create_node_security_group                   = try(each.value.create_node_security_group, var.eks_defaults.create_node_security_group, true)
  node_security_group_id                       = try(each.value.node_security_group_id, var.eks_defaults.node_security_group_id, "")
  node_security_group_name                     = try(each.value.node_security_group_name, var.eks_defaults.node_security_group_name, null)
  node_security_group_use_name_prefix          = try(each.value.node_security_group_use_name_prefix, var.eks_defaults.node_security_group_use_name_prefix, false)
  node_security_group_description              = try(each.value.node_security_group_description, var.eks_defaults.node_security_group_description, "EKS node shared security group")
  node_security_group_additional_rules         = try(each.value.node_security_group_additional_rules, var.eks_defaults.node_security_group_additional_rules, {})
  node_security_group_enable_recommended_rules = try(each.value.node_security_group_enable_recommended_rules, var.eks_defaults.node_security_group_enable_recommended_rules, true)
  node_security_group_tags                     = merge(try(each.value.node_security_group_tags, var.eks_defaults.node_security_group_tags, {}), try(each.value.karpenter.create, false) ? local.karpenter_security_group_node_tags[each.key] : {})

  /*----------------------------------------------------------------------*/
  /* IRSA                                                                 */
  /*----------------------------------------------------------------------*/
  enable_irsa                     = try(each.value.enable_irsa, var.eks_defaults.enable_irsa, true)
  openid_connect_audiences        = try(each.value.openid_connect_audiences, var.eks_defaults.openid_connect_audiences, [])
  include_oidc_root_ca_thumbprint = try(each.value.include_oidc_root_ca_thumbprint, var.eks_defaults.include_oidc_root_ca_thumbprint, true)
  custom_oidc_thumbprints         = try(each.value.custom_oidc_thumbprints, var.eks_defaults.custom_oidc_thumbprints, [])

  /*----------------------------------------------------------------------*/
  /* Cluster IAM Role                                                     */
  /*----------------------------------------------------------------------*/
  create_iam_role                   = try(each.value.create_iam_role, var.eks_defaults.create_iam_role, true)
  iam_role_arn                      = try(each.value.iam_role_arn, var.eks_defaults.iam_role_arn, null)
  iam_role_name                     = try(each.value.iam_role_name, var.eks_defaults.iam_role_name, null)
  iam_role_use_name_prefix          = try(each.value.iam_role_use_name_prefix, var.eks_defaults.iam_role_use_name_prefix, false)
  iam_role_path                     = try(each.value.iam_role_path, var.eks_defaults.iam_role_path, null)
  iam_role_description              = try(each.value.iam_role_description, var.eks_defaults.iam_role_description, null)
  iam_role_permissions_boundary     = try(each.value.iam_role_permissions_boundary, var.eks_defaults.iam_role_permissions_boundary, null)
  iam_role_additional_policies      = try(each.value.iam_role_additional_policies, var.eks_defaults.iam_role_additional_policies, {})
  encryption_policy_use_name_prefix = try(each.value.cluster_encryption_policy_use_name_prefix, var.eks_defaults.cluster_encryption_policy_use_name_prefix, false)
  encryption_policy_name            = try(each.value.cluster_encryption_policy_name, var.eks_defaults.cluster_encryption_policy_name, null)
  encryption_policy_description     = try(each.value.cluster_encryption_policy_description, var.eks_defaults.cluster_encryption_policy_description, "Cluster encryption policy to allow cluster role to utilize CMK provided")
  encryption_policy_path            = try(each.value.cluster_encryption_policy_path, var.eks_defaults.cluster_encryption_policy_path, null)
  encryption_policy_tags            = try(each.value.cluster_encryption_policy_tags, var.eks_defaults.cluster_encryption_policy_tags, {})
  dataplane_wait_duration           = try(each.value.dataplane_wait_duration, var.eks_defaults.dataplane_wait_duration, "30s")
  enable_auto_mode_custom_tags      = try(each.value.enable_auto_mode_custom_tags, var.eks_defaults.enable_auto_mode_custom_tags, true)
  iam_role_tags                     = try(each.value.iam_role_tags, var.eks_defaults.iam_role_tags, {})

  /*----------------------------------------------------------------------*/
  /* EKS Addons                                                           */
  /*----------------------------------------------------------------------*/
  addons = try(each.value.cluster_addons, var.eks_defaults.cluster_addons, {
    coredns                = {}
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
    eks-pod-identity-agent = { before_compute = true }
  })
  addons_timeouts = try(each.value.cluster_addons_timeouts, var.eks_defaults.cluster_addons_timeouts, {})

  /*----------------------------------------------------------------------*/
  /* EKS Identity Provider                                                */
  /*----------------------------------------------------------------------*/
  identity_providers = try(each.value.cluster_identity_providers, var.eks_defaults.cluster_identity_providers, {})

  /*----------------------------------------------------------------------*/
  /* EKS Auto Node IAM Role                                               */
  /*----------------------------------------------------------------------*/
  create_node_iam_role               = try(each.value.create_node_iam_role, var.eks_defaults.create_node_iam_role, true)
  node_iam_role_name                 = try(each.value.node_iam_role_name, var.eks_defaults.node_iam_role_name, null)
  node_iam_role_use_name_prefix      = try(each.value.node_iam_role_use_name_prefix, var.eks_defaults.node_iam_role_use_name_prefix, false)
  node_iam_role_path                 = try(each.value.node_iam_role_path, var.eks_defaults.node_iam_role_path, null)
  node_iam_role_description          = try(each.value.node_iam_role_description, var.eks_defaults.node_iam_role_description, null)
  node_iam_role_permissions_boundary = try(each.value.node_iam_role_permissions_boundary, var.eks_defaults.node_iam_role_permissions_boundary, null)
  node_iam_role_additional_policies  = try(each.value.node_iam_role_additional_policies, var.eks_defaults.node_iam_role_additional_policies, {})
  node_iam_role_tags                 = try(each.value.node_iam_role_tags, var.eks_defaults.node_iam_role_tags, {})

  /*----------------------------------------------------------------------*/
  /* Fargate                                                              */
  /*----------------------------------------------------------------------*/
  fargate_profiles = try(each.value.fargate_profiles, var.eks_defaults.fargate_profiles, {})

  /*----------------------------------------------------------------------*/
  /* Self Managed Node Group                                              */
  /*----------------------------------------------------------------------*/
  self_managed_node_groups = try(each.value.self_managed_node_groups, var.eks_defaults.self_managed_node_groups, {})

  /*----------------------------------------------------------------------*/
  /* EKS Managed Node Group                                               */
  /*----------------------------------------------------------------------*/
  eks_managed_node_groups = try(each.value.managed_node_groups, var.eks_defaults.managed_node_groups, {})
}
