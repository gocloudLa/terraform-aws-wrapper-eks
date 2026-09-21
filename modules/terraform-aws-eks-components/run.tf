module "lambda_run" {
  source  = "terraform-aws-modules/lambda/aws"
  version = "8.8.0"

  count = local.create ? 1 : 0

  function_name = "${var.name}-run"
  description   = "Run the kube-apply Fargate task and wait for the exit code."
  handler       = "index.lambda_handler"
  runtime       = "python3.12"
  timeout       = 900
  memory_size   = 256

  maximum_retry_attempts = 0
  source_path            = "${path.module}/lambda/run"

  attach_policy_statements = true
  policy_statements = {
    ecs = {
      effect = "Allow"
      actions = [
        "ecs:RunTask",
        "ecs:DescribeTasks",
        "ecs:StopTask",
      ]
      resources = ["*"]
    }
    pass_role = {
      effect  = "Allow"
      actions = ["iam:PassRole"]
      resources = [
        aws_iam_role.ecs_task[0].arn,
        aws_iam_role.ecs_task_execution[0].arn,
      ]
    }
  }

  cloudwatch_logs_retention_in_days = 14
  tags                              = var.tags
}

resource "aws_lambda_invocation" "run" {
  count = local.create ? 1 : 0

  function_name   = module.lambda_run[0].lambda_function_name
  lifecycle_scope = "CREATE_ONLY"

  input = jsonencode({
    cluster         = aws_ecs_cluster.this[0].name
    task_definition = aws_ecs_task_definition.this[0].arn
    image_arn       = local.image_arn
    subnets         = var.subnet_ids
    security_groups = local.task_security_group_ids
    poll_seconds    = 15
  })

  triggers = {
    pack_json     = aws_s3_object.run_json[0].etag
    pack_files    = md5(jsonencode({ for k, v in aws_s3_object.pack_files : k => v.etag }))
    task_def      = aws_ecs_task_definition.this[0].arn
    image_arn     = local.image_arn
    access_policy = aws_eks_access_policy_association.task[0].id
    cluster_sg    = try(aws_vpc_security_group_ingress_rule.cluster_api[0].id, "none")
    pod_identity  = md5(jsonencode(var.pod_identity_role_arns))
  }
}
