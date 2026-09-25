# USB-root image: the same two artifacts as ax6600-rootfs.nix, with the root
# filesystem on a USB stick instead of the board's eMMC partition:
#
#   outputs.uimage  (kernel + dtb, cmdline embedded)  -> web upload, or 0:HLOS
#   outputs.rootfs  (squashfs)                        -> a USB partition named
#                                                        liminix-root
#
# The uimage is the same shape as the eMMC one - a FIT of kernel + dtb with
# the command line embedded and no rootdir - so U-Boot uploads and boots it
# from RAM exactly like the fullSystem images, and nothing on the eMMC is
# touched either way. That is the point: a device to iterate on without
# reflashing, recovered by re-uploading a -ram image.
#
# The root is squashfs, not ext4, deliberately: modules/outputs/ext4fs.nix
# forces boot.initramfs.enable, and pkgs/preinit/preinit.c mounts the string
# from root= verbatim - it does not resolve PARTLABEL/UUID and does not wait -
# which loses the race against asynchronous USB enumeration. With squashfs the
# kernel mounts the root itself and rootwait (already in the command line)
# covers the enumeration. Writable data belongs on a second ext4 partition
# mounted through modules/mount.
#
# The device tree needs nothing: the pinned fork's ipq6018-common.dtsi already
# says `&usb3 { dr_mode = "host"; status = "okay"; }` with &ssphy_0, and the
# board dtsi enables &qusb_phy_0 with the GPIO22 usb_vbus regulator
# (regulator-boot-on), so USB3 host is described and powered already.
{
  lib,
  ...
}:
{
  imports = [
    ./ax6600-rootfs.nix
    ./modules/usb.nix
  ];

  # mkForce because ax6600-rootfs.nix names the eMMC partition with a plain
  # definition; the command line there interpolates this option, so this one
  # line is the whole difference between the two images.
  hardware.rootDevice = lib.mkForce "PARTLABEL=liminix-root";

  kernel.config = {

    PARTITION_ADVANCED = "y";

    USB_XHCI_HCD = "y";
    USB_XHCI_PLATFORM = "y";
    USB_DWC3 = "y";
    USB_DWC3_HOST = "y";
    USB_DWC3_QCOM = "y";
    PHY_QCOM_QMP = "y";
    PHY_QCOM_QMP_USB = "y";
    PHY_QCOM_QUSB2 = "y";
    REGULATOR = "y";
    REGULATOR_FIXED_VOLTAGE = "y";
  };
}
