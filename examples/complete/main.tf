module "wrapper_eks" {
  source = "../../"

  metadata = local.metadata

  eks_parameters = {
    ex-node-group = {
      create = true
      # To use a custom cluster name instead of the one derived from metadata:
      # cluster_name = "ex-node-group"

      # Optional: override VPC/subnet names instead of autodiscovery (<company>-<environment>-private*)
      # vpc_name                 = "custom-vpc-name"
      # control_plane_subnet_ids = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
      # subnet_ids               = ["subnet-xxx", "subnet-yyy", "subnet-zzz"]

      # Subnet tagging for AWS Load Balancer Controller (public/private subnets)
      aws_load_balancer_controller = {
        create                 = true
        public_ingress_create  = true
        private_ingress_create = true
        # Optional: customize subnet names when not using autodiscovery
        # public_subnet_name  = "custom-public-*"
        # private_subnet_name = "custom-private-*"
        # Optional: customize discovery tags
        # aws_load_balancer_controller_vpc_public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
        # aws_load_balancer_controller_vpc_private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
      }
      managed_node_groups = {
        default = {
          ami_type       = "AL2023_x86_64_STANDARD"
          instance_types = ["t3.medium"]
          capacity_type  = "ON_DEMAND"
          min_size       = 1
          desired_size   = 2
          max_size       = 3
        }
      }
    }

    ex-karpenter = {
      create = true
      # To use a custom cluster name instead of the one derived from metadata:
      # cluster_name = "ex-karpenter"

      # Enable AWS resources required by Karpenter (IAM, SQS, etc.)
      karpenter = {
        create = true
        # If you set the subnet tag value, you can reference it in the node class so the provisioner
        # places nodes in those subnets (as set when creating the cluster with subnet_id)
        # vpc_subnet_tag_value = "custom-tag"
        # If node security group creation is enabled, you can customize the tag value
        # to reference in the node class
        # security_group_node_tag_value = "custom-tag"
      }

      # Node group to run the Karpenter controller (Helm is installed outside this module).
      managed_node_groups = {
        default = {
          ami_type       = "AL2023_x86_64_STANDARD"
          instance_types = ["t3.medium"]
          capacity_type  = "ON_DEMAND"
          min_size       = 1
          desired_size   = 1
          max_size       = 2
          labels = {
            # Required label so Karpenter detects this node as the controller
            "karpenter.sh/controller" = "true"
          }
        }
      }

      # Use Karpenter for dynamic capacity; define your Provisioner/NodePool after deployment.
    }
    ex-auto-mode = {
      # Example with EKS Auto Mode (no classic node groups)
      create = false
      # To use a custom cluster name instead of the one derived from metadata:
      # cluster_name = "ex-auto-mode"
      cluster_compute_config = {
        enabled    = true
        node_pools = ["general-purpose"]
      }
    }
  }

  eks_defaults = var.eks_defaults
}
