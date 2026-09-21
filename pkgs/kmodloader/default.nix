{
  liminix,
  lib,
  pkgs,
  targets ? [ ],
  kernel ? null,
  # extra .ko trees to make loadable alongside the kernel's own modules,
  # e.g. a `pkgs/kernel-module` output
  modules ? [ ],
  dependencies ? [ ],
}:
let
  inherit (liminix.services) oneshot;
  inherit (lib) concatStringsSep;
  tree = liminix.modules.build pkgs {
    roots = [ kernel.modulesupport ] ++ modules;
    inherit targets;
  };
in
oneshot {
  name = "kmodloader-" + (concatStringsSep "-" targets);
  up = "O=${tree}/lib/modules sh ${tree}/load.sh";
  down = "O=${tree}/lib/modules sh ${tree}/unload.sh";
  inherit dependencies;
}
