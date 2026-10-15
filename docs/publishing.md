<!-- Moved out of README.md so the entry point stays short. Hand-written;
     not generated, unlike configuration.md / roles.md / packer.md /
     terraform.md, which `make docs-config` produces. -->

# Publishing

```bash
cd terraform/artifacts
terraform init && terraform apply     # creates the R2 bucket
eval "$(terraform output -raw usage)" # exports the env the scripts want
cd ../..

make publish     # upload + move the 'stable' channel
make fetch       # on another machine
```

## Publishing from CI

`.github/workflows/build.yml` publishes on a `v*` tag, or when run by hand with
**publish** ticked. It reads its credentials from repository secrets
(*Settings → Secrets and variables → Actions*):

| Secret | Value |
|---|---|
| `WORKSTATION_BUCKET` | `terraform output -raw bucket_name` |
| `R2_ENDPOINT_URL` | `terraform output -raw s3_endpoint` |
| `R2_ACCESS_KEY_ID` | the R2 API token's access key ID |
| `R2_SECRET_ACCESS_KEY` | the R2 API token's secret access key |

Terraform creates the bucket but not the key. Make one in the Cloudflare
dashboard under *R2 → Manage R2 API Tokens*, with **Object Read & Write**
permission scoped to this bucket only. The secret is shown once.

The workflow checks the three required secrets before it starts building, so
a publish run with any of them missing fails in seconds rather than after the
build. For AWS S3 instead of R2, the secret names stay the same but
`R2_ENDPOINT_URL` must not exist -- see [`aws-s3-setup.md`](aws-s3-setup.md).

## Channels and retention

`WORKSTATION_CHANNEL` (default `stable`) names the pointer `make publish` moves
and `make fetch` resolves; `WORKSTATION_KEEP` (default 5) is how many builds
stay in the bucket. Publishing prunes older ones — except any build a channel
still points at, which survives however old it is. That is what lets a
slow-moving `stable` sit on a proven image while an `edge` channel races ahead:
the pointer is the only thing `make fetch` resolves through, so an image
deleted from under one breaks that channel outright. Keeping a pinned build can
therefore leave more than `WORKSTATION_KEEP` images in the bucket.

If the channel pointers cannot be read, nothing is pruned and the publish says
so. Not knowing what is pinned is not the same as nothing being pinned.

R2 rather than S3 because egress is free — pulling a multi-GB image down a few
times a month is the dominant cost otherwise. Any S3-compatible store works;
the scripts use the plain `aws` CLI, only adding a custom endpoint when
`AWS_ENDPOINT_URL` is set.

Want a real AWS S3 bucket instead — no Cloudflare account, or an existing AWS
setup? See [`aws-s3-setup.md`](aws-s3-setup.md).
