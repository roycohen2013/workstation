# Storage for published workstation images.
#
# Cloudflare R2 rather than S3 for one concrete reason: egress. A workstation
# image is several GB compressed, and pulling it down onto a couple of machines
# a few times a month is real bandwidth. R2 charges nothing for egress; S3
# charges roughly $0.09/GB, which is the dominant cost of this whole setup.
#
# R2 speaks the S3 API, so scripts/fetch-image.sh and the publish step use the
# ordinary aws CLI against an R2 endpoint -- nothing here is Cloudflare-specific
# beyond bucket creation.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.0"
    }
  }

  # State is kept local by default. To move it into the bucket this config
  # creates, uncomment below and re-run `terraform init -migrate-state` AFTER
  # the first apply -- the bucket has to exist before it can hold the state
  # that describes it.
  #
  # backend "s3" {
  #   bucket                      = "workstation-artifacts"
  #   key                         = "terraform/artifacts.tfstate"
  #   region                      = "auto"
  #   endpoints                   = { s3 = "https://<account_id>.r2.cloudflarestorage.com" }
  #   skip_credentials_validation = true
  #   skip_region_validation      = true
  #   skip_requesting_account_id  = true
  #   skip_s3_checksum            = true
  #   use_path_style              = true
  # }
}

provider "cloudflare" {
  # Supply via CLOUDFLARE_API_TOKEN. Never commit it.
  api_token = var.cloudflare_api_token
}

resource "cloudflare_r2_bucket" "artifacts" {
  account_id = var.cloudflare_account_id
  name       = var.bucket_name
  location   = var.bucket_location
}

# Retention is deliberately NOT managed here.
#
# R2's lifecycle API is thinner than S3's and its Terraform surface has moved
# between provider majors, so pinning image retention to it would make this
# config fragile for very little gain. scripts/publish-image.sh prunes to the
# newest N builds instead -- one place, one behaviour, no provider coupling.
