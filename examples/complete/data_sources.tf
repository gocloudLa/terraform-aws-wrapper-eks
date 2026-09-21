data "aws_acm_certificate" "this" {
  domain      = local.zone_public
  types       = ["AMAZON_ISSUED"]
  most_recent = true
}

data "aws_vpc" "this" {
  filter {
    name   = "tag:Name"
    values = [local.common_name_prefix]
  }
}
