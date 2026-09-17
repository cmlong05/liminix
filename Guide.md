# 构建命令
# -Q 不把各 derivation 的构建日志转发到终端
nix-build -Q \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-lan-ram.nix \
    -A outputs.uimage \
    -o result-lan-ram && \
    sh md5_result.sh