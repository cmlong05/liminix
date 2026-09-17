# Web-uploadable, single-file "full system in initramfs" image for the
# phase-E ethernet bring-up of the JDCloud AX6600 (RE-CS-02).
#
# WIRED-ONLY / NO-WIFI build. The ethernet drivers are built into the
# kernel, so the whole system can ride inside the kernel image as an
# initramfs and be booted straight from the U-Boot web uploader at
# http://192.168.1.1/uimage.html - no serial console, no TFTP, and no
# wireless firmware or module loading anywhere in the boot path.
#
# Build with:
#   nix-build --arg device "import ./devices/jdcloud-ax6600" \
#     -I liminix-config=./ax6600-lan-ram.nix -A outputs.uimage -o result-lan-ram
# then upload result-lan-ram via /uimage.html.
#
# Once booted: lan1..lan4 are bridged into "int" at the address and with
# the dnsmasq pool given by devices/jdcloud-ax6600/config.nix (currently
# 10.10.10.1/24), and the 2.5G "wan" runs a PPPoE client using the
# account from that same file.
# Success is observable without a serial console: a PC on lan1 gets a
# lease; on panic the pstore ramoops region (0x60000000) survives for
# a U-Boot 'md' read after reboot. (No ssh: dropbear fails to build
# on the current nixpkgs channel - patch drift in its manpage.)
{
  config,
  pkgs,
  lib,
  ...
}:
let
  svc = config.system.service;
in
{
  imports = [
    ./ax6600-lan.nix
    ./modules/outputs/initramfs.nix
  ];

  boot = {
    initramfs = {
      enable = true;
      fullSystem = true;
    };
    # no root= / init=: preinit detects the missing root device and
    # runs the embedded system. nr_cpus=1/nokaslr same as the serial
    # bring-up baseline.
    commandLine = lib.mkForce [
      "panic=10 oops=panic loglevel=8"
      "console=ttyMSM0,115200n8"
      "fw_devlink=off"
      "nr_cpus=1"
      "nokaslr"
    ];
    imageFormat = "fit";
  };

  hardware.defaultOutput = "uimage";
}
