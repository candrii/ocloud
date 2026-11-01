resource "oci_identity_compartment" "ocloud" {
  compartment_id = var.tenancy_ocid
  name           = local.name
  description    = "A1 capture workflow"
}

# The workflow launches instances in this compartment; the quota keeps them within Always Free.
resource "oci_limits_quota" "a1_cap" {
  compartment_id = var.tenancy_ocid
  name           = "${local.name}-a1-cap"
  description    = "Keep A1 within Always Free"
  statements = [
    "set compute-core quota standard-a1-core-regional-count to 4 in compartment ${oci_identity_compartment.ocloud.name}",
    "set compute-memory quota standard-a1-memory-regional-count to 24 in compartment ${oci_identity_compartment.ocloud.name}",
  ]
}
