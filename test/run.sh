#!/usr/bin/env bash
# 无界面测试：用仓库里的 config/nvim，复用已安装的插件 / mason / treesitter 解析器（只读使用，不重新下载）
# 用法：test/run.sh [test/spec/xxx_spec.lua ...]   不带参数运行全部
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# TEST_ID 不同的测试互不影响（各自的 jdtls 工作区、shada 等），可以并行跑
T="${XDG_CACHE_HOME:-$HOME/.cache}/tmux-nvim-kit-test/${TEST_ID:-default}"
SRC_DATA="${NVIM_KIT_DATA:-$HOME/.local/share/nvim}"
mkdir -p "$T/config" "$T/data/nvim" "$T/state" "$T/cache"
ln -sfn "$ROOT/config/nvim" "$T/config/nvim"
for d in lazy mason site; do ln -sfn "$SRC_DATA/$d" "$T/data/nvim/$d"; done
export XDG_CONFIG_HOME="$T/config" XDG_DATA_HOME="$T/data" XDG_STATE_HOME="$T/state" XDG_CACHE_HOME="$T/cache"
export NVIM_KIT_JDTLS_XMX="${NVIM_KIT_JDTLS_XMX:-1g}"
export NVIM_KIT_TEST=1 NVIM_KIT_ROOT="$ROOT"
specs=("$@")
[ ${#specs[@]} -eq 0 ] && specs=("$ROOT"/test/spec/*_spec.lua)
fail=0
for s in "${specs[@]}"; do
  echo "== $(basename "$s")"
  if ! timeout "${SPEC_TIMEOUT:-600}" nvim --headless -c "lua dofile('$ROOT/test/helper.lua').run('$(realpath "$s")')" 2>&1; then
    fail=1
  fi
done
exit $fail
