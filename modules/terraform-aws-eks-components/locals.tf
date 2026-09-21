locals {
  create         = var.create
  create_task_sg = var.create && length(var.security_group_ids) == 0
  bucket_name    = lower(substr("${var.name}-${data.aws_caller_identity.current.account_id}", 0, 63))

  # Caller groups → steps. Key: "${group}/${step}"
  expanded_steps = flatten([
    for group_key, steps in try(var.components, {}) : [
      for step_key, step in try(steps, {}) : {
        id               = "${group_key}/${step_key}"
        kind             = step.kind
        source           = try(step.source, null)
        url              = try(step.url, null)
        path             = try(step.path, null)
        yaml             = try(step.yaml, null)
        repository       = try(step.repository, null)
        chart            = try(step.chart, null)
        version          = try(step.version, null)
        release          = try(step.release, null)
        namespace        = try(step.namespace, null)
        create_namespace = try(step.create_namespace, false)
        values           = try(step.values, null)
        values_file      = try(step.values_file, null)
        flags            = try(step.flags, [])
      }
    ]
  ])

  # Pack objects. Key: path under current/
  pack_files_tmp = [
    for step in local.expanded_steps : concat(
      step.kind == "kubectl" && step.source == "inline" && step.yaml != null ? [{
        "files/${step.id}.yaml" = { content = step.yaml }
      }] : [],
      step.kind == "kubectl" && step.source == "file" && step.path != null ? [{
        "files/${step.id}/${basename(step.path)}" = { content = file(step.path) }
      }] : [],
      contains(["kustomize", "helm"], step.kind) && step.source == "file" && step.path != null ? [
        for f in fileset(step.path, "**") : {
          "files/${step.id}/${f}" = { content = file("${step.path}/${f}") }
        }
      ] : [],
      step.kind == "helm" && step.values != null ? [{
        "files/${step.id}/values.yaml" = { content = step.values }
      }] : [],
      step.kind == "helm" && step.values == null && step.values_file != null ? [{
        "files/${step.id}/values.yaml" = { content = file(step.values_file) }
      }] : [],
    )
  ]

  pack_files = merge(flatten(local.pack_files_tmp)...)

  run_spec = {
    cluster_name = var.cluster_name
    region       = var.region
    steps = [
      for step in local.expanded_steps : {
        id     = step.id
        kind   = step.kind
        source = step.source
        url    = step.url
        path = (
          step.kind == "kubectl" && step.source == "inline" ? "files/${step.id}.yaml" :
          step.kind == "kubectl" && step.source == "file" ? "files/${step.id}/${basename(step.path)}" :
          contains(["kustomize", "helm"], step.kind) && step.source == "file" ? "files/${step.id}" :
          null
        )
        repository       = step.repository
        chart            = step.chart
        version          = step.version
        release          = step.release
        namespace        = step.namespace
        create_namespace = step.create_namespace
        values_file      = step.kind == "helm" && (step.values != null || step.values_file != null) ? "files/${step.id}/values.yaml" : null
        flags            = step.flags
      }
    ]
  }

  apply_id = substr(md5(jsonencode({ run = local.run_spec, files = { for k, v in local.pack_files : k => md5(v.content) } })), 0, 16)
  run_json = jsonencode(merge(local.run_spec, { apply_id = local.apply_id }))
  # Terraform always writes the live pack here. The container snapshots to runs/{apply_id}/.
  pack_prefix = "current"
  pack_uri    = "s3://${local.bucket_name}/${local.pack_prefix}"

  task_security_group_ids = length(var.security_group_ids) > 0 ? var.security_group_ids : (
    local.create_task_sg ? [aws_security_group.task[0].id] : []
  )
}

# output "debug_expanded_steps" {
#   value = local.expanded_steps
# }
#
# output "debug_pack_files" {
#   value = keys(local.pack_files)
# }
#
# output "debug_run_spec" {
#   value = local.run_spec
# }
