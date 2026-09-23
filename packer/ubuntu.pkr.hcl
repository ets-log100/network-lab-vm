source "virtualbox-iso" "ubuntu" {
  vm_name          = "log100-network-lab-vm-${var.arch}"
  guest_os_type    = var.guest_os_type
  output_filename  = "log100-network-lab-vm-${var.arch}"
  output_directory = "output-${var.arch}"

  firmware = "efi"

  chipset                  = var.chipset
  iso_interface            = var.storage_interface
  hard_drive_interface     = var.storage_interface
  hard_drive_discard       = true
  hard_drive_nonrotational = true
  sata_port_count          = var.storage_interface == "sata" ? 2 : 1
  nic_type                 = var.nic_type
  gfx_controller           = "vmsvga"
  guest_additions_mode     = "disable"

  cpus           = 2
  memory         = 4096
  disk_size      = 24576
  headless       = false
  sound          = "none"
  usb            = var.arch == "arm64"
  usb_controller = var.arch == "arm64" ? "xhci" : "none"
  keyboard       = var.arch == "arm64" ? "usb" : "ps2"

  iso_url      = var.iso_url
  iso_checksum = var.iso_checksum

  vboxmanage = var.arch == "arm64" ? [
    [
      "storagectl",
      "{{.Name}}",
      "--name",
      "IDE",
      "--remove"
    ]
    ] : [
    [
      "modifyvm",
      "{{.Name}}",
      "--boot1", "dvd",
      "--boot2", "disk",
      "--boot3", "none",
      "--boot4", "none"
    ]
  ]

  http_directory        = "${path.root}/http"
  http_bind_address     = "0.0.0.0"
  http_network_protocol = "tcp4"

  boot_wait              = "20s"
  boot_keygroup_interval = "200ms"
  boot_command = [
    "c<wait2>",
    "set gfxpayload=keep<enter><wait2>",
    "linux /casper/vmlinuz autoinstall ds=\"nocloud-net;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/\" ---<enter><wait2>",
    "initrd /casper/initrd<enter><wait2>",
    "boot<enter>"
  ]

  communicator  = "ssh"
  ssh_username  = "packer"
  ssh_password  = "packer"
  ssh_timeout   = "45m"
  host_port_min = 2223
  host_port_max = 2299

  shutdown_command = "echo 'packer' | sudo -S /usr/local/sbin/log100-finalize-build"
  shutdown_timeout = "10m"

  format = "ova"
  export_opts = [
    "--manifest",
    "--vsys", "0",
    "--description", "LOG100 - Machine virtuelle pour les laboratoires de réseautique",
    "--version", var.vm_version
  ]

  vboxmanage_post = [
    ["modifyvm", "{{.Name}}", "--nat-pf1", "ssh,tcp,127.0.0.1,2222,,22"]
  ]
}

build {
  name    = "log100-network-lab-vm"
  sources = ["source.virtualbox-iso.ubuntu"]

  provisioner "shell" {
    script          = "${path.root}/scripts/provision.sh"
    execute_command = "echo 'packer' | sudo -S -E bash '{{ .Path }}'"
  }

  provisioner "shell" {
    script          = "${path.root}/scripts/cleanup.sh"
    execute_command = "echo 'packer' | sudo -S -E bash '{{ .Path }}'"
  }
}
