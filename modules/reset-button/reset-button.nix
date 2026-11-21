{
  liminix,
  lib,
  reset-button,
}:
{ gpio, holdSeconds }:
let
  inherit (liminix.services) longrun;
in
longrun {
  name = "reset-button";
  run = "${reset-button}/bin/reset-button ${toString gpio} ${toString holdSeconds}";
}
