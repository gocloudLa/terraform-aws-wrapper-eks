/*----------------------------------------------------------------------*/
/* Locals Definition                                                    */
/*----------------------------------------------------------------------*/

locals {

  # Default Subnet Name
  default_private_subnet_name = "${local.common_name_prefix}-private*"
  default_public_subnet_name  = "${local.common_name_prefix}-public*"

}
