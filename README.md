# Standard Platform - Terraform Module 🚀🚀
<p align="right"><a href="https://partners.amazonaws.com/partners/0018a00001hHve4AAC/GoCloud"><img src="https://img.shields.io/badge/AWS%20Partner-Advanced-orange?style=for-the-badge&logo=amazonaws&logoColor=white" alt="AWS Partner"/></a><a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-green?style=for-the-badge&logo=apache&logoColor=white" alt="LICENSE"/></a></p>

Welcome to the Standard Platform — a suite of reusable and production-ready Terraform modules purpose-built for AWS environments.
Each module encapsulates best practices, security configurations, and sensible defaults to simplify and standardize infrastructure provisioning across projects.

## 📦 Module: Terraform EKS Module
<p align="right"><a href="https://github.com/gocloudLa/terraform-aws-wrapper-eks/releases/latest"><img src="https://img.shields.io/github/v/release/gocloudLa/terraform-aws-wrapper-eks.svg?style=for-the-badge" alt="Latest Release"/></a><a href=""><img src="https://img.shields.io/github/last-commit/gocloudLa/terraform-aws-wrapper-eks.svg?style=for-the-badge" alt="Last Commit"/></a><a href="https://registry.terraform.io/modules/gocloudLa/wrapper-eks/aws"><img src="https://img.shields.io/badge/Terraform-Registry-7B42BC?style=for-the-badge&logo=terraform&logoColor=white" alt="Terraform Registry"/></a></p>
Terraform wrapper for Amazon EKS. Creates clusters, node groups, and integrations such as Karpenter, Pod Identity, and Load Balancer Controller subnet tags. Can also install cluster software (Helm / kubectl) during apply without a Kubernetes provider.

### ✨ Features

- 🏷️ [Metadata and VPC/subnet autodiscovery](#metadata-and-vpc/subnet-autodiscovery) - Cluster naming and network discovery from metadata

- ⚡ [Karpenter AWS resources](#karpenter-aws-resources) - IAM, SQS, pod identity, and discovery tags for Karpenter

- 🌐 [AWS Load Balancer Controller](#aws-load-balancer-controller) - Subnet tags, then install by hand or with `components`

- 🧩 [Cluster components](#cluster-components) - Install Helm and kubectl during apply, without a Kubernetes provider

- 🪪 [EKS Pod Identity](#eks-pod-identity) - IAM roles for Kubernetes service accounts

- 📦 [EKS Auto Mode](#eks-auto-mode) - Managed node pools without classic node groups



### 🔗 External Modules
| Name | Version |
|------|------:|
| <a href="https://github.com/terraform-aws-modules/terraform-aws-eks-pod-identity" target="_blank">terraform-aws-modules/eks-pod-identity/aws</a> | 2.8.0 |
| <a href="https://github.com/terraform-aws-modules/terraform-aws-eks" target="_blank">terraform-aws-modules/eks/aws</a> | 21.25.1 |
| <a href="https://github.com/terraform-aws-modules/terraform-aws-kms" target="_blank">terraform-aws-modules/kms/aws</a> | 4.0.0 |
| <a href="https://github.com/terraform-aws-modules/terraform-aws-lambda" target="_blank">terraform-aws-modules/lambda/aws</a> | 8.7.0 |



## 🚀 Quick Start
```hcl
eks_parameters = {
  "my-cluster" = {
    create = true
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
}
```


## 🔧 Additional Features Usage

### Metadata and VPC/subnet autodiscovery
Cluster names come from `metadata` (`common_name` + cluster key). VPC and subnets are discovered by tag (`Name = <common_name_prefix>` and `<common_name_prefix>-private*` / `-public*`). Override with `vpc_name`, `control_plane_subnet_ids`, or `subnet_ids`.


<details><summary>Configuration Code</summary>

```hcl
eks_parameters = {
  "my-cluster" = {
    create = true
    # vpc_name                 = "my-vpc"
    # control_plane_subnet_ids = ["subnet-aaa", "subnet-bbb"]
    # subnet_ids               = ["subnet-xxx", "subnet-yyy"]
    managed_node_groups = { ... }
  }
}
```


</details>


### Karpenter AWS resources
Set `karpenter.create = true` to create controller/node IAM, SQS, pod identity, access entry, and `karpenter.sh/discovery` tags on subnets and the node security group. Install the Helm chart and NodePool / EC2NodeClass yourself.


<details><summary>Configuration Code</summary>

```hcl
eks_parameters = {
  "my-cluster" = {
    create = true
    karpenter = {
      create = true
      # vpc_subnet_tag_value          = "my-value"
      # security_group_node_tag_value = "my-value"
    }
    managed_node_groups = {
      karpenter-controller = {
        labels = { "karpenter.sh/controller" = "true" }
        # ...
      }
    }
  }
}
```


</details>

<details><summary>How to install Karpenter (quick start)</summary>

# Karpenter: quick install on an EKS cluster

Minimal steps to deploy Karpenter on a newly created cluster. Adjust names, ARNs, version and tags to your environment.

## 1) Base variables

```bash
export CLUSTER_NAME="dmc-prd-ex-karpenter"           # cluster name
export REGION="us-east-1"                            # AWS region
export KARPENTER_VERSION="1.8.1"                     # chart version
```

## 2) Connect to the cluster

```bash
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
```

## 3) Get cluster endpoint

```bash
export CLUSTER_ENDPOINT=$(aws eks describe-cluster --name "$CLUSTER_NAME" --region "$REGION" --query "cluster.endpoint" --output text)
```

## 4) Add Helm repo

```bash
helm repo add karpenter https://charts.karpenter.sh
helm repo update
```

## 5) Install the chart (SA + Pod Identity already created by IaC)

The wrapper creates the ServiceAccount and Pod Identity association. We only reference the existing SA.

```bash
helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --version "${KARPENTER_VERSION}" --namespace "kube-system" --create-namespace \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --set-string nodeSelector."karpenter\.sh/controller"="true"
```

## 6) Verify

```bash
kubectl get pods -n kube-system
```

## 7) Example NodeClass and NodePool

Adjust subnet/SG selectors to the tags used by your VPC (by default the wrapper tags with `karpenter.sh/discovery = "<cluster-key>"`).

Apply with:

```bash
cat <<EOF | envsubst | kubectl apply -f -
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: kubernetes.io/arch
          operator: In
          values: ["amd64"]
        - key: kubernetes.io/os
          operator: In
          values: ["linux"]
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand"]
        - key: karpenter.k8s.aws/instance-category
          operator: In
          values: ["c", "m", "r"]
        - key: karpenter.k8s.aws/instance-generation
          operator: Gt
          values: ["2"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      expireAfter: 720h
  limits:
    cpu: 1000
  disruption:
    consolidationPolicy: WhenEmptyOrUnderutilized
    consolidateAfter: 1m
---
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  role: "${CLUSTER_NAME}"
  amiSelectorTerms:
    - alias: "al2023@latest"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
EOF
```

## 8) Test app to trigger a Karpenter node

Deploy a pod that requires a new node. Use the NodePool label (`karpenter.sh/nodepool=default`):

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: karpenter-demo
spec:
  replicas: 1
  selector:
    matchLabels:
      app: karpenter-demo
  template:
    metadata:
      labels:
        app: karpenter-demo
    spec:
      nodeSelector:
        karpenter.sh/nodepool: default
      containers:
        - name: pause
          image: public.ecr.aws/eks-distro/kubernetes/pause:3.9
          resources:
            requests:
              cpu: "500m"
              memory: "512Mi"
EOF

kubectl get pods -n default -w
kubectl get nodes -w
```


</details>


### AWS Load Balancer Controller
`aws_load_balancer_controller.create = true` tags public/private subnets (`kubernetes.io/role/elb` / `internal-elb`). IAM goes in `pod_identities` (`kube-system` / `aws-load-balancer-controller`). Install CRDs, Helm, and Gateway either by hand or with `components`.

- https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html
- https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/gateway/


<details><summary>Configuration Code</summary>

```hcl
eks_parameters = {
  "my-cluster" = {
    aws_load_balancer_controller = {
      create                 = true
      public_ingress_create  = true
      private_ingress_create = true
      # Optional: custom subnet name pattern or tags
      # public_subnet_name  = "*-public*"
      # private_subnet_name = "*-private*"
    }
    pod_identities = {
      aws-load-balancer-controller = {
        namespace                       = "kube-system"
        service_account                 = "aws-load-balancer-controller"
        attach_aws_lb_controller_policy = true
      }
    }
  }
}
```


</details>

<details><summary>How to install AWS Load Balancer Controller (Gateway API)</summary>

# AWS Load Balancer Controller: Gateway API on an EKS cluster

Manual install from a workstation. Subnet tags and Pod Identity come from this wrapper. Install CRDs, Helm, then Gateway and HTTPRoutes. To install during terraform apply instead, use components (next example). Adjust names, region, VPC, ACM ARN, and hostnames.

Helm: https://docs.aws.amazon.com/eks/latest/userguide/lbc-helm.html
Gateway CRDs: https://kubernetes-sigs.github.io/aws-load-balancer-controller/latest/guide/gateway/gateway/

## 1) Base variables

```bash
export CLUSTER_NAME="dmc-prd-my-cluster"
export REGION="us-east-1"
export VPC_ID="vpc-xxxxxxxx"
export ACM_CERT_ARN="arn:aws:acm:us-east-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx"
export LBC_CHART_VERSION="3.5.0"
```

## 2) Connect to the cluster

```bash
aws eks update-kubeconfig --name "$CLUSTER_NAME" --region "$REGION"
```

## 3) Gateway API CRDs and LBC Gateway CRDs

```bash
kubectl apply --server-side=true -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.2/standard-install.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes-sigs/aws-load-balancer-controller/v3.5.0/config/crd/gateway/gateway-crds.yaml
```

## 4) Install the Helm chart (Pod Identity already created by IaC)

Use ServiceAccount name `aws-load-balancer-controller` in `kube-system` (same as `pod_identities`). Do not set `eks.amazonaws.com/role-arn`. `defaultTargetType: ip` is required for ClusterIP Services with VPC CNI.

```bash
helm repo add eks https://aws.github.io/eks-charts
helm repo update
helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  --namespace kube-system \
  --version "${LBC_CHART_VERSION}" \
  --set clusterName="${CLUSTER_NAME}" \
  --set region="${REGION}" \
  --set vpcId="${VPC_ID}" \
  --set defaultTargetType=ip \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller
kubectl -n kube-system rollout status deploy/aws-load-balancer-controller
```

## 5) Public Gateway (one ALB)

ACM certificate must be in the same region as the cluster. LBC reads the cert from `LoadBalancerConfiguration`, not from `certificateRefs`.

```bash
cat <<EOF | kubectl apply -f -
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
      defaultCertificate: ${ACM_CERT_ARN}
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
EOF
kubectl get gateway public-alb -n default
```

Wait until `ADDRESS` is an `*.elb.amazonaws.com` hostname and Gateway `Accepted=True`.

## 6) Sample app (HTTPRoute rules on the same ALB)

```bash
cat <<'EOF' | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello
  namespace: default
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
        - name: hello
          image: public.ecr.aws/nginx/nginx:stable
          ports:
            - containerPort: 80
---
apiVersion: v1
kind: Service
metadata:
  name: hello
  namespace: default
spec:
  selector:
    app: hello
  ports:
    - port: 80
      targetPort: 80
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: http-to-https
  namespace: default
spec:
  parentRefs:
    - name: public-alb
      sectionName: http
  hostnames:
    - hello.example.com
  rules:
    - filters:
        - type: RequestRedirect
          requestRedirect:
            scheme: https
            statusCode: 301
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: hello
  namespace: default
spec:
  parentRefs:
    - name: public-alb
      sectionName: https
  hostnames:
    - hello.example.com
  rules:
    - backendRefs:
        - name: hello
          port: 80
EOF
```

Further apps: Deployment + Service + HTTPRoute with `parentRefs.name: public-alb`.

## 7) Test without DNS

```bash
HOST=hello.example.com
ALB=$(kubectl -n default get gateway public-alb -o jsonpath='{.status.addresses[0].value}')
IP=$(dig +short "$ALB" | head -n1)
curl -v --resolve "${HOST}:443:${IP}" "https://${HOST}/"
```

The ACM certificate must include `HOST` (or a matching wildcard). `--resolve` sends SNI and Host without creating a DNS record.


</details>

<details><summary>Install with components</summary>

```hcl
eks_parameters = {
  "my-cluster" = {
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
            clusterName: my-cluster
            region: us-east-1
            vpcId: vpc-xxxxxxxx
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
                  defaultCertificate: arn:aws:acm:us-east-1:123456789012:certificate/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
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
    }
  }
}
```


</details>


### Cluster components
`components` is a map of groups → steps (lexicographic order by key). Terraform uses only the AWS provider: Image Builder bakes `kube-apply`, the pack goes to S3, and a Fargate task applies it. The Lambda waiter has a 15 minute limit. Apply-only (no uninstall on destroy). Plan does not show Kubernetes diffs.

- `kubectl` — `url`, `file`, or `inline`
- `helm` — `repo` or `file`; optional `values` / `values_file`, `version`, `release`, `namespace`, `create_namespace`
- `kustomize` — `file` or `url`

Needs schedulable nodes and NAT or VPC endpoints. Debug with output `components` (`task_arn`, `log_group_name`) and CloudWatch.


<details><summary>Configuration Code</summary>

```hcl
eks_parameters = {
  "my-cluster" = {
    components = {
      "20-file" = {
        "00" = {
          kind   = "kubectl"
          source = "file"
          path   = "${path.module}/components/k8s/gateway.yaml"
        }
      }
      "50-namespaces" = {
        "00" = {
          kind   = "kubectl"
          source = "inline"
          yaml   = <<-YAML
            apiVersion: v1
            kind: Namespace
            metadata:
              name: app-a
          YAML
        }
      }
      "55-helm-file" = {
        "00" = {
          kind             = "helm"
          source           = "file"
          path             = "${path.module}/components/demo"
          release          = "demo"
          namespace        = "demo"
          create_namespace = true
        }
      }
    }
  }
}
```


</details>


### EKS Pod Identity
Each key in `pod_identities` creates an IAM role and an EKS association for a `namespace` + `service_account`. Pods using that ServiceAccount can call AWS APIs. Enable the agent with `cluster_addons.eks-pod-identity-agent = { before_compute = true }`.

Use managed flags for common controllers (`attach_aws_lb_controller_policy`, `attach_aws_ebs_csi_policy`, `attach_aws_efs_csi_policy`, `attach_mountpoint_s3_csi_policy`) or `policy_statements` / `additional_policy_arns` for any other workload (S3, SQS, Secrets Manager, and so on).


<details><summary>Configuration Code</summary>

```hcl
eks_parameters = {
  "my-cluster" = {
    cluster_addons = {
      eks-pod-identity-agent = { before_compute = true }
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
      # Any other app
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
  }
}
```


</details>


### EKS Auto Mode
Set `cluster_compute_config.enabled = true` and `node_pools` (e.g. `["general-purpose"]`).


<details><summary>Configuration Code</summary>

```hcl
eks_parameters = {
  "my-cluster" = {
    create = true
    cluster_compute_config = {
      enabled    = true
      node_pools = ["general-purpose"]
    }
  }
}
```


</details>




## 📑 Inputs
| Name                                                | Description                                                                                                                                                                                                    | Type           | Default                                                               | Required |
| --------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------- | --------------------------------------------------------------------- | -------- |
| create                                              | Whether to create this EKS cluster.                                                                                                                                                                            | `bool`         | `true`                                                                | no       |
| cluster_name                                        | EKS cluster name.                                                                                                                                                                                              | `string`       | `"${local.common_name}-${each.key}"`                                  | no       |
| cluster_version                                     | Kubernetes API version (e.g. `"1.36"`).                                                                                                                                                                        | `string`       | `"1.36"`                                                              | no       |
| vpc_name                                            | VPC name (tag `Name`) used to discover VPC.                                                                                                                                                                    | `string`       | `local.default_vpc_name`                                              | no       |
| subnet_ids                                          | Explicit list of subnet IDs for node groups. If empty, subnets are discovered by tag.                                                                                                                          | `list(string)` | (discovered)                                                          | no       |
| control_plane_subnet_ids                            | Subnet IDs for the control plane.                                                                                                                                                                              | `list(string)` | `[]`                                                                  | no       |
| cluster_endpoint_public_access                      | Enable public API endpoint.                                                                                                                                                                                    | `bool`         | `false`                                                               | no       |
| cluster_endpoint_private_access                     | Enable private API endpoint.                                                                                                                                                                                   | `bool`         | `true`                                                                | no       |
| cluster_endpoint_public_access_cidrs                | CIDRs allowed to reach the public endpoint.                                                                                                                                                                    | `list(string)` | `["0.0.0.0/0"]`                                                       | no       |
| cluster_enabled_log_types                           | Control plane log types: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler`.                                                                                                                    | `list(string)` | `["api", "audit", "authenticator", "controllerManager", "scheduler"]` | no       |
| create_cloudwatch_log_group                         | Create a CloudWatch log group for control plane logs.                                                                                                                                                          | `bool`         | `true`                                                                | no       |
| cloudwatch_log_group_retention_in_days              | Retention in days for the control plane log group.                                                                                                                                                             | `number`       | `30`                                                                  | no       |
| cluster_addons                                      | Map of addon name → config (`before_compute`, `namespace_config`, `pod_identity_association`, etc.).                                                                                                           | `map(any)`     | coredns, kube-proxy, vpc-cni, eks-pod-identity-agent                  | no       |
| control_plane_egress_mode                           | Control plane egress: `AWS_MANAGED` or `CUSTOMER_ROUTED`.                                                                                                                                                      | `string`       | (AWS default)                                                         | no       |
| kube_scheduler_config                               | Control plane kube-scheduler (`node_resources_fit.scoring_strategy`).                                                                                                                                          | `object`       | `null`                                                                | no       |
| enable_cluster_creator_admin_permissions            | Grant cluster creator IAM principal full admin via EKS access entries.                                                                                                                                         | `bool`         | `true`                                                                | no       |
| access_entries                                      | Map of access entry key → `principal_arn`, `policy_associations`, etc. for explicit cluster access.                                                                                                            | `map(any)`     | `{}`                                                                  | no       |
| managed_node_groups                                 | Map of node group name → config (`ami_type`, `instance_types`, `capacity_type`, `min_size`, `desired_size`, `max_size`, etc.).                                                                                 | `map(any)`     | `{}`                                                                  | no       |
| cluster_compute_config                              | EKS Auto Mode: set `enabled = true` and `node_pools = ["general-purpose"]` to use managed node pools only.                                                                                                     | `object`       | `{}`                                                                  | no       |
| tags                                                | Tags applied to cluster and related resources.                                                                                                                                                                 | `map(string)`  | `local.common_tags`                                                   | no       |
| karpenter                                           | Config for Karpenter AWS resources. Set `create = true` to create IAM roles, SQS queue, pod identity, and discovery tags.                                                                                      | `object`       | `{}`                                                                  | no       |
| karpenter.create                                    | Enable creation of Karpenter AWS resources (controller IAM role, node IAM role, SQS, subnet/SG tags).                                                                                                          | `bool`         | `false`                                                               | no       |
| karpenter.vpc_subnet_tag_value                      | Custom value for subnet tag `karpenter.sh/discovery`; use in EC2NodeClass `subnetSelectorTerms`.                                                                                                               | `string`       | (cluster name)                                                        | no       |
| karpenter.security_group_node_tag_value             | Custom value for node security group tag `karpenter.sh/discovery`; use in EC2NodeClass `securityGroupSelectorTerms`.                                                                                           | `string`       | (cluster name)                                                        | no       |
| karpenter.node_iam_role_source_account_condition    | Restrict Karpenter node IAM trust to the cluster account (`aws:SourceAccount`).                                                                                                                                | `bool`         | `false`                                                               | no       |
| aws_load_balancer_controller                        | Config for subnet tagging so the AWS LB controller can create NLBs/ALBs.                                                                                                                                       | `object`       | `{}`                                                                  | no       |
| aws_load_balancer_controller.create                 | Enable tagging of subnets for the AWS Load Balancer Controller.                                                                                                                                                | `bool`         | `false`                                                               | no       |
| aws_load_balancer_controller.public_ingress_create  | Tag public subnets with `kubernetes.io/role/elb`.                                                                                                                                                              | `bool`         | —                                                                     | no       |
| aws_load_balancer_controller.private_ingress_create | Tag private subnets with `kubernetes.io/role/internal-elb`.                                                                                                                                                    | `bool`         | —                                                                     | no       |
| aws_load_balancer_controller.public_subnet_name     | Tag filter for public subnets (e.g. `"*-public*"`).                                                                                                                                                            | `string`       | (from metadata)                                                       | no       |
| aws_load_balancer_controller.private_subnet_name    | Tag filter for private subnets (e.g. `"*-private*"`).                                                                                                                                                          | `string`       | (from metadata)                                                       | no       |
| pod_identities                                      | Map of IAM roles for ServiceAccounts. Each entry needs `namespace` and `service_account`; use `attach_aws_*_policy` for known controllers or `policy_statements` / `additional_policy_arns` for any other app. | `map(any)`     | `{}`                                                                  | no       |
| components                                          | Map of group → step to install cluster software (Helm / kubectl). Order is lexicographic by group key, then step key.                                                                                          | `map(any)`     | `{}`                                                                  | no       |
| components.<group>.<step>.kind                      | Step kind: `kubectl`, `helm`, or `kustomize`.                                                                                                                                                                  | `string`       | —                                                                     | yes      |
| components.<group>.<step>.source                    | `url` / `file` / `inline` (kubectl), `repo` / `file` (helm), `file` / `url` (kustomize).                                                                                                                       | `string`       | —                                                                     | no       |
| components.<group>.<step>.url                       | Remote manifest (`kubectl` / `kustomize` with `source = url`).                                                                                                                                                 | `string`       | `null`                                                                | no       |
| components.<group>.<step>.path                      | Local file or directory packed into S3 (`source = file`).                                                                                                                                                      | `string`       | `null`                                                                | no       |
| components.<group>.<step>.yaml                      | Inline Kubernetes YAML (`kubectl` with `source = inline`).                                                                                                                                                     | `string`       | `null`                                                                | no       |
| components.<group>.<step>.repository                | Helm repo URL or `oci://…` (`helm` with `source = repo`).                                                                                                                                                      | `string`       | `null`                                                                | no       |
| components.<group>.<step>.chart                     | Helm chart name.                                                                                                                                                                                               | `string`       | `null`                                                                | no       |
| components.<group>.<step>.version                   | Helm chart version.                                                                                                                                                                                            | `string`       | `null`                                                                | no       |
| components.<group>.<step>.release                   | Helm release name.                                                                                                                                                                                             | `string`       | `null`                                                                | no       |
| components.<group>.<step>.namespace                 | Helm release namespace.                                                                                                                                                                                        | `string`       | `null`                                                                | no       |
| components.<group>.<step>.create_namespace          | Pass `--create-namespace` to Helm.                                                                                                                                                                             | `bool`         | `false`                                                               | no       |
| components.<group>.<step>.values                    | Inline Helm values YAML (packed as `values.yaml`).                                                                                                                                                             | `string`       | `null`                                                                | no       |
| components.<group>.<step>.values_file               | Path to a local Helm values file.                                                                                                                                                                              | `string`       | `null`                                                                | no       |
| components.<group>.<step>.flags                     | Extra argv for kubectl/helm (e.g. `--server-side`, `--wait`).                                                                                                                                                  | `list(string)` | `[]`                                                                  | no       |







## ⚠️ Important Notes
- **⚠️ Access:** Use `access_entries` or `enable_cluster_creator_admin_permissions = true` to grant cluster access.
- **⚠️ Karpenter:** This module creates AWS prerequisites only. Install the Helm chart and NodePool / EC2NodeClass yourself.
- **⚠️ AWS Load Balancer Controller:** `create` only tags subnets. Put IAM in `pod_identities`, then install CRDs + Helm by hand or with `components`.
- **⚠️ Cluster components:** Needs NAT/endpoints and schedulable nodes. Lambda waiter max 15 minutes (Helm `--wait` must fit). Apply-only; no Kubernetes diffs in plan. Do not put secrets in the pack.
- **⚠️ Pod Identity:** Set `cluster_addons.eks-pod-identity-agent = { before_compute = true }`. CSI add-ons that need an association become Active after it exists.



---

## 🤝 Contributing
We welcome contributions! Please see our contributing guidelines for more details.

## 🆘 Support
- 📧 **Email**: info@gocloud.la

## 🧑‍💻 About
We are focused on Cloud Engineering, DevOps, and Infrastructure as Code.
We specialize in helping companies design, implement, and operate secure and scalable cloud-native platforms.
- 🌎 [www.gocloud.la](https://www.gocloud.la)
- ☁️ AWS Advanced Partner (Terraform, DevOps, GenAI)
- 📫 Contact: info@gocloud.la

## 📄 License
This project is licensed under the Apache 2.0 License - see the [LICENSE](LICENSE) file for details. 