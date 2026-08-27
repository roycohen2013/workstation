variable "cloudflare_api_token" {
  type        = string
  sensitive   = true
  description = "R2-scoped API token. Prefer the CLOUDFLARE_API_TOKEN environment variable over passing this on the command line."
  default     = null
}

variable "cloudflare_account_id" {
  type        = string
  description = "Cloudflare account ID that owns the bucket."
}

variable "bucket_name" {
  type        = string
  default     = "workstation-artifacts"
  description = "Bucket holding published images. Must be globally unique within the account."
}

variable "bucket_location" {
  type        = string
  default     = "ENAM"
  description = "R2 location hint: ENAM, WNAM, EEUR, WEUR, APAC or OC."
}
