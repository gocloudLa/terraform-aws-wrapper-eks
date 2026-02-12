/*----------------------------------------------------------------------*/
/* Common |                                                             */
/*----------------------------------------------------------------------*/

# variable "metadata" {
#   type = any
# }

/*----------------------------------------------------------------------*/
/* EKS | Variable Definition                                            */
/*----------------------------------------------------------------------*/

variable "eks_defaults" {
  description = "Map of default values which will be used for each eks cluster."
  type        = any
  default     = {}
}

variable "eks_parameters" {
  description = "Maps of eks clusters to create a wrapper from. Values are passed through to the module."
  type        = any
  default     = {}
}