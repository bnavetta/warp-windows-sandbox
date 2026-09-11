packer {
  required_version = ">= 1.14.0"

  required_plugins {
    qemu = {
      source  = "github.com/hashicorp/qemu"
      version = "~> 1.1"
    }
  }
}

variable "iso_url" {
  type        = string
  description = "Windows Server 2025 installation ISO URL or local path."
}

variable "iso_checksum" {
  type        = string
  description = "Windows ISO checksum, preferably prefixed with sha256:."
}


variable "virtio_stage_dir" {
  type        = string
  description = "Local directory containing the Server 2025 virtio drivers staged by build.sh."
}

variable "output_dir" {
  type        = string
  description = "Directory where Packer writes its build output."
  default     = "output-windows-server-2025"
}

variable "image_version" {
  type        = string
  description = "Bake date in YYYYMMDD form."

  validation {
    condition     = can(regex("^[0-9]{8}$", var.image_version))
    error_message = "The image_version value must use YYYYMMDD format."
  }
}

variable "admin_password" {
  type        = string
  description = "Temporary Administrator password used by Windows Setup and Packer."
  sensitive   = true
}

variable "ssh_public_key" {
  type        = string
  description = "OpenSSH public key installed for vmuser."
}

variable "cpus" {
  type        = number
  description = "Number of vCPUs used during the bake."
  default     = 4
}

variable "memory" {
  type        = number
  description = "Memory in MiB used during the bake."
  default     = 8192
}

variable "disk_size" {
  type        = string
  description = "Size of the Windows system disk."
  default     = "64G"
}

variable "efi_firmware_code" {
  type        = string
  description = "OVMF code firmware path on the Linux bake host."
  default     = "/usr/share/OVMF/OVMF_CODE_4M.fd"
}

variable "efi_firmware_vars" {
  type        = string
  description = "OVMF variable template path on the Linux bake host."
  default     = "/usr/share/OVMF/OVMF_VARS_4M.fd"
}

variable "headless" {
  type        = bool
  description = "Run QEMU without opening a local display."
  default     = true
}

locals {
  # These constants are shared with runtime QEMU arguments. Do not change them
  # independently: stable identity is required for future Azure Arc PAYG.
  vm_uuid          = "7b7f3b1e-6b3e-4f2a-9c1a-2d0e8a5c4f01"
  vm_smbios_serial = "WINSANDBOX-0001"
  vm_mac           = "52:54:00:12:34:56"

  admin_password_xml = replace(
    replace(
      replace(
        replace(
          replace(var.admin_password, "&", "&amp;"),
          "<",
          "&lt;"
        ),
        ">",
        "&gt;"
      ),
      "\"",
      "&quot;"
    ),
    "'",
    "&apos;"
  )
  ssh_public_key_base64 = base64encode(trimspace(var.ssh_public_key))
}

source "qemu" "windows_server_2025" {
  accelerator      = "kvm"
  machine_type     = "q35"
  cpu_model        = "host"
  cpus             = var.cpus
  memory           = var.memory
  disk_size        = var.disk_size
  disk_interface   = "virtio"
  disk_compression = true
  skip_compaction  = false
  format           = "qcow2"

  efi_boot          = true
  efi_firmware_code = var.efi_firmware_code
  efi_firmware_vars = var.efi_firmware_vars
  vtpm              = false

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  output_directory = var.output_dir
  vm_name          = "win-base-${var.image_version}.qcow2"
  headless         = var.headless
  # The Windows UEFI bootloader shows "Press any key to boot from CD or DVD"
  # for ~5s after OVMF POSTs; missing it drops into the UEFI shell. Press space
  # every second from t=2s to t=13s to cover the window. Extra presses after
  # Setup starts are harmless.
  boot_wait = "2s"
  boot_command = [
    "<spacebar><wait1s><spacebar><wait1s><spacebar><wait1s><spacebar><wait1s>",
    "<spacebar><wait1s><spacebar><wait1s><spacebar><wait1s><spacebar><wait1s>",
    "<spacebar><wait1s><spacebar><wait1s><spacebar><wait1s><spacebar>",
  ]

  net_device = "virtio-net"
  # QEMU has no if=sata; on q35, if=ide drives land on the AHCI (SATA) controller.
  cdrom_interface = "ide"

  cd_label = "PROVISION"
  cd_files = [
    "${var.virtio_stage_dir}/$WinPEDriver$",
    "${var.virtio_stage_dir}/virtio-win-guest-tools.exe",
    "${path.root}/setup/enable-openssh.ps1",
    "${path.root}/setup/enable-rdp.ps1",
    "${path.root}/setup/install-virtio-guest-tools.ps1",
    "${path.root}/setup/install-azcmagent.ps1",
    "${path.root}/setup/disable-noise.ps1",
    "${path.root}/setup/finalize.ps1",
  ]
  cd_content = {
    "Autounattend.xml" = templatefile("${path.root}/autounattend.xml", {
      admin_password = local.admin_password_xml
    })
  }

  communicator   = "winrm"
  winrm_username = "Administrator"
  winrm_password = var.admin_password
  winrm_timeout  = "1h"
  winrm_use_ssl  = false

  shutdown_command = "shutdown /s /t 10 /f /d p:4:1"
  shutdown_timeout = "15m"

  qemuargs = [
    ["-uuid", local.vm_uuid],
    ["-smbios", "type=1,serial=${local.vm_smbios_serial}"],
    ["-device", "virtio-net-pci,netdev=user.0,mac=${local.vm_mac}"],
  ]
}

build {
  sources = ["source.qemu.windows_server_2025"]

  provisioner "powershell" {
    environment_vars = [
      "SSH_PUBLIC_KEY_BASE64=${local.ssh_public_key_base64}",
    ]
    scripts = [
      "${path.root}/setup/enable-openssh.ps1",
      "${path.root}/setup/enable-rdp.ps1",
      "${path.root}/setup/install-virtio-guest-tools.ps1",
      "${path.root}/setup/install-azcmagent.ps1",
      "${path.root}/setup/disable-noise.ps1",
      "${path.root}/setup/finalize.ps1",
    ]
  }
}
