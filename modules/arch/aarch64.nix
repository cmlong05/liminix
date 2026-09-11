{
  lim,
  pkgs,
  config,
  ...
}:
{
  config = {
    kernel.config = {
      CPU_LITTLE_ENDIAN = "y";
      # (CPU_BIG_ENDIAN=n removed: on arm64 >= 6.18 the option is
      # promptless under CPU_LITTLE_ENDIAN and olddefconfig drops the
      # explicit "n", tripping the config-consistency check)
      # CMDLINE_FROM_BOOTLOADER availability is conditional
      # on CMDLINE being set to something non-empty
      CMDLINE = "\"empty=false\"";
      CMDLINE_FROM_BOOTLOADER = "y";

      OF = "y";
      # USE_OF = "y";

      ARM64_PTR_AUTH = "n";
      RANDOMIZE_BASE = "y";
    };
    hardware.ram.startAddress = lim.parseInt "0x40000000";
    system.outputs.u-boot = pkgs.ubootQemuAarch64;
  };
}
