resource "oci_core_vcn" "ocloud" {
  compartment_id = oci_identity_compartment.ocloud.id
  display_name   = local.name
  cidr_block     = "10.0.0.0/16"
  dns_label      = local.name
}

resource "oci_core_internet_gateway" "ocloud" {
  compartment_id = oci_identity_compartment.ocloud.id
  vcn_id         = oci_core_vcn.ocloud.id
  display_name   = local.name
  enabled        = true
}

resource "oci_core_default_route_table" "ocloud" {
  manage_default_resource_id = oci_core_vcn.ocloud.default_route_table_id

  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id = oci_core_internet_gateway.ocloud.id
  }
}

resource "oci_core_default_security_list" "ocloud" {
  manage_default_resource_id = oci_core_vcn.ocloud.default_security_list_id

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
  }

  ingress_security_rules {
    protocol = "6"
    source   = "0.0.0.0/0"

    tcp_options {
      min = 22
      max = 22
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = "0.0.0.0/0"

    icmp_options {
      type = 3
      code = 4
    }
  }

  ingress_security_rules {
    protocol = "1"
    source   = oci_core_vcn.ocloud.cidr_block

    icmp_options {
      type = 3
    }
  }
}

# Regional, so the workflow can try every availability domain.
resource "oci_core_subnet" "ocloud" {
  compartment_id = oci_identity_compartment.ocloud.id
  vcn_id         = oci_core_vcn.ocloud.id
  display_name   = local.name
  cidr_block     = "10.0.0.0/24"
  dns_label      = "main"
}
