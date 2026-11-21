## Reset button
##
## Watch the physical reset key and reboot the system when it is held
## down for a few seconds. The key is read straight from the GPIO
## chip, so this does not need the input subsystem or a keymap: the
## kernel only has to expose /dev/gpiochip* (GPIO_CDEV, set below).
## On the JDCloud RE-CS-02 the reset key is GPIO 56, active-low.

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
    system.service.reset-button = mkOption {
      type = liminix.lib.types.serviceDefn;
    };
  };
  config.system.service.reset-button =
    config.system.callService ./reset-button.nix {
      gpio = mkOption {
        description = "GPIO line number of the reset key on the pinctrl chip";
        type = types.int;
        default = 56;
      };
      holdSeconds = mkOption {
        description = "seconds the key must be held to trigger a reboot";
        type = types.int;
        default = 5;
      };
    };
  config.kernel.config.GPIO_CDEV = "y";
}
