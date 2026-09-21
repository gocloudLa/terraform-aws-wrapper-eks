data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_subnet" "image_builder" {
  count = local.create ? 1 : 0

  id = var.subnet_ids[0]
}
