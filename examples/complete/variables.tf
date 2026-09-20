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
  type        = any
  description = "Default values merged into each entry of eks_parameters."
  default     = {}
}

variable "eks_parameters" {
  type        = any
  description = "Map of EKS clusters to create."
  default     = {}
}