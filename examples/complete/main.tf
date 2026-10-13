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
      create = false

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

    # Observability: Grafana + Prometheus/Thanos (metrics) + Loki/Alloy (logs), todo en S3, exposed through the ALB Gateway.
    # Set create = true to deploy. Grafana: https://grafana.<zone_public>.
    #   aws eks update-kubeconfig --name dmc-lab-example-ex-observability --region us-east-2
    #   kubectl -n monitoring get secret kps-grafana -o jsonpath='{.data.admin-password}' | base64 -d
    #   kubectl -n monitoring port-forward svc/kps-grafana 3000:80     # alternative to DNS/ALB
    ex-observability = {
      create = true

      cluster_endpoint_public_access = true

      cluster_addons = {
        vpc-cni                = { before_compute = true }
        eks-pod-identity-agent = { before_compute = true }
        coredns                = {}
        kube-proxy             = {}
        aws-ebs-csi-driver     = {}
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
        # Association for the EBS CSI addon. Created after the cluster, so the addon
        # itself must wait for a second apply. See cluster_addons above.
        aws-ebs-csi-driver = {
          namespace                 = "kube-system"
          service_account           = "ebs-csi-controller-sa"
          attach_aws_ebs_csi_policy = true
        }
        # ServiceAccounts de monitoring -> S3, cada uno solo a su bucket.
        # Los nombres deben coincidir con los de los values de Helm (kps-prometheus, thanos-store, thanos-compact, loki).
        thanos-sidecar = {
          namespace       = "monitoring"
          service_account = "kps-prometheus"
          policy_statements = [
            {
              sid       = "ListBucket"
              actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
              resources = [module.observability_bucket["thanos"].s3_bucket_arn]
            },
            {
              sid = "Objects"
              actions = [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts",
              ]
              resources = ["${module.observability_bucket["thanos"].s3_bucket_arn}/*"]
            },
          ]
        }
        thanos-store = {
          namespace       = "monitoring"
          service_account = "thanos-store"
          policy_statements = [
            {
              sid       = "ListBucket"
              actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
              resources = [module.observability_bucket["thanos"].s3_bucket_arn]
            },
            {
              sid = "Objects"
              actions = [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts",
              ]
              resources = ["${module.observability_bucket["thanos"].s3_bucket_arn}/*"]
            },
          ]
        }
        thanos-compact = {
          namespace       = "monitoring"
          service_account = "thanos-compact"
          policy_statements = [
            {
              sid       = "ListBucket"
              actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
              resources = [module.observability_bucket["thanos"].s3_bucket_arn]
            },
            {
              sid = "Objects"
              actions = [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts",
              ]
              resources = ["${module.observability_bucket["thanos"].s3_bucket_arn}/*"]
            },
          ]
        }
        loki = {
          namespace       = "monitoring"
          service_account = "loki"
          policy_statements = [
            {
              sid       = "ListBucket"
              actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
              resources = [module.observability_bucket["loki"].s3_bucket_arn]
            },
            {
              sid = "Objects"
              actions = [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:AbortMultipartUpload",
                "s3:ListMultipartUploadParts",
              ]
              resources = ["${module.observability_bucket["loki"].s3_bucket_arn}/*"]
            },
          ]
        }
      }

      components = {
        # Gateway API + ALB controller + public Gateway (same as ex-components).
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
              clusterName: ${local.common_name}-ex-observability
              region: ${local.metadata.aws_region}
              vpcId: ${data.aws_vpc.this.id}
              defaultTargetType: ip
              # Reutiliza el certificado del webhook en cada upgrade. Sin esto, cada apply que cambia
              # los components lo regenera y los Services que se crean enseguida fallan con x509.
              keepTLSSecret: true
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
                  - name: https
                    protocol: HTTPS
                    port: 443
                    allowedRoutes:
                      namespaces:
                        from: All
            YAML
          }
        }

        # Namespace `monitoring` + gp3 StorageClass.
        # Needs aws-ebs-csi-driver ACTIVE (second apply). On the first apply comment
        # this group too: Prometheus and Loki --wait time out while PVCs stay unbound.
        "20-monitoring" = {
          "10-storage" = {
            kind   = "kubectl"
            source = "inline"
            yaml   = <<-YAML
              apiVersion: v1
              kind: Namespace
              metadata:
                name: monitoring
              ---
              apiVersion: storage.k8s.io/v1
              kind: StorageClass
              metadata:
                name: gp3
              provisioner: ebs.csi.aws.com
              parameters:
                type: gp3
                encrypted: "true"
              volumeBindingMode: WaitForFirstConsumer
              allowVolumeExpansion: true
            YAML
          }
          # Thanos: query + store gateway + compact (los bloques viven en S3). Va antes de kps
          # porque crea el Secret thanos-objstore que usa el sidecar.
          "15-thanos" = {
            kind             = "helm"
            source           = "repo"
            repository       = "https://stevehipwell.github.io/helm-charts/"
            chart            = "thanos"
            version          = "1.24.1"
            release          = "thanos"
            namespace        = "monitoring"
            create_namespace = false
            flags            = ["--wait", "--timeout", "10m"]
            values           = <<-YAML
              objstoreConfig:
                name: thanos-objstore
                value: |-
                  type: S3
                  config:
                    bucket: ${module.observability_bucket["thanos"].s3_bucket_id}
                    endpoint: s3.${local.metadata.aws_region}.amazonaws.com
                    region: ${local.metadata.aws_region}
              # Query tambien consulta al sidecar de Prometheus (datos recientes).
              additionalEndpoints:
                - dnssrv+_grpc._tcp.kps-thanos-discovery.monitoring.svc.cluster.local
              storeGateway:
                serviceAccount:
                  name: thanos-store
                persistence:
                  enabled: true
                  storageClass: gp3
                  size: 5Gi
              compact:
                enabled: true
                serviceAccount:
                  name: thanos-compact
                persistence:
                  enabled: true
                  storageClass: gp3
                  size: 10Gi
                # Retencion de metricas en S3: 180 dias.
                extraArgs:
                  - --retention.resolution-raw=180d
                  - --retention.resolution-5m=180d
                  - --retention.resolution-1h=180d
            YAML
          }
          # Prometheus (2 dias local + sidecar de Thanos hacia S3) + Alertmanager + Grafana.
          "20-metrics" = {
            kind             = "helm"
            source           = "repo"
            repository       = "https://prometheus-community.github.io/helm-charts"
            chart            = "kube-prometheus-stack"
            version          = "92.3.0"
            release          = "kps"
            namespace        = "monitoring"
            create_namespace = false
            flags            = ["--wait", "--timeout", "15m"]
            values           = <<-YAML
              fullnameOverride: kps
              prometheus:
                thanosService:
                  enabled: true
                prometheusSpec:
                  retention: 2d
                  thanos:
                    objectStorageConfig:
                      existingSecret:
                        name: thanos-objstore
                        key: config
                  storageSpec:
                    volumeClaimTemplate:
                      spec:
                        storageClassName: gp3
                        accessModes: ["ReadWriteOnce"]
                        resources:
                          requests:
                            storage: 10Gi
                  resources:
                    requests: { cpu: 200m, memory: 1Gi }
              alertmanager:
                alertmanagerSpec:
                  storage:
                    volumeClaimTemplate:
                      spec:
                        storageClassName: gp3
                        accessModes: ["ReadWriteOnce"]
                        resources:
                          requests:
                            storage: 2Gi
              grafana:
                # Solo se publican los 3 dashboards de este ejemplo (Logs, Namespace Resources, Nodes).
                defaultDashboardsEnabled: false
                # El chart genera una password aleatoria (Secret kps-grafana, key admin-password).
                adminPassword: ""
                persistence:
                  enabled: true
                  storageClassName: gp3
                  size: 5Gi
                grafana.ini:
                  server:
                    root_url: https://grafana.${local.zone_public}
                additionalDataSources:
                  - name: Loki
                    type: loki
                    uid: loki
                    access: proxy
                    url: http://loki.monitoring.svc.cluster.local:3100
                sidecar:
                  datasources:
                    # El datasource "Prometheus" apunta a Thanos Query (reciente + historico en S3).
                    url: http://thanos-query.monitoring.svc.cluster.local:10902
            YAML
          }
          # Logs: Loki SingleBinary sobre S3 (365 dias). El disco gp3 es solo WAL.
          "30-logs-loki" = {
            kind             = "helm"
            source           = "repo"
            repository       = "https://grafana-community.github.io/helm-charts"
            chart            = "loki"
            version          = "18.15.1"
            release          = "loki"
            namespace        = "monitoring"
            create_namespace = false
            flags            = ["--wait", "--timeout", "15m"]
            values           = <<-YAML
              deploymentMode: SingleBinary
              serviceAccount:
                name: loki
              loki:
                auth_enabled: false
                commonConfig:
                  replication_factor: 1
                storage:
                  type: s3
                  bucketNames:
                    chunks: ${module.observability_bucket["loki"].s3_bucket_id}
                    ruler: ${module.observability_bucket["loki"].s3_bucket_id}
                  s3:
                    region: ${local.metadata.aws_region}
                schemaConfig:
                  configs:
                    - from: "2024-04-01"
                      store: tsdb
                      object_store: s3
                      schema: v13
                      index:
                        prefix: loki_index_
                        period: 24h
                limits_config:
                  retention_period: 8760h
                compactor:
                  retention_enabled: true
                  delete_request_store: s3
              singleBinary:
                replicas: 1
                persistence:
                  size: 10Gi
                  storageClass: gp3
              write:
                replicas: 0
              read:
                replicas: 0
              backend:
                replicas: 0
              gateway:
                enabled: false
              chunksCache:
                enabled: false
              resultsCache:
                enabled: false
              lokiCanary:
                enabled: false
              test:
                enabled: false
            YAML
          }
          # Alloy (un pod por nodo) lee los logs de los pods y los manda a Loki.
          "31-logs-alloy" = {
            kind             = "helm"
            source           = "repo"
            repository       = "https://grafana.github.io/helm-charts"
            chart            = "alloy"
            version          = "1.13.1"
            release          = "alloy"
            namespace        = "monitoring"
            create_namespace = false
            flags            = ["--wait", "--timeout", "10m"]
            values           = <<-YAML
              controller:
                type: daemonset
              alloy:
                configMap:
                  content: |
                    discovery.kubernetes "pods" {
                      role = "pod"
                      selectors {
                        role  = "pod"
                        field = "spec.nodeName=" + coalesce(sys.env("HOSTNAME"), "")
                      }
                    }

                    discovery.relabel "pods" {
                      targets = discovery.kubernetes.pods.targets
                      rule {
                        source_labels = ["__meta_kubernetes_namespace"]
                        target_label  = "namespace"
                      }
                      rule {
                        source_labels = ["__meta_kubernetes_pod_name"]
                        target_label  = "pod"
                      }
                      rule {
                        source_labels = ["__meta_kubernetes_pod_container_name"]
                        target_label  = "container"
                      }
                    }

                    loki.source.kubernetes "pods" {
                      targets    = discovery.relabel.pods.output
                      forward_to = [loki.write.default.receiver]
                    }

                    loki.write "default" {
                      endpoint {
                        url = "http://loki.monitoring.svc.cluster.local:3100/loki/api/v1/push"
                      }
                    }
            YAML
          }
          # Dashboard "Kubernetes Logs" (Loki): filtros por namespace, pod y texto. El sidecar de Grafana lo carga solo.
          "32-dashboard-logs" = {
            kind   = "kubectl"
            source = "inline"
            yaml   = <<-YAML
              apiVersion: v1
              kind: ConfigMap
              metadata:
                name: dashboard-kubernetes-logs
                namespace: monitoring
                labels:
                  grafana_dashboard: "1"
              data:
                kubernetes-logs.json: |
                  {
                    "title": "Kubernetes Logs",
                    "uid": "k8s-logs",
                    "schemaVersion": 39,
                    "refresh": "30s",
                    "time": { "from": "now-1h", "to": "now" },
                    "templating": {
                      "list": [
                        {
                          "name": "namespace", "type": "query", "label": "Namespace",
                          "datasource": { "type": "loki", "uid": "loki" },
                          "query": "label_values(namespace)", "refresh": 2, "sort": 1
                        },
                        {
                          "name": "pod", "type": "query", "label": "Pod",
                          "datasource": { "type": "loki", "uid": "loki" },
                          "query": "label_values({namespace=\"$namespace\"}, pod)", "refresh": 2,
                          "multi": true, "includeAll": true, "allValue": ".*"
                        },
                        {
                          "name": "pod_filter",
                          "type": "textbox",
                          "label": "Pod regex (e.g. service-pepe-.*)",
                          "query": ".*"
                        },
                        { "name": "search", "type": "textbox", "label": "Search", "query": "" }
                      ]
                    },
                    "panels": [
                      {
                        "id": 1, "type": "timeseries", "title": "Log volume",
                        "gridPos": { "h": 6, "w": 24, "x": 0, "y": 0 },
                        "datasource": { "type": "loki", "uid": "loki" },
                        "targets": [{
                          "refId": "A",
                          "expr": "sum by (pod) (count_over_time({namespace=\"$namespace\", pod=~\"$pod\", pod=~\"$pod_filter\"} |~ \"(?i)$search\" [$__interval]))"
                        }]
                      },
                      {
                        "id": 2, "type": "logs", "title": "Logs",
                        "gridPos": { "h": 18, "w": 24, "x": 0, "y": 6 },
                        "datasource": { "type": "loki", "uid": "loki" },
                        "options": { "showTime": true, "wrapLogMessage": true, "sortOrder": "Descending", "enableLogDetails": true },
                        "targets": [{
                          "refId": "A",
                          "expr": "{namespace=\"$namespace\", pod=~\"$pod\", pod=~\"$pod_filter\"} |~ \"(?i)$search\""
                        }]
                      }
                    ]
                  }
            YAML
          }
          # Dashboard "Namespace Resources": CPU, memoria, red y estado de pods por namespace.
          "33-dashboard-namespace" = {
            kind   = "kubectl"
            source = "inline"
            yaml   = <<-YAML
              apiVersion: v1
              kind: ConfigMap
              metadata:
                name: dashboard-namespace-resources
                namespace: monitoring
                labels:
                  grafana_dashboard: "1"
              data:
                namespace-resources.json: |
                  {
                    "title": "Namespace Resources",
                    "uid": "k8s-namespace",
                    "schemaVersion": 39,
                    "refresh": "1m",
                    "time": {
                      "from": "now-3h",
                      "to": "now"
                    },
                    "templating": {
                      "list": [
                        {
                          "name": "namespace",
                          "type": "query",
                          "label": "Namespace",
                          "datasource": {
                            "type": "prometheus",
                            "uid": "prometheus"
                          },
                          "query": "label_values(kube_namespace_status_phase, namespace)",
                          "refresh": 2,
                          "sort": 1
                        },
                        {
                          "name": "pod",
                          "type": "query",
                          "label": "Pod",
                          "datasource": {
                            "type": "prometheus",
                            "uid": "prometheus"
                          },
                          "query": "label_values(kube_pod_info{namespace=\"$namespace\"}, pod)",
                          "refresh": 2,
                          "multi": true,
                          "includeAll": true,
                          "allValue": ".*"
                        },
                        {
                          "name": "pod_filter",
                          "type": "textbox",
                          "label": "Pod regex (e.g. service-pepe-.*)",
                          "query": ".*"
                        }
                      ]
                    },
                    "panels": [
                      {
                        "id": 1,
                        "type": "stat",
                        "title": "Running pods",
                        "gridPos": {
                          "h": 4,
                          "w": 6,
                          "x": 0,
                          "y": 0
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "short"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "sum(kube_pod_status_phase{namespace=\"$namespace\", pod=~\"$pod\", pod=~\"$pod_filter\",phase=\"Running\"})"
                          }
                        ]
                      },
                      {
                        "id": 2,
                        "type": "stat",
                        "title": "Pending / Failed pods",
                        "gridPos": {
                          "h": 4,
                          "w": 6,
                          "x": 6,
                          "y": 0
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "short"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "sum(kube_pod_status_phase{namespace=\"$namespace\", pod=~\"$pod\", pod=~\"$pod_filter\",phase=~\"Pending|Failed\"})"
                          }
                        ]
                      },
                      {
                        "id": 3,
                        "type": "stat",
                        "title": "Container restarts (1h)",
                        "gridPos": {
                          "h": 4,
                          "w": 6,
                          "x": 12,
                          "y": 0
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "short"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "sum(increase(kube_pod_container_status_restarts_total{namespace=\"$namespace\", pod=~\"$pod\", pod=~\"$pod_filter\"}[1h]))"
                          }
                        ]
                      },
                      {
                        "id": 4,
                        "type": "stat",
                        "title": "Memory used",
                        "gridPos": {
                          "h": 4,
                          "w": 6,
                          "x": 18,
                          "y": 0
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "bytes"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "sum(container_memory_working_set_bytes{namespace=\"$namespace\", pod=~\"$pod\", pod=~\"$pod_filter\",container!=\"\"})"
                          }
                        ]
                      },
                      {
                        "id": 5,
                        "type": "timeseries",
                        "title": "CPU by pod",
                        "gridPos": {
                          "h": 8,
                          "w": 12,
                          "x": 0,
                          "y": 4
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "short"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "sum by (pod) (rate(container_cpu_usage_seconds_total{namespace=\"$namespace\", pod=~\"$pod\", pod=~\"$pod_filter\",container!=\"\"}[$__rate_interval]))",
                            "legendFormat": "{{pod}}"
                          }
                        ]
                      },
                      {
                        "id": 6,
                        "type": "timeseries",
                        "title": "Memory by pod",
                        "gridPos": {
                          "h": 8,
                          "w": 12,
                          "x": 12,
                          "y": 4
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "bytes"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "sum by (pod) (container_memory_working_set_bytes{namespace=\"$namespace\", pod=~\"$pod\", pod=~\"$pod_filter\",container!=\"\"})",
                            "legendFormat": "{{pod}}"
                          }
                        ]
                      },
                      {
                        "id": 7,
                        "type": "timeseries",
                        "title": "Network received by pod",
                        "gridPos": {
                          "h": 8,
                          "w": 12,
                          "x": 0,
                          "y": 12
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "Bps"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "sum by (pod) (rate(container_network_receive_bytes_total{namespace=\"$namespace\", pod=~\"$pod\", pod=~\"$pod_filter\"}[$__rate_interval]))",
                            "legendFormat": "{{pod}}"
                          }
                        ]
                      },
                      {
                        "id": 8,
                        "type": "timeseries",
                        "title": "Network sent by pod",
                        "gridPos": {
                          "h": 8,
                          "w": 12,
                          "x": 12,
                          "y": 12
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "Bps"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "sum by (pod) (rate(container_network_transmit_bytes_total{namespace=\"$namespace\", pod=~\"$pod\", pod=~\"$pod_filter\"}[$__rate_interval]))",
                            "legendFormat": "{{pod}}"
                          }
                        ]
                      }
                    ]
                  }
            YAML
          }
          # Dashboard "Nodes": estado y uso de CPU, memoria, disco y red de los nodos.
          "34-dashboard-nodes" = {
            kind   = "kubectl"
            source = "inline"
            yaml   = <<-YAML
              apiVersion: v1
              kind: ConfigMap
              metadata:
                name: dashboard-nodes
                namespace: monitoring
                labels:
                  grafana_dashboard: "1"
              data:
                nodes.json: |
                  {
                    "title": "Nodes",
                    "uid": "k8s-nodes",
                    "schemaVersion": 39,
                    "refresh": "1m",
                    "time": {
                      "from": "now-3h",
                      "to": "now"
                    },
                    "templating": {
                      "list": []
                    },
                    "panels": [
                      {
                        "id": 1,
                        "type": "stat",
                        "title": "Nodes Ready",
                        "gridPos": {
                          "h": 4,
                          "w": 6,
                          "x": 0,
                          "y": 0
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "short"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "sum(kube_node_status_condition{condition=\"Ready\",status=\"true\"})"
                          }
                        ]
                      },
                      {
                        "id": 2,
                        "type": "stat",
                        "title": "Nodes not Ready",
                        "gridPos": {
                          "h": 4,
                          "w": 6,
                          "x": 6,
                          "y": 0
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "short"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "sum(kube_node_status_condition{condition=\"Ready\",status!=\"true\"})"
                          }
                        ]
                      },
                      {
                        "id": 3,
                        "type": "stat",
                        "title": "Running pods",
                        "gridPos": {
                          "h": 4,
                          "w": 6,
                          "x": 12,
                          "y": 0
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "short"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "sum(kubelet_running_pods)"
                          }
                        ]
                      },
                      {
                        "id": 4,
                        "type": "stat",
                        "title": "Pods not Running",
                        "gridPos": {
                          "h": 4,
                          "w": 6,
                          "x": 18,
                          "y": 0
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "short"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "sum(kube_pod_status_phase{phase=~\"Pending|Failed|Unknown\"})"
                          }
                        ]
                      },
                      {
                        "id": 5,
                        "type": "timeseries",
                        "title": "CPU usage by node",
                        "gridPos": {
                          "h": 8,
                          "w": 12,
                          "x": 0,
                          "y": 4
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "percentunit"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "1 - avg by (instance) (rate(node_cpu_seconds_total{mode=\"idle\"}[$__rate_interval]))",
                            "legendFormat": "{{instance}}"
                          }
                        ]
                      },
                      {
                        "id": 6,
                        "type": "timeseries",
                        "title": "Memory usage by node",
                        "gridPos": {
                          "h": 8,
                          "w": 12,
                          "x": 12,
                          "y": 4
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "percentunit"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "1 - (node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes)",
                            "legendFormat": "{{instance}}"
                          }
                        ]
                      },
                      {
                        "id": 7,
                        "type": "timeseries",
                        "title": "Disk usage by node",
                        "gridPos": {
                          "h": 8,
                          "w": 12,
                          "x": 0,
                          "y": 12
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "percentunit"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "1 - (node_filesystem_avail_bytes{fstype!~\"tmpfs|overlay\",mountpoint=\"/\"} / node_filesystem_size_bytes{fstype!~\"tmpfs|overlay\",mountpoint=\"/\"})",
                            "legendFormat": "{{instance}}"
                          }
                        ]
                      },
                      {
                        "id": 8,
                        "type": "timeseries",
                        "title": "Network by node",
                        "gridPos": {
                          "h": 8,
                          "w": 12,
                          "x": 12,
                          "y": 12
                        },
                        "datasource": {
                          "type": "prometheus",
                          "uid": "prometheus"
                        },
                        "fieldConfig": {
                          "defaults": {
                            "unit": "Bps"
                          },
                          "overrides": []
                        },
                        "targets": [
                          {
                            "refId": "A",
                            "expr": "sum by (instance) (rate(node_network_receive_bytes_total{device!~\"lo|veth.*|eni.*\"}[$__rate_interval]))",
                            "legendFormat": "{{instance}}"
                          }
                        ]
                      }
                    ]
                  }
            YAML
          }
          # https://grafana.<zone_public>
          "40-expose" = {
            kind   = "kubectl"
            source = "inline"
            yaml   = <<-YAML
                apiVersion: gateway.networking.k8s.io/v1
                kind: HTTPRoute
                metadata:
                  name: grafana
                  namespace: monitoring
                spec:
                  parentRefs:
                    - name: public-alb
                      namespace: default
                      sectionName: https
                  hostnames:
                    - grafana.${local.zone_public}
                  rules:
                    - backendRefs:
                        - name: kps-grafana
                          port: 80
              YAML
          }
        }
      }

      # Stack chico (un pod por componente). EBS PVCs no funcionan en Fargate.
      managed_node_groups = {
        default = {
          ami_type       = "AL2023_x86_64_STANDARD"
          instance_types = ["t3.large"]
          capacity_type  = "ON_DEMAND"
          min_size       = 2
          desired_size   = 2
          max_size       = 4
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
