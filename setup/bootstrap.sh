#!/usr/bin/env bash
# One-time OCI and GitHub setup for the capture workflow. Safe to re-run: anything that
# already exists is reused. Requires an admin session (oci session authenticate), gh
# logged in, and an SSH public key.
#
#   OCI_BIN=oci GH_BIN=gh SSH_KEY=~/.ssh/ocloud_ed25519.pub setup/bootstrap.sh
set -euo pipefail
export MSYS_NO_PATHCONV=1

repo=candrii/ocloud
region=us-chicago-1
domain_url=https://idcs-7643571319b8489bb4d12a0f20961d61.identity.oraclecloud.com
name=ocloud
service_user=ocloud-capture
github_subject="repo:$repo:ref:refs/heads/main"
github_issuer=https://token.actions.githubusercontent.com

OCI_BIN=${OCI_BIN:-oci}
GH_BIN=${GH_BIN:-gh}
SSH_KEY=${SSH_KEY:-$HOME/.ssh/ocloud_ed25519.pub}

oci() { "$OCI_BIN" --profile DEFAULT --auth security_token "$@" | tr -d '\r'; }
# Prints a value, or fails with the name of what is missing.
need() { [ -n "$2" ] && [ "$2" != "null" ] || { echo "Could not get $1" >&2; exit 1; }; echo "$2"; }
scim_find() { # <resource> <filter>
  oci raw-request --http-method GET --target-uri "$domain_url/admin/v1/$1?filter=$2" \
    --query 'data.Resources[0].[id,name || `""`] | join(`" "`, @)' --raw-output 2>/dev/null || true
}
scim_post() { # <resource> <body> <jmespath>
  oci raw-request --http-method POST --target-uri "$domain_url/admin/v1/$1" --request-body "$2" \
    --query "$3" --raw-output
}

tenancy=$(sed -n 's/^tenancy=//p' "$HOME/.oci/config" | tr -d '\r')

echo "Compartment"
compartment=$(oci iam compartment list -c "$tenancy" --name "$name" --lifecycle-state ACTIVE --query 'data[0].id' --raw-output)
if [ -z "$compartment" ]; then
  compartment=$(oci iam compartment create -c "$tenancy" --name "$name" \
    --description "A1 capture workflow" --wait-for-state ACTIVE --query 'data.id' --raw-output)
fi
need compartment "$compartment" >/dev/null

echo "Network"
vcn=$(oci network vcn list -c "$compartment" --display-name "$name" --lifecycle-state AVAILABLE --query 'data[0].id' --raw-output)
if [ -z "$vcn" ]; then
  vcn=$(oci network vcn create -c "$compartment" --display-name "$name" --cidr-block 10.0.0.0/16 \
    --dns-label "$name" --wait-for-state AVAILABLE --query 'data.id' --raw-output)
fi
igw=$(oci network internet-gateway list -c "$compartment" --vcn-id "$vcn" --query 'data[0].id' --raw-output)
if [ -z "$igw" ]; then
  igw=$(oci network internet-gateway create -c "$compartment" --vcn-id "$vcn" --display-name "$name" \
    --is-enabled true --wait-for-state AVAILABLE --query 'data.id' --raw-output)
fi
route_table=$(oci network vcn get --vcn-id "$vcn" --query 'data."default-route-table-id"' --raw-output)
oci network route-table update --rt-id "$route_table" --force --wait-for-state AVAILABLE \
  --route-rules "[{\"destination\":\"0.0.0.0/0\",\"destinationType\":\"CIDR_BLOCK\",\"networkEntityId\":\"$igw\"}]" >/dev/null
subnet=$(oci network subnet list -c "$compartment" --vcn-id "$vcn" --query 'data[0].id' --raw-output)
if [ -z "$subnet" ]; then
  subnet=$(oci network subnet create -c "$compartment" --vcn-id "$vcn" --display-name "$name" \
    --cidr-block 10.0.0.0/24 --dns-label main --wait-for-state AVAILABLE --query 'data.id' --raw-output)
fi

echo "Cost cap and policy"
if [ -z "$(oci limits quota list -c "$tenancy" --name "$name-a1-cap" --query 'data[0].id' --raw-output)" ]; then
  oci limits quota create -c "$tenancy" --name "$name-a1-cap" --description "Keep A1 within Always Free" \
    --statements "[\"set compute-core quota standard-a1-core-regional-count to 4 in compartment $name\",\"set compute-memory quota standard-a1-memory-regional-count to 24 in compartment $name\"]" >/dev/null
fi
if [ -z "$(oci iam policy list -c "$tenancy" --name "$name-capture" --query 'data[0].id' --raw-output)" ]; then
  oci iam policy create -c "$tenancy" --name "$name-capture" --description "A1 capture workflow" \
    --statements "[\"Allow group 'Default'/'$service_user' to manage instance-family in compartment $name\",\"Allow group 'Default'/'$service_user' to use volume-family in compartment $name\",\"Allow group 'Default'/'$service_user' to use virtual-network-family in compartment $name\"]" >/dev/null
fi

echo "Service user and group"
read -r user_id _ <<<"$(scim_find Users "userName%20eq%20%22$service_user%22")"
if [ -z "${user_id:-}" ]; then
  user_id=$(scim_post Users "{\"schemas\":[\"urn:ietf:params:scim:schemas:core:2.0:User\"],\"urn:ietf:params:scim:schemas:oracle:idcs:extension:user:User\":{\"serviceUser\":true},\"userName\":\"$service_user\"}" 'data.id')
fi
need "service user" "$user_id" >/dev/null
read -r group_id _ <<<"$(scim_find Groups "displayName%20eq%20%22$service_user%22")"
if [ -z "${group_id:-}" ]; then
  group_id=$(scim_post Groups "{\"schemas\":[\"urn:ietf:params:scim:schemas:core:2.0:Group\"],\"displayName\":\"$service_user\",\"members\":[{\"value\":\"$user_id\",\"type\":\"User\"}]}" 'data.id')
fi
need group "$group_id" >/dev/null

echo "Confidential app"
read -r app_id client_id <<<"$(scim_find Apps "displayName%20eq%20%22$name-github%22")"
client_secret=
if [ -z "${app_id:-}" ]; then
  read -r app_id client_id client_secret <<<"$(scim_post Apps "{\"schemas\":[\"urn:ietf:params:scim:schemas:oracle:idcs:App\"],\"displayName\":\"$name-github\",\"isOAuthClient\":true,\"clientType\":\"confidential\",\"allowedGrants\":[\"client_credentials\"],\"basedOnTemplate\":{\"value\":\"CustomWebAppTemplateId\"},\"active\":true}" 'join(`" "`, [data.id, data.name, data."clientSecret"])')"
  need "app" "$app_id" >/dev/null
  oci raw-request --http-method PUT --target-uri "$domain_url/admin/v1/AppStatusChanger/$app_id" \
    --request-body '{"schemas":["urn:ietf:params:scim:schemas:oracle:idcs:AppStatusChanger"],"active":true}' >/dev/null
else
  client_secret=$(oci raw-request --http-method GET --target-uri "$domain_url/admin/v1/Apps/$app_id?attributes=clientSecret" \
    --query 'data."clientSecret"' --raw-output)
fi

echo "Identity propagation trust"
read -r trust_id _ <<<"$(scim_find IdentityPropagationTrusts "name%20eq%20%22$name-github%22")"
if [ -z "${trust_id:-}" ]; then
  trust_id=$(scim_post IdentityPropagationTrusts "{\"schemas\":[\"urn:ietf:params:scim:schemas:oracle:idcs:IdentityPropagationTrust\"],\"name\":\"$name-github\",\"type\":\"JWT\",\"issuer\":\"$github_issuer\",\"publicKeyEndpoint\":\"$github_issuer/.well-known/jwks\",\"active\":true,\"oauthClients\":[\"$client_id\"],\"clientClaimName\":\"aud\",\"clientClaimValues\":[\"ocloud-oci\"],\"subjectClaimName\":\"sub\",\"subjectType\":\"User\",\"allowImpersonation\":true,\"impersonationServiceUsers\":[{\"rule\":\"sub eq $github_subject\",\"value\":\"$user_id\"}]}" 'data.id')
fi
need trust "$trust_id" >/dev/null

echo "GitHub secrets"
set_secret() { "$GH_BIN" secret set "$1" --repo "$repo" --body "$2" >/dev/null; }
set_secret OCI_DOMAIN_URL "$domain_url"
set_secret OCI_TENANCY "$tenancy"
set_secret OCI_REGION "$region"
set_secret OCI_COMPARTMENT "$compartment"
set_secret OCI_SUBNET "$subnet"
set_secret OCI_CLIENT_ID "$client_id"
set_secret SSH_PUBLIC_KEY "$(cat "$SSH_KEY")"
set_secret OCI_CLIENT_SECRET "$(need "client secret" "$client_secret")"

echo "Done."
