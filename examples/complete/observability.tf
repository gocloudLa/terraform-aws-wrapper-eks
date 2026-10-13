# Thanos (metricas) y Loki (logs). El account id mantiene los nombres globalmente unicos.
# La retencion la aplican Thanos compact y el compactor de Loki; el lifecycle solo abarata el almacenamiento.
module "observability_bucket" {
  source  = "terraform-aws-modules/s3-bucket/aws"
  version = "~> 5.17"

  for_each = toset(["thanos", "loki"])

  bucket        = "${local.common_name}-ex-observability-${each.key}-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true

  server_side_encryption_configuration = {
    rule = {
      apply_server_side_encryption_by_default = { sse_algorithm = "AES256" }
    }
  }

  lifecycle_rule = [{
    id      = "tiering"
    enabled = true
    filter  = {}

    transition = [{
      days          = 30
      storage_class = "INTELLIGENT_TIERING"
    }]

    abort_incomplete_multipart_upload_days = 7
  }]
}
