# The repo is public and Actions prints step environments in its logs, so every setting
# the workflow reads is a secret and gets masked.
locals {
  actions_secrets = {
    OCI_DOMAIN_URL    = local.domain_url
    OCI_TENANCY       = var.tenancy_ocid
    OCI_REGION        = var.region
    OCI_COMPARTMENT   = oci_identity_compartment.ocloud.id
    OCI_SUBNET        = oci_core_subnet.ocloud.id
    OCI_CLIENT_ID     = oci_identity_domains_app.github.name
    OCI_CLIENT_SECRET = sensitive(oci_identity_domains_app.github.client_secret)
    SSH_PUBLIC_KEY    = trimspace(file(pathexpand(var.ssh_public_key_path)))
  }
}

resource "github_actions_secret" "capture" {
  for_each = toset(["OCI_DOMAIN_URL", "OCI_TENANCY", "OCI_REGION", "OCI_COMPARTMENT", "OCI_SUBNET", "OCI_CLIENT_ID", "OCI_CLIENT_SECRET", "SSH_PUBLIC_KEY"])

  repository      = var.github_repository
  secret_name     = each.key
  plaintext_value = local.actions_secrets[each.key]

  # Everything the secrets refer to must exist before the workflow can use them.
  depends_on = [
    oci_core_default_route_table.ocloud,
    oci_core_default_security_list.ocloud,
    oci_identity_domains_identity_propagation_trust.github,
    oci_identity_policy.capture,
    oci_limits_quota.a1_cap,
  ]
}
