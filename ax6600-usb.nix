# USB-root system

#   outputs.uimage  (kernel + dtb, cmdline embedded)  -> p1, FAT, as fit.itb
#   outputs.rootfs  (squashfs, may change to ext4)    -> p2, GPT name
#                                                        liminix-root
#   (p3, ext4, volume label liminix-persist)          -> /persist
#
{
  lib,
  pkgs,
  ...
}:
let
  inherit (pkgs.pseudofile) dir symlink;
  persistLabel = "liminix-persist";
  persistMountpoint = "/persist";
in
{
  imports = [
    ./ax6600-rootfs.nix
    ./modules/usb.nix
  ];

  hardware.rootDevice = lib.mkForce "PARTLABEL=liminix-root";

  filesystem = dir {
    persist = dir { };
    etc = dir {
      "rc-init.d" = dir {
        persist = symlink (
          pkgs.writeAshScript "mount-persist" { } ''
            # A bounded wait, because a missing partition should mean no
            # persistence rather than a machine that will not boot.
            i=0
            while test "$i" -lt 10 ; do
                if mount -t ext4 LABEL=${persistLabel} ${persistMountpoint} 2>/dev/null ; then
                    echo ${persistMountpoint} > /run/state-mountpoint
                    exit 0
                fi
                i=$((i + 1))
                sleep 1
            done
            echo "no ${persistLabel} filesystem: service state stays on tmpfs"
          ''
        );
      };
    };
  };

  programs.busybox.options = {
    FEATURE_MOUNT_LABEL = "y";
    FEATURE_VOLUMEID_EXT = "y";
  };

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
