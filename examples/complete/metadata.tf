locals {

  metadata = {
    aws_region     = "us-east-2"
    environment    = "Laboratory"
    project        = "Example"
    public_domain  = "democorp.cloud"
    private_domain = "democorp"

    key = {
      company = "dmc"
      region  = "use2"
      env     = "lab"
      project = "example"
      layer   = "project"
    }
  }

  common_name_prefix = join("-", [
    local.metadata.key.company,
    local.metadata.key.env
  ])

  common_name = join("-", [
    local.common_name_prefix,
    local.metadata.key.project
  ])
}
