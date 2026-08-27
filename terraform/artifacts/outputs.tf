output "bucket_name" {
  value       = cloudflare_r2_bucket.artifacts.name
  description = "Set as WORKSTATION_BUCKET for the publish and fetch scripts."
}

output "s3_endpoint" {
  value       = "https://${var.cloudflare_account_id}.r2.cloudflarestorage.com"
  description = "Set as AWS_ENDPOINT_URL so the aws CLI talks to R2."
}

output "usage" {
  description = "Environment the publish/fetch scripts expect."
  value       = <<-EOT
    export WORKSTATION_BUCKET=${cloudflare_r2_bucket.artifacts.name}
    export AWS_ENDPOINT_URL=https://${var.cloudflare_account_id}.r2.cloudflarestorage.com
    export AWS_ACCESS_KEY_ID=<r2 access key id>
    export AWS_SECRET_ACCESS_KEY=<r2 secret access key>
    export AWS_DEFAULT_REGION=auto
  EOT
}
