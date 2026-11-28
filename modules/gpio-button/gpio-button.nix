{
  liminix,
  lib,
  gpio-button,
}:
{
  name,
  gpio,
  holdSeconds,
  command ? null,
}:
let
  inherit (liminix.services) longrun;
  action = lib.optionalString (command != null) " ${lib.escapeShellArg command}";
in
longrun {
  inherit name;
  run = "${gpio-button}/bin/gpio-button ${toString gpio} ${toString holdSeconds}${action}";
}
