resource "aws_s3_bucket" "this" {
  count = local.create ? 1 : 0

  bucket        = local.bucket_name
  force_destroy = true
  tags          = var.tags
}

resource "aws_s3_bucket_public_access_block" "this" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.this[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_object" "run_json" {
  count = local.create ? 1 : 0

  bucket       = aws_s3_bucket.this[0].id
  key          = "${local.pack_prefix}/run.json"
  content      = local.run_json
  content_type = "application/json"
  etag         = md5(local.run_json)
  tags         = var.tags
}

# Key: path under current/ (e.g. files/10-lbc/00.yaml). Snapshots live in runs/{apply_id}/.
resource "aws_s3_object" "pack_files" {
  for_each = local.create ? local.pack_files : {}

  bucket  = aws_s3_bucket.this[0].id
  key     = "${local.pack_prefix}/${each.key}"
  content = each.value.content
  etag    = md5(each.value.content)
  tags    = var.tags
}
