# ============================================================================
# environments/lab — variables
# ============================================================================

variable "fleet_size" {
  description = "Number of fleet VMs (1..30)"
  type        = number
  default     = 20
}

variable "fleet_image_name" {
  description = "Glance image for fleet VMs"
  type        = string
  default     = "cirros"
}

variable "fleet_flavor_name" {
  description = "Nova flavor for fleet VMs"
  type        = string
  default     = "m1.tiny"
}

variable "fleet_disk_gb" {
  description = "Boot volume size per fleet VM (GB)"
  type        = number
  default     = 5
}

variable "fleet_key_pair" {
  description = "Nova key pair name for fleet SSH"
  type        = string
  default     = "default"
}

variable "fleet_domain" {
  type    = string
  default = "lab.internal"
}

variable "fleet_timezone" {
  type    = string
  default = "UTC"
}

variable "fleet_ssh_public_key" {
  description = "Public key injected into fleet VMs. NEVER commit private keys."
  type        = string
  default     = ""
}

variable "fleet_package_update" {
  description = "Run apt update+upgrade in cloud-init (idempotent)"
  type        = bool
  default     = true
}

variable "fleet_packages" {
  type    = list(string)
  default = ["qemu-guest-agent"]
}

variable "fleet_install_guest_agent" {
  type    = bool
  default = true
}

# ----------------------------------------------------------------------------
# Auth (usually from env; overrides here for CI convenience)
# ----------------------------------------------------------------------------
variable "auth_url" {
  type    = string
  default = ""
}

variable "OS_PASSWORD" {
  type      = string
  default   = ""
  sensitive = true
}
