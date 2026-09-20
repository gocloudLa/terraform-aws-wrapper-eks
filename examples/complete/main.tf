module "wrapper_eks" {
  source = "../../"

  metadata = local.metadata

  eks_parameters = {
    ex-node-group = {
      create = true
      # Default: false (private API). Public so kubectl works without VPN/bastion.
      cluster_endpoint_public_access = true
      # To use a custom cluster name instead of the one derived from metadata:
      # cluster_name = "ex-node-group"

      # Optional: override VPC/subnet names instead of autodiscovery (<company>-<environment>-private*)
      # vpc_name                 = "custom-vpc-name"
      # control_plane_subnet_ids = ["subnet-aaa", "subnet-bbb", "subnet-ccc"]
      # subnet_ids               = ["subnet-xxx", "subnet-yyy", "subnet-zzz"]

      cluster_addons = {
        vpc-cni                = { before_compute = true }
        eks-pod-identity-agent = { before_compute = true }
        coredns                = {}
        kube-proxy             = {}
        metrics-server         = {}
        kube-state-metrics     = {}
        # After first apply (Pod Identity exists): aws-ebs-csi-driver, aws-efs-csi-driver, aws-mountpoint-s3-csi-driver
        aws-ebs-csi-driver = {}
        # aws-efs-csi-driver                    = {}
        # aws-mountpoint-s3-csi-driver          = {}
        # aws-secrets-store-csi-driver-provider = {}
      }

      # Subnet tagging only. Pod Identity for the controller is declared below.
      aws_load_balancer_controller = {
        create                 = true # Default: false
        public_ingress_create  = true
        private_ingress_create = true
        # Optional: customize subnet names when not using autodiscovery
        # public_subnet_name  = "custom-public-*"
        # private_subnet_name = "custom-private-*"
        # Optional: customize discovery tags
        # aws_load_balancer_controller_vpc_public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
        # aws_load_balancer_controller_vpc_private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
      }

      pod_identities = {
        aws-load-balancer-controller = {
          namespace                       = "kube-system"
          service_account                 = "aws-load-balancer-controller"
          attach_aws_lb_controller_policy = true
        }
        aws-ebs-csi-driver = {
          namespace                 = "kube-system"
          service_account           = "ebs-csi-controller-sa"
          attach_aws_ebs_csi_policy = true
        }
        # aws-efs-csi-driver = {
        #   namespace                 = "kube-system"
        #   service_account           = "efs-csi-controller-sa"
        #   attach_aws_efs_csi_policy = true
        # }
        # aws-mountpoint-s3-csi-driver = {
        #   namespace                         = "kube-system"
        #   service_account                   = "s3-csi-driver-sa"
        #   attach_mountpoint_s3_csi_policy   = true
        #   mountpoint_s3_csi_bucket_arns     = ["arn:aws:s3:::example-bucket"]
        #   mountpoint_s3_csi_bucket_path_arns = ["arn:aws:s3:::example-bucket/*"]
        # }
        example-s3 = {
          namespace       = "apps"
          service_account = "example"
          policy_statements = [{
            sid       = "ReadBucket"
            actions   = ["s3:GetObject", "s3:ListBucket"]
            resources = ["arn:aws:s3:::example-bucket", "arn:aws:s3:::example-bucket/*"]
          }]
        }
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
        create = true # Default: false
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
