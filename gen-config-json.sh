#!/bin/sh
# 从源码树的 deployment 生成 config.json —— 与镜像里 /persist 的种子同一份文本
#   sh gen-config-json.sh [输出文件] [-I liminix-deployment=<deployment.nix>]
set -eu
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-"$here/config.json"}
shift 2>/dev/null || true
case " $* " in
*" liminix-deployment="*) ;;
*) set -- -I "liminix-deployment=$here/devices/jdcloud-ax6600/config.nix" "$@" ;;
esac
nix-instantiate --eval --strict --raw "$@" \
    --expr "(import $here/devices/jdcloud-ax6600/deployment-json.nix { lib = import <nixpkgs/lib>; }).text" \
    > "$out"
