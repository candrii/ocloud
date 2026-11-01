# ocloud

Four Always Free Ampere A1 instances in OCI `us-chicago-1`. Terraform deploys everything they depend on. A scheduled GitHub Actions workflow then keeps trying to launch whichever instances are missing, because A1 capacity is often unavailable, and disables itself once all four exist.

| Setting | Value |
| --- | --- |
| Instances | `ocloud-a1-1` to `ocloud-a1-4` |
| Shape | `VM.Standard.A1.Flex`, 1 OCPU, 6 GB each |
| Image | Latest Canonical Ubuntu 24.04 aarch64 |
| Boot volume | 50 GB each |
| Schedule | Every 5 minutes, trying each availability domain |

Together these use the whole Always Free A1 allowance of 4 OCPU, 24 GB and 200 GB of block storage.

## What Terraform deploys

- `ocloud` compartment, with a quota capping A1 at 4 OCPU and 24 GB
- VCN, internet gateway, default route, SSH ingress rule and a regional public subnet
- Service user, group and policy limited to the `ocloud` compartment
- Confidential app and identity propagation trust for GitHub OIDC
- The GitHub Actions secrets the workflow reads

## How the workflow authenticates

There are no OCI API keys. Each run requests a GitHub OIDC token and exchanges it at the identity domain for an OCI session token bound to a key pair generated for that run.

- The trust accepts tokens only from GitHub's issuer, with audience `ocloud-oci` and this repository's `main` branch as the subject. It uses GitHub's immutable subject format, `repo:candrii@<owner-id>/ocloud@<repo-id>:ref:refs/heads/main`.
- A matching token maps to the service user `ocloud-capture`, which has no password or API keys.

## Deploying the infrastructure

Requires an OCI administrator session, `gh` logged in with the `repo` scope, and an SSH key at `~/.ssh/ocloud_ed25519`. Run from `terraform/` in Git Bash:

```sh
oci session authenticate --region us-chicago-1 --profile-name DEFAULT
echo 'tenancy_ocid = "<tenancy-ocid>"' > terraform.tfvars

export TF_DATA_DIR="$LOCALAPPDATA/ocloud/.terraform"
export GITHUB_TOKEN="$(gh auth token)"

terraform init -backend-config="path=$LOCALAPPDATA/ocloud/terraform.tfstate"
terraform apply
```

The state contains the app's client secret, so it is kept outside the repo and OneDrive. Keep it private and don't share plan or apply output from changes to the app, because the provider doesn't mark that secret as sensitive.

## After capture

Find the public IPs:

```sh
oci compute instance list -c <compartment-ocid> --auth security_token
oci compute instance list-vnics --instance-id <instance-ocid> --auth security_token
```

Connect with `ssh -i ~/.ssh/ocloud_ed25519 ubuntu@<public-ip>`.

To replace an instance, terminate it without keeping its boot volume, because a leftover volume counts against the 200 GB allowance. Then re-enable the workflow:

```sh
oci compute instance terminate --instance-id <instance-ocid> --preserve-boot-volume false --auth security_token
gh workflow enable capture-a1.yml
```
