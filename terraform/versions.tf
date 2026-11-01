terraform {
  required_version = ">= 1.11"

  # The state holds the app's client secret, so it lives outside the repo and OneDrive.
  # Its path is passed to terraform init; see the README.
  backend "local" {}

  required_providers {
    oci = {
      source  = "oracle/oci"
      version = "~> 9.11"
    }
    github = {
      source  = "integrations/github"
      version = "~> 6.13"
    }
  }
}

provider "oci" {
  auth                = "SecurityToken"
  config_file_profile = "DEFAULT"
  region              = var.region
}

# Authenticates with the GITHUB_TOKEN environment variable.
provider "github" {
  owner = var.github_owner
}
