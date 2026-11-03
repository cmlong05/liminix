{
  lib,
  pkgs,
  config,
  ...
}:
let
  inherit (lib) mkOption types;
  inherit (pkgs) liminix;
in
{
  options.system.service.singleLine = mkOption {
    type = liminix.lib.types.serviceDefn;
  };
  config.system.service.singleLine = config.system.callService ./single-line.nix {
    name = mkOption {
      type = types.str;
      default = "single-line";
    };
    bridge = mkOption {
      type = liminix.lib.types.interface;
    };
    uplink = mkOption {
      type = liminix.lib.types.interface;
    };
    vlan = mkOption {
      type = types.str;
    };
    lanVlan = mkOption {
      type = types.int;
      default = 1;
    };
  };
}
