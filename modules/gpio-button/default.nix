## GPIO button
##
## Watch a physical key wired to a pinctrl/TLMM line and, when it has been
## held down for a few seconds, run a command - or reboot if no command is
## given. The key is read straight from the GPIO chip, so this does not
## need the input subsystem or a keymap: the kernel only has to expose
## /dev/gpiochip* (GPIO_CDEV, set below). Lines are treated as active-low.
##
## `name` is the s6 service name, so one image can wire several keys.

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
  options = {
    system.service.gpio-button = mkOption {
      type = liminix.lib.types.serviceDefn;
    };
  };
  config.system.service.gpio-button =
    config.system.callService ./gpio-button.nix {
      name = mkOption {
        description = "s6 service name for this button";
        type = types.str;
        default = "gpio-button";
      };
      gpio = mkOption {
        description = "GPIO line number of the key on the pinctrl chip";
        type = types.int;
        default = 56;
      };
      holdSeconds = mkOption {
        description = "seconds the key must be held to trigger the action";
        type = types.int;
        default = 5;
      };
      command = mkOption {
        description = "shell command to run on long press; null means sync and reboot";
        type = types.nullOr types.str;
        default = null;
      };
    };
  config.kernel.config.GPIO_CDEV = "y";
}
