{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (pkgs) liminix;
in
{
  options.system.service.singBox = mkOption {
    type = liminix.lib.types.serviceDefn;
  };

  config = {
    kernel.config.TUN = "y";

    system.service.singBox = config.system.callService ./service.nix {
      configFile = mkOption {
        type = types.str;
        default = "/var/lib/liminix/sing-box/config.json";
      };
      stateDir = mkOption {
        type = types.str;
        default = "/var/lib/liminix/sing-box";
      };
      tunName = mkOption {
        type = types.str;
        default = "sing-box0";
      };
    };
  };
}
