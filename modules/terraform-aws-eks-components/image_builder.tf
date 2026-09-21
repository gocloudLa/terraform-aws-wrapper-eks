################################################################################
# kube-apply image — Dockerfile + install.sh + scripts/kube-apply.sh
################################################################################

locals {
  parent_image = "public.ecr.aws/amazonlinux/amazonlinux:2023"
  image_hash = parseint(substr(md5(join("|", [
    file("${path.module}/container/Dockerfile"),
    file("${path.module}/container/install.sh"),
    file("${path.module}/container/scripts/kube-apply.sh"),
  ])), 0, 6), 16)
  image_version = "1.0.${local.image_hash}"
  image_component = yamlencode({
    schemaVersion = "1.0"
    phases = [{
      name = "build"
      steps = [{
        name   = "Install"
        action = "ExecuteBash"
        inputs = {
          commands = [join("\n", [
            file("${path.module}/container/install.sh"),
            "echo '${base64encode(file("${path.module}/container/scripts/kube-apply.sh"))}' | base64 -d > /usr/local/bin/kube-apply",
            "chmod 0755 /usr/local/bin/kube-apply",
          ])]
        }
      }]
    }]
  })
  container_image = local.create ? "${aws_ecr_repository.this[0].repository_url}:latest" : ""
  # Token for the apply waiter. Referencing the image resource ARN (not :latest)
  # makes aws_lambda_invocation wait until Image Builder has pushed the tag.
  image_arn = local.create ? aws_imagebuilder_image.this[0].arn : ""
}

resource "aws_security_group" "image_builder" {
  count = local.create ? 1 : 0

  name        = "${var.name}-imagebuilder"
  description = "Egress-only SG for the Image Builder build instance"
  vpc_id      = data.aws_subnet.image_builder[0].vpc_id
  tags        = var.tags
}

resource "aws_vpc_security_group_egress_rule" "image_builder_all" {
  count = local.create ? 1 : 0

  security_group_id = aws_security_group.image_builder[0].id
  description       = "Allow all egress for package managers and AWS API calls"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_ecr_repository" "this" {
  count = local.create ? 1 : 0

  name                 = var.name
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = var.tags
}

resource "aws_iam_role" "imagebuilder" {
  count = local.create ? 1 : 0

  name = "${var.name}-imagebuilder"
  tags = var.tags

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "imagebuilder" {
  count = local.create ? 1 : 0

  role       = aws_iam_role.imagebuilder[0].name
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder"
}

resource "aws_iam_role_policy_attachment" "imagebuilder_ssm" {
  count = local.create ? 1 : 0

  role       = aws_iam_role.imagebuilder[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "imagebuilder_ecr_container" {
  count = local.create ? 1 : 0

  role       = aws_iam_role.imagebuilder[0].name
  policy_arn = "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds"
}

resource "aws_iam_role_policy" "imagebuilder" {
  count = local.create ? 1 : 0

  name = "${var.name}-imagebuilder"
  role = aws_iam_role.imagebuilder[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:CompleteLayerUpload",
          "ecr:InitiateLayerUpload",
          "ecr:PutImage",
          "ecr:UploadLayerPart",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr-public:GetAuthorizationToken",
          "ecr-public:BatchCheckLayerAvailability",
          "ecr-public:GetDownloadUrlForLayer",
          "ecr-public:BatchGetImage"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_instance_profile" "imagebuilder" {
  count = local.create ? 1 : 0

  name = "${var.name}-imagebuilder"
  role = aws_iam_role.imagebuilder[0].name
  tags = var.tags
}

resource "aws_imagebuilder_component" "this" {
  count = local.create ? 1 : 0

  name     = var.name
  version  = local.image_version
  platform = "Linux"
  data     = local.image_component
  tags     = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_imagebuilder_container_recipe" "this" {
  count = local.create ? 1 : 0

  name              = var.name
  version           = local.image_version
  container_type    = "DOCKER"
  parent_image      = local.parent_image
  platform_override = "Linux"
  tags              = var.tags

  component {
    component_arn = aws_imagebuilder_component.this[0].arn
  }

  target_repository {
    repository_name = aws_ecr_repository.this[0].name
    service         = "ECR"
  }

  dockerfile_template_data = file("${path.module}/container/Dockerfile")

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_imagebuilder_infrastructure_configuration" "this" {
  count = local.create ? 1 : 0

  name                          = var.name
  instance_types                = ["c5.large"]
  instance_profile_name         = aws_iam_instance_profile.imagebuilder[0].name
  subnet_id                     = var.subnet_ids[0]
  security_group_ids            = [aws_security_group.image_builder[0].id]
  terminate_instance_on_failure = true
  tags                          = var.tags
}

resource "aws_imagebuilder_distribution_configuration" "this" {
  count = local.create ? 1 : 0

  name = var.name
  tags = var.tags

  distribution {
    region = var.region

    container_distribution_configuration {
      container_tags = ["latest"]

      target_repository {
        service         = "ECR"
        repository_name = aws_ecr_repository.this[0].name
      }
    }
  }
}

resource "aws_imagebuilder_image_pipeline" "this" {
  count = local.create ? 1 : 0

  name                             = var.name
  status                           = "ENABLED"
  container_recipe_arn             = aws_imagebuilder_container_recipe.this[0].arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.this[0].arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.this[0].arn
  tags                             = var.tags

  image_tests_configuration {
    image_tests_enabled = false
  }
}

resource "aws_imagebuilder_image" "this" {
  count = local.create ? 1 : 0

  container_recipe_arn             = aws_imagebuilder_container_recipe.this[0].arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.this[0].arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.this[0].arn

  image_tests_configuration {
    image_tests_enabled = false
  }

  # Instance profile does not reference managed-policy attachments; Image Builder
  # must not launch until those attachments exist.
  depends_on = [
    aws_iam_role_policy_attachment.imagebuilder,
    aws_iam_role_policy_attachment.imagebuilder_ssm,
    aws_iam_role_policy_attachment.imagebuilder_ecr_container,
    aws_iam_role_policy.imagebuilder,
  ]

  lifecycle {
    replace_triggered_by = [
      aws_imagebuilder_container_recipe.this[0],
    ]
  }
}
