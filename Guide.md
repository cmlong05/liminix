# 构建命令
nix-build \
    --arg device "import ./devices/jdcloud-ax6600" \
    -I liminix-config=./ax6600-lan-ram.nix \
    -A outputs.uimage \
    -o result-lan-ram && \
    sh md5_result.sh