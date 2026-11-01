#!/usr/bin/env bash
# Tries each availability domain once. No capacity is a normal outcome and exits 0;
# any other error fails the run. The repo is public, so OCI output stays out of the
# log unless a launch fails unexpectedly.
set -euo pipefail

shape=VM.Standard.A1.Flex
shape_config='{"ocpus": 4, "memoryInGBs": 24}'
boot_volume_gb=100
name=ocloud-a1

stop_capturing() {
  gh workflow disable capture-a1.yml --repo "$GITHUB_REPOSITORY"
  echo "Workflow disabled."
}

existing=$(oci compute instance list -c "$OCI_COMPARTMENT" --all \
  --query "length(data[?shape=='$shape' && \"lifecycle-state\"!='TERMINATED' && \"lifecycle-state\"!='TERMINATING'])" \
  --raw-output)
if [ "$existing" != "0" ]; then
  echo "An A1 instance already exists."
  stop_capturing
  exit 0
fi

image=$(oci compute image list -c "$OCI_COMPARTMENT" --shape "$shape" --all \
  --operating-system "Canonical Ubuntu" --operating-system-version "24.04" \
  --sort-by TIMECREATED --sort-order DESC \
  --query 'data[0].id' --raw-output)

ssh_key_file="$RUNNER_TEMP/oci/ssh.pub"
printf '%s\n' "$SSH_PUBLIC_KEY" > "$ssh_key_file"

ads=$(oci iam availability-domain list -c "$OCI_TENANCY" --query 'data[].name' --raw-output | jq -r '.[]')

for ad in $ads; do
  label=${ad#*:}
  if output=$(oci --no-retry compute instance launch \
    --availability-domain "$ad" \
    --compartment-id "$OCI_COMPARTMENT" \
    --subnet-id "$OCI_SUBNET" \
    --image-id "$image" \
    --shape "$shape" \
    --shape-config "$shape_config" \
    --boot-volume-size-in-gbs "$boot_volume_gb" \
    --assign-public-ip true \
    --display-name "$name" \
    --ssh-authorized-keys-file "$ssh_key_file" 2>&1); then
    echo "$label: launched."
    stop_capturing
    exit 0
  fi

  if grep -qiE 'out of (host )?capacity|TooManyRequests' <<<"$output"; then
    echo "$label: no capacity."
  else
    echo "$label: launch failed."
    echo "$output"
    exit 1
  fi
done

echo "No capacity in any availability domain; will retry on the next schedule."
