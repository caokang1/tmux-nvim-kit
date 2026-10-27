#!/usr/bin/env bash
# tmux + Neovim(LazyVim, IDEA 风格) + 浏览器访问 一键安装
# 在 WSL Ubuntu（或普通 Ubuntu/Debian）里，用普通用户运行：  ./install.sh [选项]
#
# 选项：
#   --password <密码>         浏览器访问密码（默认随机生成）
#   --user <用户名>           浏览器登录用户名（默认当前 Linux 用户名）
#   --port <端口>             浏览器访问端口（默认 7681）
#   --session <名称>          浏览器接入的 tmux 会话名（默认 code）
#   --proxy <http://主机:端口> Java/Maven 走的代理（如 Clash: http://127.0.0.1:7890）
#   --maven-settings <路径>   复制一份 Maven settings.xml（如 /mnt/c/Users/xxx/.m2/settings.xml）
#   --no-web                  不安装浏览器访问
#   --no-windows-path         WSL 不再把 Windows 的 PATH 加进来（更快，需重启 WSL）
#   -h, --help                显示帮助
set -euo pipefail

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d-%H%M%S)"

WEB_USER="$USER"
WEB_PASSWORD=""
WEB_PORT=7681
WEB_SESSION=code
PROXY=""
MAVEN_SETTINGS=""
INSTALL_WEB=1
NO_WINDOWS_PATH=0

while [ $# -gt 0 ]; do
  case "$1" in
    --password) WEB_PASSWORD="$2"; shift 2 ;;
    --user) WEB_USER="$2"; shift 2 ;;
    --port) WEB_PORT="$2"; shift 2 ;;
    --session) WEB_SESSION="$2"; shift 2 ;;
    --proxy) PROXY="$2"; shift 2 ;;
    --maven-settings) MAVEN_SETTINGS="$2"; shift 2 ;;
    --no-web) INSTALL_WEB=0; shift ;;
    --no-windows-path) NO_WINDOWS_PATH=1; shift ;;
    -h | --help) sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知选项: $1（用 --help 查看）"; exit 1 ;;
  esac
done

step() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }
warn() { printf '\033[1;33m[注意]\033[0m %s\n' "$*"; }
die() { printf '\033[1;31m[错误]\033[0m %s\n' "$*"; exit 1; }
ver_ge() { [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -1)" = "$2" ]; } # $1 >= $2
apt_has() { [ -n "$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ && $2 != "(none)" {print $2}')" ]; }
backup() { [ -e "$1" ] || [ -L "$1" ] && { mv "$1" "$1.bak.$TS"; info "已备份 $1 -> $1.bak.$TS"; } || true; }

[ "$(id -u)" -ne 0 ] || die "请用普通用户运行（脚本内部会在需要时调用 sudo）"
command -v apt-get >/dev/null || die "目前只支持 Ubuntu / Debian（apt）"
[ "$(uname -m)" = "x86_64" ] || warn "未在 $(uname -m) 架构上测试过，部分二进制下载可能失败"
[ -n "$WEB_PASSWORD" ] || WEB_PASSWORD="$(tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 10)"

step "请输入 sudo 密码（安装系统软件需要）"
sudo -v

# 代理：让本脚本里的 curl/git/apt 也走代理
if [ -n "$PROXY" ]; then
  export http_proxy="$PROXY" https_proxy="$PROXY" HTTP_PROXY="$PROXY" HTTPS_PROXY="$PROXY"
  export no_proxy="localhost,127.0.0.1" NO_PROXY="localhost,127.0.0.1"
fi
SUDO_ENV=(sudo env "http_proxy=${http_proxy:-}" "https_proxy=${https_proxy:-}" DEBIAN_FRONTEND=noninteractive)

# ---------------------------------------------------------------- 系统软件
step "安装系统软件（git、ripgrep、fd、tmux、ttyd、maven、npm 等）"
"${SUDO_ENV[@]}" apt-get update -qq
PKGS=(build-essential git curl wget unzip xz-utils ripgrep fd-find fzf tmux maven npm python3 python3-venv)
[ $INSTALL_WEB -eq 1 ] && PKGS+=(ttyd python3-fonttools python3-brotli)
"${SUDO_ENV[@]}" apt-get install -y -qq "${PKGS[@]}" >/dev/null
[ -e /usr/local/bin/fd ] || sudo ln -sf "$(command -v fdfind)" /usr/local/bin/fd

step "安装 Neovim（需要 0.11.2 以上）"
NVIM_APT_VER="$(apt-cache policy neovim | awk '/Candidate:/ {print $2}' | sed 's/-.*//; s/~.*//')"
if [ "$NVIM_APT_VER" != "(none)" ] && ver_ge "$NVIM_APT_VER" 0.11.2; then
  "${SUDO_ENV[@]}" apt-get install -y -qq neovim >/dev/null
else
  info "系统源里的 Neovim 版本过低（$NVIM_APT_VER），改为从 GitHub 下载最新稳定版"
  curl -fsSL -o /tmp/nvim.tar.gz https://github.com/neovim/neovim/releases/download/stable/nvim-linux-x86_64.tar.gz
  sudo rm -rf /opt/nvim-linux-x86_64 && sudo tar -C /opt -xzf /tmp/nvim.tar.gz
  sudo ln -sf /opt/nvim-linux-x86_64/bin/nvim /usr/local/bin/nvim
fi
info "$(nvim --version | head -1)"

step "安装 JDK 25（Java 语言服务 jdtls 需要；不影响项目本身用的 JDK 版本）"
if apt_has openjdk-25-jdk-headless; then
  "${SUDO_ENV[@]}" apt-get install -y -qq openjdk-25-jdk-headless >/dev/null
  JAVA25="$(update-alternatives --list java | grep -- '-25' | head -1)"
else
  info "系统源里没有 JDK 25，改为下载 Eclipse Temurin 25"
  curl -fsSL -o /tmp/jdk25.tar.gz "https://api.adoptium.net/v3/binary/latest/25/ga/linux/x64/jdk/hotspot/normal/eclipse"
  sudo mkdir -p /opt/jdk-25 && sudo tar -C /opt/jdk-25 --strip-components=1 -xzf /tmp/jdk25.tar.gz
  sudo update-alternatives --install /usr/bin/java java /opt/jdk-25/bin/java 2500 >/dev/null
  JAVA25=/opt/jdk-25/bin/java
fi
sudo update-alternatives --set java "$JAVA25" >/dev/null
info "$(java -version 2>&1 | head -1)"

step "安装 tree-sitter 命令行和 lazygit"
# nvim-treesitter 需要 tree-sitter 0.25+ 来编译语法解析器；旧版系统源里的版本太低（如 24.04 是 0.20）
ts_ver() { tree-sitter --version 2>/dev/null | awk '{print $2}'; }
if ! ver_ge "$(ts_ver || echo 0)" 0.25; then
  TS_APT_VER="$(apt-cache policy tree-sitter-cli 2>/dev/null | awk '/Candidate:/ {print $2}' | sed 's/-.*//')"
  if [ -n "$TS_APT_VER" ] && [ "$TS_APT_VER" != "(none)" ] && ver_ge "$TS_APT_VER" 0.25; then
    "${SUDO_ENV[@]}" apt-get install -y -qq tree-sitter-cli >/dev/null
  else
    info "系统源里的 tree-sitter 版本过低，改为从 GitHub 下载"
    curl -fsSL -o /tmp/tree-sitter.gz https://github.com/tree-sitter/tree-sitter/releases/latest/download/tree-sitter-linux-x64.gz
    gunzip -f /tmp/tree-sitter.gz && sudo install -m 755 /tmp/tree-sitter /usr/local/bin/tree-sitter
    hash -r
  fi
fi
info "tree-sitter $(ts_ver)"
if ! command -v lazygit >/dev/null; then
  if apt_has lazygit; then "${SUDO_ENV[@]}" apt-get install -y -qq lazygit >/dev/null
  else
    LG_VER="$(curl -fsSL https://api.github.com/repos/jesseduffield/lazygit/releases/latest | grep -Po '"tag_name": *"v\K[^"]*')"
    curl -fsSL -o /tmp/lazygit.tar.gz "https://github.com/jesseduffield/lazygit/releases/download/v${LG_VER}/lazygit_${LG_VER}_Linux_x86_64.tar.gz"
    tar -C /tmp -xzf /tmp/lazygit.tar.gz lazygit && sudo install /tmp/lazygit /usr/local/bin/lazygit
  fi
fi

# ---------------------------------------------------------------- 代理与 Maven
if [ -n "$PROXY" ] || [ -n "$MAVEN_SETTINGS" ]; then
  step "配置 Java / Maven"
fi
if [ -n "$MAVEN_SETTINGS" ]; then
  [ -f "$MAVEN_SETTINGS" ] || die "找不到 Maven 配置: $MAVEN_SETTINGS"
  mkdir -p ~/.m2 && backup ~/.m2/settings.xml
  sed 's/\r$//' "$MAVEN_SETTINGS" >~/.m2/settings.xml
  info "已复制 Maven 配置到 ~/.m2/settings.xml"
fi
if [ -n "$PROXY" ]; then
  P_HOST="$(echo "$PROXY" | sed -E 's#^[a-z]+://##; s#[:/].*##')"
  P_PORT="$(echo "$PROXY" | sed -E 's#^[a-z]+://##' | grep -oE ':[0-9]+' | tr -d ':')"
  P_PORT="${P_PORT:-80}"
  # Java 程序（Maven 命令行、jdtls）不读 http_proxy 环境变量，要用 JVM 参数
  if ! grep -q 'tmux-nvim-kit: java proxy' ~/.profile 2>/dev/null; then
    cat >>~/.profile <<EOF

# tmux-nvim-kit: java proxy —— Java（Maven / jdtls）走代理
export JAVA_TOOL_OPTIONS="-Dhttp.proxyHost=$P_HOST -Dhttp.proxyPort=$P_PORT -Dhttps.proxyHost=$P_HOST -Dhttps.proxyPort=$P_PORT -Dhttp.nonProxyHosts=localhost|127.*"
EOF
  fi
  # jdtls 内置的 Maven（m2e）只认 settings.xml 里的 <proxies>
  mkdir -p ~/.m2
  [ -f ~/.m2/settings.xml ] || printf '<settings>\n</settings>\n' >~/.m2/settings.xml
  if ! grep -q '<proxies>' ~/.m2/settings.xml; then
    PROXY_XML="  <proxies>\n    <proxy><id>kit-http</id><active>true</active><protocol>http</protocol><host>$P_HOST</host><port>$P_PORT</port><nonProxyHosts>localhost|127.*</nonProxyHosts></proxy>\n    <proxy><id>kit-https</id><active>true</active><protocol>https</protocol><host>$P_HOST</host><port>$P_PORT</port><nonProxyHosts>localhost|127.*</nonProxyHosts></proxy>\n  </proxies>\n</settings>"
    sed -i "s#</settings>#$PROXY_XML#" ~/.m2/settings.xml
  else
    warn "$HOME/.m2/settings.xml 里已有 <proxies>，未改动，请自行确认代理设置"
  fi
  info "Java / Maven 代理: $P_HOST:$P_PORT"
fi

# ---------------------------------------------------------------- tmux
step "配置 tmux"
backup ~/.tmux.conf
cp "$KIT_DIR/config/tmux.conf" ~/.tmux.conf
tmux source-file ~/.tmux.conf 2>/dev/null || true
# 打开链接：win-open 调用 Windows 浏览器，tmux-open-url 是 前缀 u 的链接菜单
mkdir -p ~/.local/bin
install -m 755 "$KIT_DIR/bin/win-open" "$KIT_DIR/bin/tmux-open-url" ~/.local/bin/
if grep -qi microsoft /proc/version && ! grep -q 'BROWSER=' ~/.bashrc; then
  printf '\n# Claude Code 等程序打开链接时用 Windows 默认浏览器\nexport BROWSER="$HOME/.local/bin/win-open"\n' >>~/.bashrc
fi

# ---------------------------------------------------------------- Neovim
step "配置 Neovim（LazyVim + IDEA 风格）"
for d in ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim; do backup "$d"; done
mkdir -p ~/.config
cp -r "$KIT_DIR/config/nvim" ~/.config/nvim

step "下载插件（按 lazy-lock.json 锁定的版本，首次较慢）"
nvim --headless "+Lazy! restore" +qa >/tmp/kit-lazy.log 2>&1 || { tail -20 /tmp/kit-lazy.log; die "插件下载失败，检查网络/代理后重新运行"; }

step "安装语法解析器（treesitter）"
nvim --headless "+lua require('nvim-treesitter').install({'java','kotlin','groovy','xml','yaml','json','json5','toml','properties','ini','sql','bash','dockerfile','make','proto','nginx','csv','diff','html','css','scss','javascript','typescript','tsx','vue','python','go','lua','vim','vimdoc','regex','markdown','markdown_inline','latex','git_config','gitcommit','gitignore','git_rebase'}):wait(900000)" +qa >/tmp/kit-ts.log 2>&1 || warn "部分语法解析器安装失败，可在 Neovim 里运行 :TSUpdate 重试"

step "安装语言服务（jdtls、XML、YAML、JSON 等）"
nvim --headless "+Lazy! load mason.nvim" "+MasonInstall jdtls lemminx bash-language-server shellcheck shfmt json-lsp yaml-language-server taplo vtsls pyright ruff dockerfile-language-server docker-compose-language-service lua-language-server stylua" +qa >/tmp/kit-mason.log 2>&1 || warn "部分语言服务安装失败，可在 Neovim 里运行 :Mason 查看"
info "已安装: $(ls ~/.local/share/nvim/mason/bin 2>/dev/null | tr '\n' ' ')"

# ---------------------------------------------------------------- 浏览器访问
if [ $INSTALL_WEB -eq 1 ]; then
  step "配置浏览器访问（ttyd）"
  [ -d /run/systemd/system ] || die "未启用 systemd。请在 /etc/wsl.conf 加入 [boot] systemd=true，执行 wsl --shutdown 后重新运行"
  C=~/.config/tmux-web
  mkdir -p "$C/fonts"

  # Ubuntu 的 ttyd 包自带一个 root 登录服务，会占用 7681 端口，停用它
  sudo systemctl disable --now ttyd.service >/dev/null 2>&1 || true

  info "下载 JetBrainsMono Nerd Font（嵌入网页，任何设备打开都能正常显示图标）"
  curl -fsSL -o /tmp/jbmono.tar.xz https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz
  tar -C "$C/fonts" -xJf /tmp/jbmono.tar.xz JetBrainsMonoNerdFontMono-Regular.ttf JetBrainsMonoNerdFontMono-Bold.ttf

  info "生成带字体的网页"
  TMP_PORT=17681
  ttyd -p $TMP_PORT -c kit:kit cat >/dev/null 2>&1 &
  TTYD_PID=$!
  sleep 1
  curl -fsS --noproxy '*' --compressed -u kit:kit "http://127.0.0.1:$TMP_PORT/" -o "$C/ttyd-original.html"
  kill $TTYD_PID 2>/dev/null || true
  python3 -I "$KIT_DIR/web/build_index.py" "$C/ttyd-original.html" "$C/fonts" "$C/index.html" >/dev/null

  # 配置文件（密码等），只有自己可读
  umask 077
  cat >"$C/env" <<EOF
TMUX_WEB_USER=$(printf '%q' "$WEB_USER")
TMUX_WEB_PASSWORD=$(printf '%q' "$WEB_PASSWORD")
TMUX_WEB_PORT=$WEB_PORT
TMUX_WEB_SESSION=$(printf '%q' "$WEB_SESSION")
TMUX_WEB_FONT_SIZE=14
# 新建 tmux 会话时的起始目录（建议改成 WSL 里的项目目录，如 \$HOME/project；用 tmux-web-ctl dir 修改）
TMUX_WEB_DIR=\$HOME
EOF
  umask 022

  sudo install -m 755 "$KIT_DIR/web/tmux-web" /usr/local/bin/tmux-web
  sudo install -m 755 "$KIT_DIR/web/tmux-web-ctl" /usr/local/bin/tmux-web-ctl
  sed "s#__USER__#$USER#; s#__HOME__#$HOME#" "$KIT_DIR/web/tmux-web.service" | sudo tee /etc/systemd/system/tmux-web.service >/dev/null
  sudo systemctl daemon-reload
  sudo systemctl enable tmux-web >/dev/null 2>&1
  sudo systemctl restart tmux-web
  sleep 1
  systemctl is-active --quiet tmux-web && info "浏览器访问服务已启动" || warn "服务未能启动，运行 tmux-web-ctl status 查看原因"
fi

# ---------------------------------------------------------------- WSL 设置
if [ $NO_WINDOWS_PATH -eq 1 ] && grep -qi microsoft /proc/version; then
  step "WSL：不再继承 Windows PATH"
  if ! grep -q '^appendWindowsPath' /etc/wsl.conf 2>/dev/null; then
    printf '\n[interop]\nappendWindowsPath=false\n' | sudo tee -a /etc/wsl.conf >/dev/null
  fi
  grep -q "alias explorer=" ~/.bashrc || printf "\n# Windows PATH 不再加入 WSL，常用 Windows 程序单独加回来\nalias explorer='/mnt/c/Windows/explorer.exe'\nalias clip='/mnt/c/Windows/System32/clip.exe'\n" >>~/.bashrc
  warn "需要在 Windows 里执行 wsl --shutdown 后重新打开 Ubuntu 才生效"
fi

# ---------------------------------------------------------------- 完成
step "安装完成"
cat <<EOF

  开始使用：
    tmux new -A -s $WEB_SESSION        # 进入 tmux 会话（浏览器看到的就是它）
    cd 你的项目 && nvim .             # 打开项目

EOF
if [ $INSTALL_WEB -eq 1 ]; then
  tmux-web-ctl url | sed 's/^/    /'
  cat <<EOF

    其他电脑打不开？在 Windows 里运行 windows\\setup.ps1（见 README「Windows 设置」）
    修改密码：tmux-web-ctl passwd 新密码
EOF
fi
[ -n "$PROXY" ] && echo -e "\n    代理设置写在 ~/.profile，请重新打开终端（或 source ~/.profile）后再用 nvim 打开 Java 项目"
echo
