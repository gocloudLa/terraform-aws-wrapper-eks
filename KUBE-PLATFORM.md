# EKS components

Installs cluster software (Helm / kubectl / Kustomize) onto an EKS cluster created by this wrapper. Terraform uses only the **AWS** provider. Workload apps stay out of this module.

Caller key: `eks_parameters["<cluster>"].components`.

Child module: `modules/terraform-aws-eks-components` (one instance per cluster that has a non-empty `components` map).

---

## Caller shape

Map of **groups** → **steps**. Order is lexicographic (group key, then step key). Prefix IDs (`10-lbc`, `00`). HCL map order is ignored.

| `kind` | Fields |
|--------|--------|
| `kubectl` | `source` = `url` \| `file` \| `inline`; `url` / `path` / `yaml`; optional `flags` |
| `kustomize` | `source` = `file` \| `url`; `path` / `url`; optional `flags` |
| `helm` | `source` = `repo` \| `file`; `repository`, `chart`, `version`, `release`, `namespace`, `create_namespace`, `values` or `values_file` / `path`; optional `flags` |

Example below hits every `kind` / `source` used in v1 (use it as the feature test).

```hcl
eks_parameters = {
  "00" = {
    components = {
      "10-lbc" = {
        "00" = {
          kind   = "kubectl"
          source = "url"
          url    = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-install.yaml"
          flags  = ["--server-side=true"]
        }
        "01" = {
          kind             = "helm"
          source           = "repo"
          repository       = "https://aws.github.io/eks-charts"
          chart            = "aws-load-balancer-controller"
          version          = "3.5.0"
          release          = "aws-load-balancer-controller"
          namespace        = "kube-system"
          create_namespace = false
          flags            = ["--wait", "--timeout", "20m"]
        }
        "02" = {
          kind   = "kubectl"
          source = "inline"
          yaml   = <<-YAML
            # Caller-owned Gateway / LoadBalancerConfiguration (ACM, hosts, etc.)
            apiVersion: gateway.networking.k8s.io/v1
            kind: GatewayClass
            metadata:
              name: aws-alb
            spec:
              controllerName: gateway.k8s.aws/alb
          YAML
        }
      }

      "20-file" = {
        "00" = {
          kind   = "kubectl"
          source = "file"
          path   = "${path.module}/k8s/gateway.yaml"
        }
      }

      "25-kustomize" = {
        "00" = {
          kind   = "kustomize"
          source = "file"
          path   = "${path.module}/kustomize/overlays/lab"
        }
      }

      "35-wordpress" = {
        "00" = {
          kind             = "helm"
          source           = "repo"
          repository       = "oci://registry-1.docker.io/bitnamicharts"
          chart            = "wordpress"
          version          = "24.2.3"
          release          = "wordpress"
          namespace        = "wordpress"
          create_namespace = true
          values           = <<-YAML
            service:
              type: ClusterIP
            persistence:
              enabled: false
            mariadb:
              primary:
                persistence:
                  enabled: false
          YAML
        }
      }

      "40-url" = {
        "00" = {
          kind   = "kubectl"
          source = "url"
          url    = "https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.6.0/standard-install.yaml"
          flags  = ["--server-side=true"]
        }
      }

      "45-kustomize-url" = {
        "00" = {
          kind   = "kustomize"
          source = "url"
          url    = "https://github.com/kubernetes-sigs/kustomize//examples/helloWorld?ref=kustomize/v5.4.3"
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
            ---
            apiVersion: v1
            kind: Namespace
            metadata:
              name: app-b
          YAML
        }
      }

      "55-helm-file" = {
        "00" = {
          kind      = "helm"
          source    = "file"
          path      = "${path.module}/charts/demo"
          release   = "demo"
          namespace = "demo"
          create_namespace = true
        }
      }
    }
  }
}
```

The public Gateway is always a later `kubectl` step on the invocador. IAM (Pod Identity, subnet tags) stays on existing wrapper keys; LBC Helm uses SA `kube-system/aws-load-balancer-controller`.

---

## Module layout

Reduced RDS dump-create: **no Lambda, no Batch, no EventBridge**. Image Builder + ECS Fargate + S3 pack + sync wait.

```
modules/terraform-aws-eks-components/
  versions.tf
  variables.tf
  locals.tf
  data_sources.tf
  image_builder.tf      # ECR + Image Builder, embeds kube-apply.sh
  ecs.tf                # cluster, task def, roles, log group, SG if needed
  s3.tf                 # bucket + pack objects
  run.tf                # terraform_data: ecs run-task + wait + exit code
  outputs.tf
  container/
    README.md
    scripts/kube-apply.sh
    install.sh
    Dockerfile
  lambda/run/index.py
```

Wrapper: `_components.tf` — `for_each` clusters with `components`; pass `cluster_name`, `cluster_arn`, `vpc_id`, `subnet_ids` (private), `region`, `components` map; `depends_on = [module.eks]`. Access entry for the task role on that cluster.

### Variables (module)

- `create`, `name`, `tags`
- `cluster_name`, `region`, `vpc_id`, `subnet_ids`, `security_group_ids` (task ENI)
- `components` (the group→step map)
- `container_cpu` / `container_memory` (Fargate, e.g. 1024 / 2048)

### Outputs

- `summary` — parsed `result.json` after a successful wait (empty/error if apply failed)
- `task_arn`, `log_group_name`

---

## Runtime

1. Flatten `components` (sort group, then step) → ordered list.
2. Upload pack to `s3://…/current/` (`run.json` + `files/`). The task definition `PACK_URI` is this fixed prefix.
3. Lambda RunTask always uses that task def (no per-apply URI).
4. Container copies the pack to `s3://…/runs/{apply_id}/`, then applies.
5. Wait for **container exit code** (source of truth). Task also writes `result.json` (audit + `output.summary`). CloudWatch for logs.

`kube-apply.sh` (baked by Image Builder, **not** downloaded from S3): download `current/`, snapshot to `runs/{apply_id}/`, `aws eks update-kubeconfig`, walk steps in order, stop on first error.

| kind | Action |
|------|--------|
| `kubectl` url | `kubectl apply [flags] -f URL` |
| `kubectl` file / inline | `kubectl apply [flags] -f` pack file |
| `kustomize` | `kubectl apply [flags] -k` |
| `helm` | `helm upgrade --install [flags]` |

Image: Amazon Linux + helm, kubectl, aws cli (kubectl `-k` is enough for Kustomize). Same Image Builder embed pattern as RDS dump.

There is **no** `aws_ecs_run_task` resource that blocks until the container exits. HashiCorp never added it (RunTask is not a CRUD object). Closest official piece is **`data.aws_ecs_task_execution`**: it calls RunTask on **every read**, so a `terraform plan` can start a task, and it does **not** wait for exit code. Do not use it here.

Waiter is `terraform_data` (apply only) with `local-exec` / AWS CLI on the apply runner — same machine that already talks to AWS, never to kube:

```hcl
resource "terraform_data" "run" {
  triggers_replace = [aws_s3_object.pack.etag, aws_ecs_task_definition.this.arn]

  provisioner "local-exec" {
    interpreter = ["/bin/bash", "-c"]
    command     = <<-EOT
      TASK=$(aws ecs run-task --cluster ${aws_ecs_cluster.this.name} ... --query 'tasks[0].taskArn' --output text)
      aws ecs wait tasks-stopped --cluster ${aws_ecs_cluster.this.name} --tasks "$TASK"
      CODE=$(aws ecs describe-tasks --cluster ${aws_ecs_cluster.this.name} --tasks "$TASK" \
        --query 'tasks[0].containers[0].exitCode' --output text)
      test "$CODE" = "0"
    EOT
  }
}
```

---

## IAM / network

- Task in **private** subnets; egress to EKS API, S3, ECR, Helm/GitHub (NAT or endpoints).
- **Task role:** EKS access entry (`system:masters` or a tighter group is fine for v1); `s3:Get/Put` on the pack prefix; `eks:DescribeCluster`.
- **Execution role:** ECR pull, CloudWatch.
- Apply identity: ECS run/describe/wait, S3 put, Image Builder; **no** kubeconfig.

---

## Implement (v1)

- ECS Fargate only. Skip Batch, Lambda, CodeBuild, Helmfile, GitOps engine.
- Apply-only (no helm uninstall on destroy).
- No secrets in the pack; keep passwords out of `values` / inline YAML.
- `terraform plan` does not show Kubernetes diffs.
- Needs schedulable nodes before Helm pods run; `depends_on` the EKS module (node groups / Karpenter AWS resources).
