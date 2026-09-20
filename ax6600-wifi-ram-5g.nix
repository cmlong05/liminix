# The same image as ax6600-wifi-ram.nix, with the QCN9074 5GHz PCIe radio
# enabled. Not the default: on the firmware ImmortalWrt and OpenWrt both ship
# it does not reach mission mode on this unit - see
# devices/jdcloud-ax6600/wifi/README.
#
# Build with:
#   nix-build --arg device "import ./devices/jdcloud-ax6600" \
#     -I liminix-config=./ax6600-wifi-ram-5g.nix -A outputs.uimage -o result-wifi-5g
{
  imports = [ ./ax6600-wifi-ram.nix ];
  wifi.qcn9074.enable = true;
}
