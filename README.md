# ocloud

A scheduled GitHub Actions workflow that keeps trying to launch one Always Free Ampere A1 instance in OCI `us-chicago-1`, then disables itself.

| Setting | Value |
| --- | --- |
| Shape | `VM.Standard.A1.Flex`, 4 OCPU, 24 GB |
| Image | Latest Canonical Ubuntu 24.04 aarch64 |
| Boot volume | 100 GB |
| Schedule | Every 5 minutes, trying each availability domain |

## How it authenticates

There are no OCI API keys. Each run requests a GitHub OIDC token and exchanges it at the identity domain for an OCI session token bound to a key pair generated for that run.

- The identity propagation trust accepts tokens only from GitHub's issuer, with audience `ocloud-oci` and subject `repo:candrii/ocloud:ref:refs/heads/main`.
- A matching token maps to the service user `ocloud-capture`, which has no password or API keys.
- That user's permissions are limited to the `ocloud` compartment.
- A compartment quota caps A1 at 4 OCPU and 24 GB.

## Setup

Log in with `oci session authenticate` and `gh auth login`, create an SSH key, then run `setup/bootstrap.sh`. It creates the compartment, network, quota, policy, service user, group, confidential app and trust, and stores the values in GitHub Actions secrets.

## After capture

Find the public IP:

```sh
oci compute instance list -c <compartment-ocid> --auth security_token
oci compute instance list-vnics --instance-id <instance-ocid> --auth security_token
```

Connect with `ssh -i ~/.ssh/ocloud_ed25519 ubuntu@<public-ip>`.

To capture again, terminate the instance and re-enable the workflow with `gh workflow enable capture-a1.yml`.
