#!/usr/bin/env bash
# Exchanges the job's GitHub OIDC token for a short-lived OCI session token (UPST)
# and writes an OCI CLI config for the following steps.
set -euo pipefail

dir="$RUNNER_TEMP/oci"
mkdir -p "$dir"
chmod 700 "$dir"

openssl genrsa -out "$dir/key.pem" 2048 2>/dev/null
chmod 600 "$dir/key.pem"
public_key=$(openssl rsa -in "$dir/key.pem" -pubout -outform DER 2>/dev/null | base64 -w0)
fingerprint=$(openssl rsa -in "$dir/key.pem" -pubout -outform DER 2>/dev/null | openssl md5 -c | awk '{print $NF}')

github_jwt=$(curl -sSf -H "Authorization: bearer $ACTIONS_ID_TOKEN_REQUEST_TOKEN" \
  "$ACTIONS_ID_TOKEN_REQUEST_URL&audience=ocloud-oci" | jq -r .value)
echo "::add-mask::$github_jwt"

response=$(curl -sS "$OCI_DOMAIN_URL/oauth2/v1/token" \
  -u "$OCI_CLIENT_ID:$OCI_CLIENT_SECRET" \
  --data-urlencode 'grant_type=urn:ietf:params:oauth:grant-type:token-exchange' \
  --data-urlencode 'requested_token_type=urn:oci:token-type:oci-upst' \
  --data-urlencode "public_key=$public_key" \
  --data-urlencode "subject_token=$github_jwt" \
  --data-urlencode 'subject_token_type=jwt')
upst=$(jq -r '.token // empty' <<<"$response")
if [ -z "$upst" ]; then
  echo "Token exchange failed: $(jq -r '"\(.error) \(.error_description)"' <<<"$response")"
  # The payload claims are not secret; the signature is what makes the token usable.
  echo "GitHub token subject: $(cut -d. -f2 <<<"$github_jwt" | tr '_-' '/+' | base64 -d 2>/dev/null | jq -r .sub)"
  exit 1
fi
echo "::add-mask::$upst"

printf '%s' "$upst" > "$dir/token"
chmod 600 "$dir/token"

cat > "$dir/config" <<EOF
[DEFAULT]
fingerprint=$fingerprint
key_file=$dir/key.pem
tenancy=$OCI_TENANCY
region=$OCI_REGION
security_token_file=$dir/token
EOF
chmod 600 "$dir/config"

{
  echo "OCI_CLI_CONFIG_FILE=$dir/config"
  echo "OCI_CLI_AUTH=security_token"
} >> "$GITHUB_ENV"
