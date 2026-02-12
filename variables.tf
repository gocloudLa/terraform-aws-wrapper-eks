/*----------------------------------------------------------------------*/
/* Common |                                                             */
/*----------------------------------------------------------------------*/

variable "metadata" {
  type = any
}

/*----------------------------------------------------------------------*/
/* EKS | Variable Definition                                            */
/*----------------------------------------------------------------------*/

variable "eks_parameters" {
  type        = any
  description = "EKS parameteres"
  default     = {}
}

variable "eks_defaults" {
  type        = any
  description = "EKS default parameteres"
  default     = {}
}
