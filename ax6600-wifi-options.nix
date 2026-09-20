# Options for the wifi images. Kept in their own module so the service
# modules can stay in the imports + bare-config form.
{
  lib,
  ...
}:
{
  options.wifi.qcn9074.enable = lib.mkEnableOption "the QCN9074 5GHz PCIe radio (0000:01:00.0)";
}
