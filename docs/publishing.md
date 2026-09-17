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
