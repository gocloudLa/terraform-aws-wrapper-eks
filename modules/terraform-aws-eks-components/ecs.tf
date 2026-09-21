resource "aws_cloudwatch_log_group" "this" {
  count = local.create ? 1 : 0

  name              = "/${var.name}/kube-apply"
  retention_in_days = 14
  tags              = var.tags
}

resource "aws_ecs_cluster" "this" {
  count = local.create ? 1 : 0

  name = var.name
  tags = var.tags

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}

resource "aws_iam_role" "ecs_task_execution" {
  count = local.create ? 1 : 0

  name = "${var.name}-ecs-exec"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_task_execution" {
  count = local.create ? 1 : 0

  role       = aws_iam_role.ecs_task_execution[0].name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

resource "aws_iam_role" "ecs_task" {
  count = local.create ? 1 : 0

  name = "${var.name}-ecs-task"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "ecs_task" {
  count = local.create ? 1 : 0

  name = "${var.name}-ecs-task"
  role = aws_iam_role.ecs_task[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Effect = "Allow"
          Action = [
            "s3:PutObject",
            "s3:GetObject",
            "s3:ListBucket"
          ]
          Resource = [
            aws_s3_bucket.this[0].arn,
            "${aws_s3_bucket.this[0].arn}/*"
          ]
        },
        {
          Effect   = "Allow"
          Action   = ["eks:DescribeCluster"]
          Resource = var.cluster_arn != "" ? [var.cluster_arn] : ["*"]
        }
      ]
    )
  })
}

# Key: none (single SG). Created when the caller does not pass security_group_ids.
resource "aws_security_group" "task" {
  count = local.create_task_sg ? 1 : 0

  name        = "${var.name}-task"
  description = "Egress-only SG for the kube-apply Fargate task"
  vpc_id      = var.vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_egress_rule" "task_all" {
  count = local.create_task_sg ? 1 : 0

  security_group_id = aws_security_group.task[0].id
  description       = "Allow all egress for EKS API, S3, ECR, Helm, and GitHub"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "cluster_api" {
  count = local.create_task_sg ? 1 : 0

  security_group_id            = var.cluster_security_group_id
  referenced_security_group_id = aws_security_group.task[0].id
  description                  = "Allow kube-apply Fargate task to reach the EKS API"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
}

# Access entry lives here so the run Lambda cannot start the task before RBAC exists.
resource "aws_eks_access_entry" "task" {
  count = local.create ? 1 : 0

  cluster_name  = var.cluster_name
  principal_arn = aws_iam_role.ecs_task[0].arn
  type          = "STANDARD"
  tags          = var.tags
}

resource "aws_eks_access_policy_association" "task" {
  count = local.create ? 1 : 0

  cluster_name  = aws_eks_access_entry.task[0].cluster_name
  principal_arn = aws_eks_access_entry.task[0].principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# Key: none (single task definition per cluster).
resource "aws_ecs_task_definition" "this" {
  count = local.create ? 1 : 0

  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = tostring(var.container_cpu)
  memory                   = tostring(var.container_memory)
  execution_role_arn       = aws_iam_role.ecs_task_execution[0].arn
  task_role_arn            = aws_iam_role.ecs_task[0].arn
  tags                     = var.tags

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([{
    name      = "kube-apply"
    image     = local.container_image
    essential = true
    command   = ["/usr/local/bin/kube-apply"]
    environment = [
      {
        name  = "PACK_URI"
        value = local.pack_uri
      },
      {
        name  = "CLUSTER_NAME"
        value = var.cluster_name
      },
      {
        name  = "AWS_REGION"
        value = var.region
      }
    ]
    logConfiguration = {
      logDriver = "awslogs"
      options = {
        awslogs-group         = aws_cloudwatch_log_group.this[0].name
        awslogs-region        = var.region
        awslogs-stream-prefix = "kube-apply"
      }
    }
  }])
}
