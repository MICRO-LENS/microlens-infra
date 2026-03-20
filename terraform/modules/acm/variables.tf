variable "name_prefix" {
  type = string
}

variable "domain" {
  type        = string
  description = "Root domain name (e.g. microlens.cloud)"
}

variable "zone_id" {
  type        = string
  description = "Route 53 Hosted Zone ID"
}
