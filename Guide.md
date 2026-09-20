# 构建命令
# -Q 不把各 derivation 的构建日志转发到终端

# 有线版（lan1..lan4 桥接 + 2.5G PPPoE），不含无线栈
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-lan-ram.nix \
    -A outputs.uimage \
    -o result-lan-ram && \
    sh md5_result.sh

# 有线 + 无线版（QCN9074 5G + 板载 IPQ6018 2.4G，见 devices/jdcloud-ax6600/wifi/README）
# 不需要额外的板级输入：校准数据在启动时由 firmware-ath11k 服务从 eMMC 的
# ART 分区读出（和 immortalwrt 的 11-ath11k-caldata 一样）
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-wifi-ram.nix \
    -A outputs.uimage \
    -o result-wifi && \
    sh md5_result.sh

# ttl 命令
sudo nix-shell -p picocom --run "picocom -b 115200 /dev/ttyUSB0"

# Deployment
The network this board is deployed into,  lives in `+./config.nix+`, as
plain data (`+hostname+`, `+lan.address+`, `+lan.prefixLength+`,
`+lan.dhcpRange+`). 
`+ax6600-lan.nix+` imports it and reads the 
address and the DHCP pool from it.

A different network means a different values file, selected with the
same `-I` idiom used for the configuration itself:

```console
$ nix-build --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-lan-ram.nix \
    -I liminix-deployment=./devices/jdcloud-ax6600/config-lab.nix \
    -A outputs.uimage
```

Without `+-I liminix-deployment+` the build falls back to
`+config.nix+`, so the common case needs no extra argument.