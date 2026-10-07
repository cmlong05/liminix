# 站点防火墙策略
#
# 这份规则不跟着镜像走：只有构建时显式指定才生效
#
#   -I liminix-firewall=./devices/jdcloud-ax6600/config_firewall.nix
#
# 不带该参数时镜像不带任何站点放行规则（build.sh 已带上）。每条是 nft
# 规则文本，追加进默认留空的 incoming-allowed-ip6（转发与到本机两条链
# 都会跳进去）。
{
  # 公网 IPv6 访问 LAN 主机的入站连接。不限定 daddr：LAN 前缀来自
  # DHCPv6-PD、主机地址来自 SLAAC，写死会失效。
  incomingAllowedIp6 = [
    "oifname @lan tcp dport 5858 accept" # allow_SSH
    "oifname @lan tcp dport 8443 accept" # allow_ERP
    "oifname @lan tcp dport 8444 accept" # allow_wuju
    "oifname @lan tcp dport 9443 accept" # allow_nextcloud
  ];
}
