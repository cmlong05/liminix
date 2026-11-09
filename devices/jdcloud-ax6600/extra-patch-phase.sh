# 内核构建 extraPatchPhase 所用的原语集合：
#   - default.nix 按序调用这里的函数，完成打补丁与源码树装配
#   - kernel-checks.nix 依据各 SOURCES.nix 的 verify 记录生成检查调用
#
# 本文件被 source 而非直接执行：工作目录（解包后的内核源码树）、
# shell 与 errexit/pipefail 均继承自 stdenv 的 setup。

apply_patch() {
  patch -p1 --fuzz="$1" < "$2" || { echo "failed to apply $2"; exit 1; }
}

# What a patch must have left in the tree. `need` greps a whole file,
# `need_once` requires exactly one occurrence of the needle, `need_file`
# only that the file exists.
need() {
  grep -q "$2" "$1" || { echo "check failed: $3 ($1)"; exit 1; }
}

need_once() {
  test "$(grep -c "$2" "$1" || true)" = 1 || { echo "check failed: $3 ($1)"; exit 1; }
}

need_file() {
  test -f "$1" || { echo "check failed: $2 ($1)"; exit 1; }
}

# `needle` within `window` lines from the line holding `anchor`. Some
# needles sit in short braced blocks, and some occur elsewhere in the same
# file too, so for those a whole-file grep would prove nothing.
in_entry() {
  awk -v anchor="$2" -v needle="$3" -v win="$5" '
    BEGIN { if (win == "") win = 25 }
    index($0, anchor) { hit = 1 }
    hit { if (index($0, needle)) found = 1
          if (found || ++n > win) exit }
    END { exit found ? 0 : 1 }
  ' "$1" || { echo "check failed: $4 ($1)"; exit 1; }
}

# Mainline's qcom,ipq6018-wcss-pil node has to still be in the tarball: 0905
# rewrites its body and 0906 uses it as trailing context.
require_wcss_pil_in_tarball() {
  grep -q "qcom,ipq6018-wcss-pil" arch/arm64/boot/dts/qcom/ipq6018.dtsi ||
    { echo "ipq6018 wcss compatible missing from ipq6018.dtsi"; exit 1; }
}

# --no-preserve=mode: the store's read-only directory modes would leave the
# source root unwritable for the .config write the configure phase does.
install_overlay() {
  cp -a --no-preserve=mode "$1"/. .
}
