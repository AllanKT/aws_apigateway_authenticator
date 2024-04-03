variable "aws_region" {
  description = "AWS region"
  type    = string
  default = "sa-east-1"
}

variable "aws_access_key" {
  type    = string
  default = ""
}

variable "aws_secret_key" {
  type    = string
  default = ""
}

variable "aws_session_token" {
  type    = string
  default = ""
}
