locals {
  service_user = "ocloud-capture"
  domain_url   = trimsuffix(data.oci_identity_domains.default.domains[0].url, ":443")
}

data "oci_identity_domains" "default" {
  compartment_id = var.tenancy_ocid
  display_name   = "Default"
}

# The identity GitHub runs act as. It has no password or API keys.
resource "oci_identity_domains_user" "capture" {
  idcs_endpoint = local.domain_url
  schemas = [
    "urn:ietf:params:scim:schemas:core:2.0:User",
    "urn:ietf:params:scim:schemas:oracle:idcs:extension:user:User",
  ]
  user_name = local.service_user

  urnietfparamsscimschemasoracleidcsextensionuser_user {
    service_user = true
  }

  # OCI appends its own schemas to identity resources.
  lifecycle {
    ignore_changes = [schemas]
  }
}

resource "oci_identity_domains_group" "capture" {
  idcs_endpoint = local.domain_url
  schemas       = ["urn:ietf:params:scim:schemas:core:2.0:Group"]
  display_name  = local.service_user

  # Members are only returned when requested, and would otherwise show as drift.
  attribute_sets = ["all"]

  members {
    type  = "User"
    value = oci_identity_domains_user.capture.id
  }

  lifecycle {
    ignore_changes = [schemas]
  }
}

resource "oci_identity_policy" "capture" {
  compartment_id = var.tenancy_ocid
  name           = "${local.name}-capture"
  description    = "A1 capture workflow"
  statements = [
    "Allow group 'Default'/'${oci_identity_domains_group.capture.display_name}' to manage instance-family in compartment ${oci_identity_compartment.ocloud.name}",
    "Allow group 'Default'/'${oci_identity_domains_group.capture.display_name}' to use volume-family in compartment ${oci_identity_compartment.ocloud.name}",
    "Allow group 'Default'/'${oci_identity_domains_group.capture.display_name}' to use virtual-network-family in compartment ${oci_identity_compartment.ocloud.name}",
  ]
}

# The client whose credentials the workflow presents to the token exchange endpoint.
resource "oci_identity_domains_app" "github" {
  idcs_endpoint   = local.domain_url
  schemas         = ["urn:ietf:params:scim:schemas:oracle:idcs:App"]
  display_name    = "${local.name}-github"
  active          = true
  is_oauth_client = true
  client_type     = "confidential"
  allowed_grants  = ["client_credentials"]

  based_on_template {
    value = "CustomWebAppTemplateId"
  }

  lifecycle {
    ignore_changes = [schemas]
  }
}

# Only tokens from this repository's main branch map to the service user.
resource "oci_identity_domains_identity_propagation_trust" "github" {
  idcs_endpoint       = local.domain_url
  schemas             = ["urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust"]
  name                = "${local.name}-github"
  type                = "JWT"
  active              = true
  issuer              = local.github_issuer
  public_key_endpoint = "${local.github_issuer}/.well-known/jwks"
  oauth_clients       = [oci_identity_domains_app.github.name]
  client_claim_name   = "aud"
  client_claim_values = [local.github_audience]
  subject_claim_name  = "sub"
  subject_type        = "User"
  allow_impersonation = true

  # The rule is only returned when requested, and would otherwise show as drift.
  attribute_sets = ["all"]

  impersonation_service_users {
    rule  = "sub eq ${local.github_subject}"
    value = oci_identity_domains_user.capture.id
  }

  lifecycle {
    ignore_changes = [schemas]
  }
}
