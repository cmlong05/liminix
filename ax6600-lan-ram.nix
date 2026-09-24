# Web-uploadable, single-file "full system in initramfs" image 

{
  config,
  pkgs,
  lib,
  ...
}:
let
  svc = config.system.service;
in
{
  imports = [
    ./ax6600-lan.nix
    ./modules/outputs/initramfs.nix
  ];

  boot = {
    initramfs = {
      enable = true;
      fullSystem = true;
    };
    imageFormat = "fit";
  };

  hardware.defaultOutput = "uimage";
}
