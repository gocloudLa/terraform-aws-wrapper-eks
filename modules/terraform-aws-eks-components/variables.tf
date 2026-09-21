variable "create" {
  type        = bool
  description = "Set to create resources."
  default     = true
}

variable "name" {
  type        = string
  description = "Name prefix for ECS, ECR, Image Builder, and S3 resources."
}

variable "tags" {
  type        = map(string)
  description = "Tags applied to created resources."
  default     = {}
}

variable "cluster_name" {
  type        = string
  description = "EKS cluster name to configure kubeconfig against."
}

variable "cluster_arn" {
  type        = string
  description = "EKS cluster ARN for IAM and access entry."
  default     = ""
}

variable "region" {
  type        = string
  description = "AWS region of the cluster and Fargate task."
}

variable "vpc_id" {
  type        = string
  description = "VPC ID for the Fargate task and Image Builder."
}

variable "subnet_ids" {
  type        = list(string)
  description = "Private subnet IDs for the Fargate task and Image Builder."
}

variable "security_group_ids" {
  type        = list(string)
  description = "Security group IDs for the Fargate task ENI. Empty creates an egress-all SG."
  default     = []
}

variable "cluster_security_group_id" {
  type        = string
  description = "EKS cluster security group to allow 443 from the task ENI."
  default     = ""
}

variable "components" {
  type        = any
  description = "Map of groups to steps (kubectl, kustomize, helm)."
  default     = {}
}

variable "container_cpu" {
  type        = number
  description = "Fargate CPU units (256, 512, 1024, 2048, 4096)."
  default     = 1024
}

variable "container_memory" {
  type        = number
  description = "Fargate memory in MiB."
  default     = 2048
}

variable "pod_identity_role_arns" {
  type        = list(string)
  description = "Pod Identity role ARNs for this cluster; the apply task waits until they exist."
  default     = []
}
