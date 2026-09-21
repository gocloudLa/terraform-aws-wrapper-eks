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

output "summary" {
  description = "Waiter result: ok, running (lambda deadline), or apply error if the task exited non-zero."
  value       = try(jsondecode(aws_lambda_invocation.run[0].result), {})
}

output "task_arn" {
  description = "ARN of the last ECS task started by the waiter."
  value       = try(jsondecode(aws_lambda_invocation.run[0].result).task_arn, null)
}

output "log_group_name" {
  description = "CloudWatch log group for the kube-apply task."
  value       = try(aws_cloudwatch_log_group.this[0].name, null)
}

output "task_role_arn" {
  description = "IAM role ARN used by the Fargate task (EKS access entry principal)."
  value       = try(aws_iam_role.ecs_task[0].arn, null)
}

output "security_group_id" {
  description = "Security group ID attached to the Fargate task ENI."
  value       = try(local.task_security_group_ids[0], null)
}
