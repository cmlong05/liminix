# 构建命令
# -Q 不把各 derivation 的构建日志转发到终端
# 指定配置文件
# -I liminix-deployment=./devices/jdcloud-ax6600/config-lab.nix


# 有线版（lan1..lan4 桥接 + 2.5G PPPoE），不含无线栈
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-lan-ram.nix \
    -A outputs.uimage \
    -o result-lan-ram && \
    sh md5_result.sh

# NSS（lan1..lan4 桥接 + 2.5G PPPoE + 2.4g + 5.8g）
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-nss-ram.nix \
    -A outputs.uimage \
    -o result-nss-lan-ram && \
    sh md5_result.sh

# uimage rootfs
nix-build -Q 
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-rootfs.nix \
    -A outputs.uimage \
    -A outputs.rootfs -o result-rootfs \
    && sh md5_result.sh


# ttl 命令
sudo nix-shell -p picocom --run "picocom -b 115200 /dev/ttyUSB0"
