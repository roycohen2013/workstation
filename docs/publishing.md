<!-- Moved out of README.md so the entry point stays short. Hand-written;
     not generated, unlike configuration.md / roles.md / packer.md /
     terraform.md, which `make docs-config` produces. -->

# Publishing

```bash
cd terraform/artifacts
terraform init && terraform apply     # creates the R2 bucket
eval "$(terraform output -raw usage)" # exports the env the scripts want
cd ../..

make publish     # upload + move the 'stable' channel pointer
make fetch       # on another machine
```

R2 rather than S3 because egress is free — pulling a multi-GB image down a few
times a month is the dominant cost otherwise. Any S3-compatible store works;
the scripts use the plain `aws` CLI, only adding a custom endpoint when
`AWS_ENDPOINT_URL` is set.

Want a real AWS S3 bucket instead — no Cloudflare account, or an existing AWS
setup? See [`aws-s3-setup.md`](aws-s3-setup.md).
