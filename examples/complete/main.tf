module "wrapper_eks" {
  source = "../../"

  metadata = local.metadata

  eks_parameters = {
    ex-node-group = {
      create = false
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
      create = false
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
    ex-components = {
      create = true

      cluster_endpoint_public_access = true

      cluster_addons = {
        vpc-cni                = { before_compute = true }
        eks-pod-identity-agent = { before_compute = true }
        coredns                = {}
        kube-proxy             = {}
      }

      aws_load_balancer_controller = {
        create                 = true
        public_ingress_create  = true
        private_ingress_create = true
      }

      pod_identities = {
        aws-load-balancer-controller = {
          namespace                       = "kube-system"
          service_account                 = "aws-load-balancer-controller"
          attach_aws_lb_controller_policy = true
        }
      }

      # Every kind/source in v1 except kustomize. Order is lexicographic. Drop groups to apply a subset.
      components = {
        "10-lbc" = {
          "00" = {
            kind   = "kubectl"
            source = "url"
            url    = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.2/standard-install.yaml"
            flags  = ["--server-side=true"]
          }
          "01" = {
            kind   = "kubectl"
            source = "url"
            url    = "https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.5.0/config/crd/gateway/gateway-crds.yaml"
          }
          "02" = {
            kind             = "helm"
            source           = "repo"
            repository       = "https://aws.github.io/eks-charts"
            chart            = "aws-load-balancer-controller"
            version          = "3.5.0"
            release          = "aws-load-balancer-controller"
            namespace        = "kube-system"
            create_namespace = false
            flags            = ["--wait", "--timeout", "10m"]
            values           = <<-YAML
              clusterName: ${local.common_name}-ex-components
              region: ${local.metadata.aws_region}
              vpcId: ${data.aws_vpc.this.id}
              defaultTargetType: ip
              serviceAccount:
                create: true
                name: aws-load-balancer-controller
            YAML
          }
          "03" = {
            kind   = "kubectl"
            source = "inline"
            yaml   = <<-YAML
              apiVersion: gateway.networking.k8s.io/v1
              kind: GatewayClass
              metadata:
                name: aws-alb
              spec:
                controllerName: gateway.k8s.aws/alb
              ---
              apiVersion: gateway.k8s.aws/v1
              kind: LoadBalancerConfiguration
              metadata:
                name: public-alb
                namespace: default
              spec:
                scheme: internet-facing
                listenerConfigurations:
                  - protocolPort: HTTPS:443
                    defaultCertificate: ${data.aws_acm_certificate.this.arn}
              ---
              apiVersion: gateway.networking.k8s.io/v1
              kind: Gateway
              metadata:
                name: public-alb
                namespace: default
              spec:
                gatewayClassName: aws-alb
                infrastructure:
                  parametersRef:
                    group: gateway.k8s.aws
                    kind: LoadBalancerConfiguration
                    name: public-alb
                listeners:
                  - name: http
                    protocol: HTTP
                    port: 80
                    allowedRoutes:
                      namespaces:
                        from: All
                  - name: https
                    protocol: HTTPS
                    port: 443
                    allowedRoutes:
                      namespaces:
                        from: All
            YAML
          }
        }

        # After apply, test without DNS:
        #   aws eks update-kubeconfig --name dmc-lab-example-ex-components --region us-east-2
        #   HOST=hello.lab.democorp.cloud
        #   ALB=$(kubectl -n default get gateway public-alb -o jsonpath='{.status.addresses[0].value}')
        #   IP=$(dig +short "$ALB" | head -n1)
        #   curl -v --resolve "${HOST}:443:${IP}" "https://${HOST}/"
        "15-sample-app" = {
          "00" = {
            kind   = "kubectl"
            source = "inline"
            yaml   = <<-YAML
              apiVersion: apps/v1
              kind: Deployment
              metadata:
                name: hello
              spec:
                replicas: 1
                selector:
                  matchLabels:
                    app: hello
                template:
                  metadata:
                    labels:
                      app: hello
                  spec:
                    containers:
                      - name: nginx
                        image: public.ecr.aws/nginx/nginx:stable
                        ports:
                          - containerPort: 80
              ---
              apiVersion: v1
              kind: Service
              metadata:
                name: hello
              spec:
                selector:
                  app: hello
                ports:
                  - port: 80
              ---
              apiVersion: gateway.networking.k8s.io/v1
              kind: HTTPRoute
              metadata:
                name: hello
              spec:
                parentRefs:
                  - name: public-alb
                    sectionName: https
                hostnames:
                  - hello.${local.zone_public}
                rules:
                  - backendRefs:
                      - name: hello
                        port: 80
            YAML
          }
        }

        # "20-file" = {
        #   "00" = {
        #     kind   = "kubectl"
        #     source = "file"
        #     path   = "${path.module}/components/k8s/gateway.yaml"
        #   }
        # }

        # "35-wordpress" = {
        #   "00" = {
        #     kind             = "helm"
        #     source           = "repo"
        #     repository       = "oci://registry-1.docker.io/bitnamicharts"
        #     chart            = "wordpress"
        #     version          = "24.2.3"
        #     release          = "wordpress"
        #     namespace        = "wordpress"
        #     create_namespace = true
        #     values           = <<-YAML
        #       service:
        #         type: ClusterIP
        #       persistence:
        #         enabled: false
        #       mariadb:
        #         primary:
        #           persistence:
        #             enabled: false
        #     YAML
        #   }
        # }

        # "40-url" = {
        #   "00" = {
        #     kind   = "kubectl"
        #     source = "url"
        #     url    = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-install.yaml"
        #     flags  = ["--server-side=true"]
        #   }
        # }

        # "50-namespaces" = {
        #   "00" = {
        #     kind   = "kubectl"
        #     source = "inline"
        #     yaml   = <<-YAML
        #       apiVersion: v1
        #       kind: Namespace
        #       metadata:
        #         name: app-a
        #       ---
        #       apiVersion: v1
        #       kind: Namespace
        #       metadata:
        #         name: app-b
        #     YAML
        #   }
        # }

        # "55-helm-file" = {
        #   "00" = {
        #     kind             = "helm"
        #     source           = "file"
        #     path             = "${path.module}/components/demo"
        #     release          = "demo"
        #     namespace        = "demo"
        #     create_namespace = true
        #   }
        # }
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
