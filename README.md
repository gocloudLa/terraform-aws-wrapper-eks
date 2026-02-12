# Standard Platform - Terraform Module 🚀🚀
<p align="right"><a href="https://partners.amazonaws.com/partners/0018a00001hHve4AAC/GoCloud"><img src="https://img.shields.io/badge/AWS%20Partner-Advanced-orange?style=for-the-badge&logo=amazonaws&logoColor=white" alt="AWS Partner"/></a><a href="LICENSE"><img src="https://img.shields.io/badge/License-Apache%202.0-green?style=for-the-badge&logo=apache&logoColor=white" alt="LICENSE"/></a></p>

Welcome to the Standard Platform — a suite of reusable and production-ready Terraform modules purpose-built for AWS environments.
Each module encapsulates best practices, security configurations, and sensible defaults to simplify and standardize infrastructure provisioning across projects.

## 📦 Module: Terraform EKS Module
<p align="right"><a href="https://github.com/gocloudLa/terraform-aws-wrapper-eks/releases/latest"><img src="https://img.shields.io/github/v/release/gocloudLa/terraform-aws-wrapper-eks.svg?style=for-the-badge" alt="Latest Release"/></a><a href=""><img src="https://img.shields.io/github/last-commit/gocloudLa/terraform-aws-wrapper-eks.svg?style=for-the-badge" alt="Last Commit"/></a><a href="https://registry.terraform.io/modules/gocloudLa/wrapper-eks/aws"><img src="https://img.shields.io/badge/Terraform-Registry-7B42BC?style=for-the-badge&logo=terraform&logoColor=white" alt="Terraform Registry"/></a></p>
The Terraform wrapper for EKS simplifies the configuration of Amazon Elastic Kubernetes Service in the AWS cloud. This wrapper functions as a predefined template, facilitating the creation and management of EKS clusters, node groups, and integrations such as Karpenter by handling all the technical details.

### ✨ Features

- 🏷️ [Metadata and VPC/subnet autodiscovery](#metadata-and-vpc/subnet-autodiscovery) - Cluster naming and network discovery from a single metadata structure

- ⚡ [Karpenter AWS resources](#karpenter-aws-resources) - One-block setup of IAM, SQS, pod identity, and discovery tags for Karpenter

- 🌐 [AWS Load Balancer Controller subnet tagging](#aws-load-balancer-controller-subnet-tagging) - Automatic tagging of subnets for public and private ingress

- 📦 [EKS Auto Mode](#eks-auto-mode) - Use EKS managed node pools without managing node groups



### 🔗 External Modules
| Name | Version |
|------|------:|
| <a href="https://github.com/terraform-aws-modules/terraform-aws-eks" target="_blank">terraform-aws-modules/eks/aws</a> | 21.9.0 |
| <a href="https://github.com/terraform-aws-modules/terraform-aws-kms" target="_blank">terraform-aws-modules/kms/aws</a> | 4.0.0 |



## 🚀 Quick Start
```hcl
module "wrapper_eks" {
  source = "gocloudLa/wrapper-eks/aws"

  metadata = local.metadata

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
}
```


## 🔧 Additional Features Usage

### Metadata and VPC/subnet autodiscovery
The wrapper derives cluster names from `metadata` (e.g. `local.common_name` + cluster key) and discovers VPC and subnets by convention: VPC by tag `Name = <common_name_prefix>` and subnets by tag `Name = <common_name_prefix>-private*` or `-public*`. Override with `vpc_name`, `control_plane_subnet_ids`, or `subnet_ids` when you need custom network layout.


<details><summary>Configuration Code</summary>

```hcl
# Cluster name becomes e.g. dmc-prd-my-cluster from metadata + key
eks_parameters = {
  "my-cluster" = {
    create = true
    # Optional: override autodiscovery
    # vpc_name                 = "my-vpc"
    # control_plane_subnet_ids = ["subnet-aaa", "subnet-bbb"]
    # subnet_ids               = ["subnet-xxx", "subnet-yyy"]
    managed_node_groups = { ... }
  }
}
```


</details>


### Karpenter AWS resources
Enable `karpenter.create = true` to create the controller IAM role, node IAM role (and instance profile), SQS queue for spot termination, pod identity association, and EKS access entry. The wrapper also applies subnet and security group discovery tags (`karpenter.sh/discovery`) so you can reference them in EC2NodeClass. Install the Karpenter Helm chart and define Provisioner/NodePool separately.


<details><summary>Configuration Code</summary>

```hcl
"my-cluster" = {
  create = true
  karpenter = {
    create = true
    # Optional: custom tag values for NodeClass subnet/SG selectors
    # vpc_subnet_tag_value        = "my-value"
    # security_group_node_tag_value = "my-value"
  }
  managed_node_groups = {
    karpenter-controller = {
      labels = { "karpenter.sh/controller" = "true" }
      # ...
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

## 4) Create namespace and add Helm repo

```bash
kubectl create namespace karpenter
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
kubectl get pods -n karpenter
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


### AWS Load Balancer Controller subnet tagging
Set `aws_load_balancer_controller.create = true` and choose `public_ingress_create` and/or `private_ingress_create`. The wrapper discovers the relevant subnets (by default using the same naming convention as the cluster) and applies `kubernetes.io/role/elb` and `kubernetes.io/role/internal-elb` so the AWS Load Balancer Controller can create NLBs/ALBs in the right subnets. Optional custom subnet names and tags are supported.


<details><summary>Configuration Code</summary>

```hcl
aws_load_balancer_controller = {
  create                  = true
  public_ingress_create   = true
  private_ingress_create  = true
  # Optional: custom subnet name pattern or tags
  # public_subnet_name  = "*-public*"
  # private_subnet_name = "*-private*"
  # aws_load_balancer_controller_vpc_public_subnet_tags  = { "kubernetes.io/role/elb" = 1 }
  # aws_load_balancer_controller_vpc_private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }
}
```


</details>


### EKS Auto Mode
Set `cluster_compute_config.enabled = true` and specify `node_pools` (e.g. `["general-purpose"]`). The control plane manages capacity; no managed node groups or Karpenter are required for basic workloads.


<details><summary>Configuration Code</summary>

```hcl
"my-cluster" = {
  create = true
  cluster_compute_config = {
    enabled    = true
    node_pools = ["general-purpose"]
  }
}
```


</details>




## 📑 Inputs
| Name                                                | Description                                                                                                                    | Type           | Default                                                               | Required |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------ | -------------- | --------------------------------------------------------------------- | -------- |
| create                                              | Whether to create this EKS cluster.                                                                                            | `bool`         | `true`                                                                | no       |
| cluster_name                                        | EKS cluster name.                                                                                                              | `string`       | `"${local.common_name}-${each.key}"`                                  | no       |
| cluster_version                                     | Kubernetes API version (e.g. `"1.33"`).                                                                                        | `string`       | `"1.33"`                                                              | no       |
| vpc_name                                            | VPC name (tag `Name`) used to discover VPC.                                                                                    | `string`       | `local.default_vpc_name`                                              | no       |
| subnet_ids                                          | Explicit list of subnet IDs for node groups. If empty, subnets are discovered by tag.                                          | `list(string)` | (discovered)                                                          | no       |
| control_plane_subnet_ids                            | Subnet IDs for the control plane.                                                                                              | `list(string)` | `[]`                                                                  | no       |
| cluster_endpoint_public_access                      | Enable public API endpoint.                                                                                                    | `bool`         | `false`                                                               | no       |
| cluster_endpoint_private_access                     | Enable private API endpoint.                                                                                                   | `bool`         | `true`                                                                | no       |
| cluster_endpoint_public_access_cidrs                | CIDRs allowed to reach the public endpoint.                                                                                    | `list(string)` | `["0.0.0.0/0"]`                                                       | no       |
| cluster_enabled_log_types                           | Control plane log types: `api`, `audit`, `authenticator`, `controllerManager`, `scheduler`.                                    | `list(string)` | `["api", "audit", "authenticator", "controllerManager", "scheduler"]` | no       |
| create_cloudwatch_log_group                         | Create a CloudWatch log group for control plane logs.                                                                          | `bool`         | `true`                                                                | no       |
| cloudwatch_log_group_retention_in_days              | Retention in days for the control plane log group.                                                                             | `number`       | `30`                                                                  | no       |
| cluster_addons                                      | Map of addon name → config (e.g. `coredns = {}`, `vpc-cni = { before_compute = true }`).                                       | `map(any)`     | coredns, kube-proxy, vpc-cni, eks-pod-identity-agent                  | no       |
| enable_cluster_creator_admin_permissions            | Grant cluster creator IAM principal full admin via EKS access entries.                                                         | `bool`         | `true`                                                                | no       |
| access_entries                                      | Map of access entry key → `principal_arn`, `policy_associations`, etc. for explicit cluster access.                            | `map(any)`     | `{}`                                                                  | no       |
| managed_node_groups                                 | Map of node group name → config (`ami_type`, `instance_types`, `capacity_type`, `min_size`, `desired_size`, `max_size`, etc.). | `map(any)`     | `{}`                                                                  | no       |
| cluster_compute_config                              | EKS Auto Mode: set `enabled = true` and `node_pools = ["general-purpose"]` to use managed node pools only.                     | `object`       | `{}`                                                                  | no       |
| tags                                                | Tags applied to cluster and related resources.                                                                                 | `map(string)`  | `local.common_tags`                                                   | no       |
| karpenter                                           | Config for Karpenter AWS resources. Set `create = true` to create IAM roles, SQS queue, pod identity, and discovery tags.      | `object`       | `{}`                                                                  | no       |
| karpenter.create                                    | Enable creation of Karpenter AWS resources (controller IAM role, node IAM role, SQS, subnet/SG tags).                          | `bool`         | `false`                                                               | no       |
| karpenter.vpc_subnet_tag_value                      | Custom value for subnet tag `karpenter.sh/discovery`; use in EC2NodeClass `subnetSelectorTerms`.                               | `string`       | (cluster name)                                                        | no       |
| karpenter.security_group_node_tag_value             | Custom value for node security group tag `karpenter.sh/discovery`; use in EC2NodeClass `securityGroupSelectorTerms`.           | `string`       | (cluster name)                                                        | no       |
| aws_load_balancer_controller                        | Config for subnet tagging so the AWS LB controller can create NLBs/ALBs.                                                       | `object`       | `{}`                                                                  | no       |
| aws_load_balancer_controller.create                 | Enable tagging of subnets for the AWS Load Balancer Controller.                                                                | `bool`         | `false`                                                               | no       |
| aws_load_balancer_controller.public_ingress_create  | Tag public subnets with `kubernetes.io/role/elb`.                                                                              | `bool`         | —                                                                     | no       |
| aws_load_balancer_controller.private_ingress_create | Tag private subnets with `kubernetes.io/role/internal-elb`.                                                                    | `bool`         | —                                                                     | no       |
| aws_load_balancer_controller.public_subnet_name     | Tag filter for public subnets (e.g. `"*-public*"`).                                                                            | `string`       | (from metadata)                                                       | no       |
| aws_load_balancer_controller.private_subnet_name    | Tag filter for private subnets (e.g. `"*-private*"`).                                                                          | `string`       | (from metadata)                                                       | no       |







## ⚠️ Important Notes
- **⚠️ VPC and subnets:** The module discovers VPC and subnets by default using `vpc_name` and subnet tags. Override with `control_plane_subnet_ids` and `subnet_ids` if needed.
- **⚠️ Access:** Use `access_entries` or `enable_cluster_creator_admin_permissions = true` to grant cluster access.
- **⚠️ Karpenter:** This module only creates the AWS prerequisites (IAM, SQS, discovery tags). Install the Karpenter controller (e.g. via Helm) and create NodePool and EC2NodeClass in the cluster yourself.



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