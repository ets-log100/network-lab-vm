packer {
  required_version = ">= 1.14.0"

  required_plugins {
    virtualbox = {
      version = "= 1.1.5"
      source  = "github.com/hashicorp/virtualbox"
    }
  }
}

variable "storage_interface" {
  type = string
  validation {
    condition     = contains(["sata", "virtio"], var.storage_interface)
    error_message = "L'interface de stockage doit être sata ou virtio."
  }
}

variable "arch" {
  type = string
  validation {
    condition     = contains(["amd64", "arm64"], var.arch)
    error_message = "L'architecture doit être amd64 ou arm64."
  }
}

variable "guest_os_type" {
  type = string
}

variable "chipset" {
  type = string
}

variable "nic_type" {
  type = string
}

variable "iso_url" {
  type = string
}

variable "iso_checksum" {
  type = string
}

variable "vm_version" {
  type = string
}
