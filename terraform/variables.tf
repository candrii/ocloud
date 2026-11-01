variable "tenancy_ocid" {
  type = string
}

variable "region" {
  type    = string
  default = "us-chicago-1"
}

variable "github_owner" {
  type    = string
  default = "candrii"
}

variable "github_repository" {
  type    = string
  default = "ocloud"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/ocloud_ed25519.pub"
}

locals {
  name         = "ocloud"
  service_user = "ocloud-capture"
}
