#!/usr/bin/env bash
# Launches whichever of the four instances are missing, trying each availability domain.
# No capacity is a normal outcome and exits 0; any other error fails the run. The repo is
# public, so OCI output stays out of the log unless a launch fails unexpectedly.
set -euo pipefail

shape=VM.Standard.A1.Flex
shape_config='{"ocpus": 1, "memoryInGBs": 6}'
boot_volume_gb=50
names=(ocloud-a1-1 ocloud-a1-2 ocloud-a1-3 ocloud-a1-4)

existing=$(oci compute instance list -c "$OCI_COMPARTMENT" --all --query data \
  | jq -r --arg shape "$shape" '.[]? | select(.shape == $shape and ."lifecycle-state" != "TERMINATED" and ."lifecycle-state" != "TERMINATING") | ."display-name"')

missing=()
for name in "${names[@]}"; do
  grep -qxF "$name" <<<"$existing" || missing+=("$name")
done
echo "Instances missing: ${#missing[@]} of ${#names[@]}"

if [ "${#missing[@]}" -gt 0 ]; then
  image=$(oci compute image list -c "$OCI_COMPARTMENT" --shape "$shape" --all \
    --operating-system "Canonical Ubuntu" --operating-system-version "24.04" \
    --sort-by TIMECREATED --sort-order DESC \
    --query 'data[0].id' --raw-output)

  ssh_key_file="$RUNNER_TEMP/oci/ssh.pub"
  printf '%s\n' "$SSH_PUBLIC_KEY" > "$ssh_key_file"

  ads=$(oci iam availability-domain list -c "$OCI_TENANCY" --query 'data[].name' --raw-output | jq -r '.[]')

  for ad in $ads; do
    label=${ad#*:}
    while [ "${#missing[@]}" -gt 0 ]; do
      if output=$(oci --no-retry compute instance launch \
        --availability-domain "$ad" \
        --compartment-id "$OCI_COMPARTMENT" \
        --subnet-id "$OCI_SUBNET" \
        --image-id "$image" \
        --shape "$shape" \
        --shape-config "$shape_config" \
        --boot-volume-size-in-gbs "$boot_volume_gb" \
        --assign-public-ip true \
        --display-name "${missing[0]}" \
        --ssh-authorized-keys-file "$ssh_key_file" 2>&1); then
        echo "$label: launched ${missing[0]}."
        missing=("${missing[@]:1}")
      elif grep -qiE 'out of (host )?capacity|TooManyRequests' <<<"$output"; then
        echo "$label: no capacity."
        break
      else
        echo "$label: launch of ${missing[0]} failed."
        echo "$output"
        exit 1
      fi
    done
  done
fi

if [ "${#missing[@]}" -gt 0 ]; then
  echo "Still missing ${#missing[@]}; will retry on the next schedule."
  exit 0
fi

echo "All instances exist."
gh workflow disable capture-a1.yml --repo "$GITHUB_REPOSITORY"
echo "Workflow disabled."
