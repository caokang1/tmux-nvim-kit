# tmux-nvim-kit

> 一键在 Windows（WSL）里搭一套**像 IntelliJ IDEA 一样好用的轻量看代码环境**：Neovim + tmux，还能在浏览器里打开。
> A one-command setup for an IDEA-like code reading environment on WSL: Neovim (LazyVim) + tmux + browser access via ttyd.

![平台](https://img.shields.io/badge/平台-Windows_10%2F11_+_WSL2-0078D6)
![Neovim](https://img.shields.io/badge/Neovim-0.11+-57A143)
![tmux](https://img.shields.io/badge/tmux-3.4+-1BB91F)
![语言](https://img.shields.io/badge/文档-中文-red)
![License](https://img.shields.io/badge/License-MIT-blue)

## 为什么用它

IDEA 打开大型 Java 项目又慢又吃内存，只是想**看代码、跳转、搜索**时显得太重。这套工具把 Neovim 调教成 IDEA 的样子和手感：

- **不用重新学快捷键**：`Ctrl+B` 跳转、`Ctrl+Shift+F` 全局搜索、`Ctrl+F` 查找、`Ctrl+E` 最近文件、`Alt+Enter` 意图操作……按 IDEA（Windows 默认键位）来
- **Neovim + LazyVim**：配色、界面尽量向 IDEA（Islands Dark）看齐，Java 跳转 / 查找引用由 jdtls 提供
- **tmux**：多项目、多窗口、分屏，关掉终端也不丢；适合左边看代码、右边跑 Claude Code
- **浏览器访问**：内网任何设备打开网页，就能看到并操作同一个 tmux 画面
- **全中文**：按键提示、帮助面板（`F1` / `空格 h`）、状态提示都是中文

## 功能一览

| 能力 | 说明 |
|---|---|
| Java 看代码 | `gd` 跳定义、`gr` 查引用、`gI` 跳实现；跳进依赖库自动下载源码/反编译；Lombok 支持；项目导入进度显示在状态栏 |
| IDEA 快捷键 | Windows 默认键位；`Ctrl+Shift+字母` 在 Windows Terminal 和浏览器里都可用（见 `windows/wt-keys.ps1`） |
| IDEA 配色 | 关键字橙、字符串绿、字段紫、注解土黄、方法声明蓝、static 斜体（jdtls 语义高亮） |
| IDEA 界面 | 顶部固定显示当前类/方法、面包屑、方法上方 "N references"、参数名提示、文件标签栏、右上角查找栏 |
| 搜索 | 全局搜索默认按字面、不区分大小写，`Alt+C/W/X` 切换大小写 / 整词 / 正则；结果大预览 |
| 鼠标 | 点击、`Ctrl+单击` 跳转、`Shift+滚轮` 横向滚动、拖选复制，tmux 里也能用 |
| 各类文件 | XML/pom、YAML、properties、JSON、SQL、Shell、Dockerfile、前端、Python、Markdown（直接渲染）等 |
| 浏览器 | 内嵌 Nerd Font，任何设备打开图标都正常；带登录密码；复制内容进入当前设备剪贴板 |
| 链接 | Claude Code 等程序里的链接自动用 Windows 浏览器打开；`前缀 u` 列出面板里的链接 |

## 快速开始

```powershell
# Windows PowerShell：下载并做 Windows 端设置（字体、网络、防火墙）
git clone https://github.com/caokang1/tmux-nvim-kit.git D:\tmux-nvim-kit
cd D:\tmux-nvim-kit
powershell -ExecutionPolicy Bypass -File windows\setup.ps1 -PrivateNetwork
powershell -ExecutionPolicy Bypass -File windows\wt-keys.ps1   # 可选：Windows Terminal 支持 Ctrl+Shift 快捷键
wsl --shutdown
```

```bash
# Ubuntu：安装（20～30 分钟）
cd /mnt/d/tmux-nvim-kit
./install.sh --proxy http://127.0.0.1:7890 --password 你的密码

# 使用：项目建议放在 WSL 里（如 ~/project），放在 /mnt/d 上会慢很多
tmux new -A -s code
cd ~/project && nvim .
```

详细步骤和参数见下文。

## 目录

- [一、安装](#一安装)
- [二、日常使用](#二日常使用)
- [三、常见问题](#三常见问题)
- [四、卸载](#四卸载)
- [目录说明](#目录说明)

---

## 一、安装

### 准备

- Windows 10/11，已安装 **WSL 2 + Ubuntu**（22.04 / 24.04 / 26.04 都可以）
  没装的话，管理员 PowerShell 运行 `wsl --install -d Ubuntu`，按提示重启、设置用户名密码
- 网络能访问 GitHub。国内网络建议开着代理（Clash 等），安装时用 `--proxy` 指定

### 第 1 步：Windows 端设置（字体、网络、防火墙）

用 `git clone https://github.com/caokang1/tmux-nvim-kit.git D:\tmux-nvim-kit` 下载（或在 GitHub 页面 Code → Download ZIP 解压），放到任意位置都可以，在 PowerShell 里运行：

```powershell
cd D:\tmux-nvim-kit
powershell -ExecutionPolicy Bypass -File windows\setup.ps1 -PrivateNetwork
```

| 参数 | 作用 |
|---|---|
| `-Port 7681` | 浏览器访问端口（默认 7681，要和第 2 步一致） |
| `-PrivateNetwork` | 把当前网络设为"专用网络"。**不加的话，如果网络是"公用"，别人的电脑会打不开** |
| `-AllowPublic` | 不改网络类型，让防火墙规则在公用网络也生效（仅同网段）。连公共 WiFi 时陌生人也能看到登录页，不推荐 |
| `-SkipFont` / `-SkipWslConfig` | 跳过装字体 / 跳过 WSL 网络设置 |

中间会弹出一次 UAC（管理员确认），点"是"。完成后：

1. **Windows Terminal 设置字体**：`Ctrl+,` → 默认值 → 外观 → 字体选 **JetBrainsMono Nerd Font Mono**
2. **重启 WSL**：PowerShell 运行 `wsl --shutdown`，再打开 Ubuntu

### 第 2 步：Ubuntu 里安装

打开 Ubuntu，进入这个文件夹（Windows 的 `D:\` 在 Ubuntu 里是 `/mnt/d/`）：

```bash
cd /mnt/d/tmux-nvim-kit
./install.sh --proxy http://127.0.0.1:7890 --password 你的密码
```

| 参数 | 作用 |
|---|---|
| `--password <密码>` | 浏览器访问密码（不填会随机生成，装完显示） |
| `--user <用户名>` | 浏览器登录用户名（默认是 Ubuntu 用户名） |
| `--port <端口>` | 浏览器访问端口（默认 7681） |
| `--proxy <地址>` | 代理，如 Clash 的 `http://127.0.0.1:7890`。Java/Maven 默认不走系统代理，用了这个参数才会走；不填时，浏览器里的 tmux 沿用安装时终端里的代理 |
| `--maven-settings <路径>` | 复制一份公司的 Maven 配置，如 `/mnt/c/Users/你的名字/.m2/settings.xml` |
| `--no-web` | 不装浏览器访问 |
| `--no-windows-path` | Ubuntu 不再继承 Windows 的 PATH（命令查找更快，避免误用 Windows 版程序）；需 `wsl --shutdown` 后生效 |

安装大约 20～30 分钟（主要是下载，取决于网速），装完会显示浏览器访问地址和账号。

> 已有的 `~/.config/nvim`、`~/.tmux.conf` 等会自动备份成 `xxx.bak.时间`，不会丢。

---

## 二、日常使用

### 打开项目

```bash
tmux new -A -s code              # 进入 code 会话（浏览器看到的就是它；已存在则直接进入）
cd /mnt/d/work/你的项目           # 进入项目根目录（pom.xml 所在那层）
nvim .                           # 打开
```

第一次打开某个 Java 项目，状态栏右侧会显示黄色的 `项目导入中 xx%`（jdtls 在导入 Maven 项目），消失后跳转才完整可用（大项目 1～3 分钟）。

### Neovim：快捷键和 IDEA（Windows 默认键位）一致

和 Vim 原有按键冲突时以 IDEA 为准。终端有几条限制：

- **`Ctrl+Shift+字母` 和 IDEA 一样可用**（`Ctrl+Shift+F` 全局搜索、`Ctrl+Shift+N` 找文件等）：
  - 浏览器里直接可用（页面已处理，刷新一次网页）
  - Windows Terminal 里需要运行一次 `powershell -ExecutionPolicy Bypass -File windows\wt-keys.ps1`（不需要管理员，会先备份设置）
  - 例外：`Ctrl+Shift+V` / `Ctrl+Shift+C` 仍是终端的粘贴 / 复制；浏览器里 `Ctrl+Shift+N` / `T` / `W` 被浏览器占用
  - 以上不可用时，对应的 `Alt+Shift+字母` 功能完全相同，作为备用
- **`Ctrl+B` 是 tmux 前缀**：跳转到声明要连按两次 `Ctrl+B`，或按住 `Ctrl` / `Alt` 鼠标点击
- **浏览器会抢走 `Ctrl+N`、`Ctrl+W`、`Ctrl+T`、`Ctrl+Tab`**（新窗口、关标签页等）：只能在 Windows Terminal 里用，`Ctrl+N` 在浏览器里用 `Alt+N` 代替。千万别在浏览器里按 `Ctrl+W`，会关掉网页
- **无法实现**：双击 Shift（用 `Alt+Shift+N` 找文件）、`Ctrl+I`（终端里等同 Tab）、`Ctrl+Alt+M`（等同 `Alt+Enter`，选中代码后 `Alt+Enter` 菜单里有提取方法）
- **Windows Terminal 默认把 `Alt+Enter` 当作全屏切换**，上面的 `wt-keys.ps1` 会一并去掉这个设置

| 分类 | 快捷键 |
|---|---|
| 编辑 | `Ctrl+S` 保存、`Ctrl+Z` 撤销、`Alt+Shift+Z` 重做、`Ctrl+C`/`X`/`V` 复制/剪切/粘贴（不选中时整行）、`Ctrl+D` 复制行、`Ctrl+Y` 删除行、`Ctrl+/` 注释、`Ctrl+A` 全选、`Ctrl+W` 扩大选区、`Shift+方向键` 选择、`Alt+Shift+↑/↓` 移动行、`Alt+Shift+J` 合并行、`Alt+Shift+U` 大小写 |
| 代码 | `Alt+Enter` 意图操作、`Alt+Insert` 生成、`Ctrl+O` 重写方法、`Shift+F6` 重命名、`Ctrl+Alt+V`/`C` 提取变量/常量、`Ctrl+Alt+N` 内联、`Ctrl+Alt+L` 格式化、`Ctrl+Alt+O` 整理 import、`Ctrl+Alt+I` 自动缩进 |
| 跳转 | `Ctrl+B` 声明、`Ctrl+Alt+B` 实现、`Alt+Shift+B` 类型声明、`Ctrl+U` 父类方法、`Alt+F7` 查找用法、`Ctrl+H` 类型层级、`Ctrl+Alt+H` 调用层级、`Ctrl+Alt+←/→` 后退/前进、`Alt+↑/↓` 上/下一个方法、`F2`/`Shift+F2` 下/上一个问题、`Ctrl+G` 跳转到行 |
| 查找 | `Ctrl+N` 类、`Alt+Shift+N` 文件、`Alt+Shift+A` 操作、`Ctrl+E` 最近文件、`Alt+Shift+E` 最近位置、`Ctrl+F12` 文件结构、`Ctrl+F`/`Ctrl+R` 文件内查找/替换、`F3`/`Shift+F3` 下/上一个、`Alt+Shift+F`/`Alt+Shift+R` 全局查找/替换、`Alt+Shift+V` 复制历史 |
| 文档 | `Ctrl+Q` 文档、`Ctrl+P` 参数信息、`Alt+Shift+I` 快速查看定义 |
| 窗口 | `Alt+←/→` 切换标签页、`Ctrl+F4` 关闭标签页、`Alt+1` 文件树、`Alt+F1` 定位当前文件、`Alt+6` 问题、`Alt+7` 结构、`Alt+9` / `Ctrl+K` Git、`Alt+F12` 终端、`Ctrl+Shift+F12` 最大化编辑区 |

被替换掉的 Vim 原有按键：翻页用 `PageUp`/`PageDown` 或鼠标滚轮，块选择用 `Alt+Shift+Insert`，窗口切换用鼠标点击或 `空格 w`。`gd`、`gr`、`空格` 开头的组合键等其余 Vim / LazyVim 按键照常可用。

**横向看长代码**：和 IDEA 一样 `Shift+滚轮` 左右滚动（触控板直接左右滑也可以），滚动的是鼠标所在的窗口，编辑区和弹框里的预览都适用；也可以 `空格 u w` 切换自动折行。Markdown、文本文件默认折行显示，不需要横向滚动。

**跳转弹框**：跳转到定义 / 实现、查找用法等有多个结果时，会弹出上面是结果列表、下面是几乎全屏代码预览的弹框（超长的行自动折行），`↑`/`↓` 选择，回车跳转，`Ctrl+F`/`Ctrl+B` 或鼠标滚轮滚动预览，`Esc` 关闭。

**在文件中查找（`Ctrl+Shift+F`）**：和 IDEA 一样上方输入、中间结果列表、下方预览，默认按普通文字、不区分大小写搜索；`Alt+C` 区分大小写、`Alt+W` 整词、`Alt+X` 正则（打开的开关显示在标题栏）；回车打开，`Esc` 关闭。限定文件类型：输入 `关键字 -- -g *.java`。选中文字后按会直接搜索选中内容。

**查找（`Ctrl+F`）**：和 IDEA 一样在编辑区右上角弹出查找栏，边输入边高亮全部匹配并显示 `3/12`；回车 / `F3` / `↓` 下一个，`↑` / `Shift+F3` 上一个；`Alt+C` 区分大小写、`Alt+W` 整词、`Alt+X` 正则，`Ctrl+R` 转到替换；`Esc` 关闭，光标停在当前匹配处。找不到时显示"0 个结果"，不会报错。再次打开时会预填上次的内容并选中，直接输入即可替换。

**粘贴**：Windows Terminal 和浏览器里 `Ctrl+V` 都直接粘贴系统剪贴板（编辑器里 `y` / `Ctrl+C` 复制的内容也会进入系统剪贴板）；`Ctrl+Shift+V` 同样可以粘贴。

退出：`:qa`。

**不知道怎么操作时**：按 `空格 h`（或 `F1`）打开中文帮助，会根据当前所在窗口（文件树、搜索窗口、Java 文件、Markdown 等）列出常用操作；在帮助里按 `a` 查看当前窗口的全部快捷键。按 `空格` 稍等也会弹出快捷键菜单，所有说明都是中文。

**文件树**：`Enter`/`→` 打开或展开、`←` 折叠、直接打字过滤、`a`/`d`/`r` 新建/删除/重命名、`?` 查看全部按键。

**Markdown**：直接显示渲染后的效果；按 `i` 编辑时显示源码，`空格 u m` 切换。

### tmux：前缀键 `Ctrl+b`（先按 Ctrl+b，松开，再按后面的键）

| 操作 | 按键 |
|---|---|
| 新建窗口（每个项目一个） | `前缀 c` |
| 切换窗口 | `前缀 1~9`、`前缀 n`/`p`、`前缀 w`（列表选择） |
| 左右 / 上下分屏 | `前缀 %` / `前缀 "` |
| 在分屏间移动 | 鼠标点击，或 `前缀 方向键` |
| 放大/还原当前分屏 | `前缀 z` |
| 列出/切换会话 | `前缀 s` |
| 暂时离开（程序继续运行） | `前缀 d`，回来用 `tmux new -A -s code` |
| 关闭当前分屏 / 窗口 | `前缀 x` / `前缀 &`，然后按 `y` 确认 |
| 重新加载配置 | `前缀 r` |
| 打开面板里的链接 | `前缀 u`（列出最近的链接，选中后在 Windows 浏览器打开） |

分屏时每个面板顶部会显示编号和项目名；底部状态栏的窗口名自动显示为项目目录名。窗口处于放大状态时，窗口名后会显示 `[已放大 前缀z还原]`。

> 按 tmux 快捷键时请切到**英文输入法**，中文输入法下 `%`、`"`、`&` 等符号会变成全角字符，tmux 识别不了。

鼠标拖选文字时会进入 tmux 的**复制模式**（面板右上角出现 `[0/28]` 这样的行号），此时按 `Ctrl+C` 复制；复制模式下键盘输入不会传给程序，**单击一下面板或按 `Esc`** 即可退出。

Claude Code、Neovim 这类自己处理鼠标的程序里，拖选交给程序本身，不会进入 tmux 复制模式。任何时候都可以**按住 `Shift` 拖选**：浏览器里松开鼠标即复制，Windows Terminal 里再按 `Ctrl+Shift+C`。

### 浏览器访问

```bash
tmux-web-ctl url                 # 显示访问地址、用户名、密码
```

- 本机：`http://localhost:7681`；内网其他设备：`http://<本机内网IP>:7681`
- 浏览器里看到的就是 `code` 会话，和本地终端同一个画面，两边实时同步
- 注意：`Ctrl+W`、`Ctrl+T` 会被浏览器截走（关闭/新建标签页），Neovim 里的窗口操作改用 `空格 w`
- 复制：Neovim 里 `y`、tmux 复制模式里 `Ctrl+C` 复制的内容会进入**当前设备**的剪贴板；`Shift+拖选` 松开即复制，选中后 `Ctrl+Shift+C` 也可以
- 浏览器不允许程序随时写剪贴板，偶尔会提示"点一下页面或按任意键完成复制"，照做即可
- 粘贴：`Ctrl+V` 或 `Ctrl+Shift+V`，粘贴的是当前设备的剪贴板

管理命令：

```bash
tmux-web-ctl passwd 新密码        # 改密码
tmux-web-ctl port 8080           # 改端口（Windows 防火墙需重新运行 setup.ps1 -Port 8080）
tmux-web-ctl font 16             # 改浏览器字号
tmux-web-ctl proxy http://127.0.0.1:7890   # 浏览器里 tmux 中程序联网用的代理（off 关闭）
tmux-web-ctl dir ~/project       # 新建 tmux 会话时的起始目录（建议用 WSL 里的项目目录）
tmux-web-ctl status | restart | stop | start
```

### 在 tmux 里用 Claude Code

```bash
curl -fsSL https://claude.ai/install.sh | bash
```

- 在 tmux 里 `Shift+Enter` 换行已配置好（Windows Terminal 中有效；浏览器里用 `\` + Enter）
- Claude Code 的 `Ctrl+b`（转后台）会被 tmux 截走，要**连按两次 `Ctrl+b`**
- 推荐布局：`前缀 %` 分屏，左边 nvim 看代码，右边 `claude`
- 离开电脑时想知道 Claude 什么时候跑完：配合 [claude-code-wecom-notify](https://github.com/caokang1/claude-code-wecom-notify)，回答完成后推送提醒到企业微信 / 飞书
- 打开 Claude 给出的链接（在线文档等）：Claude 会自动用 Windows 默认浏览器打开（安装时已设置 `BROWSER=win-open`，旧终端需重新打开）；手动打开用 `前缀 u` 选择，或在 Windows Terminal 里按住 `Ctrl+Shift` 单击链接

---

## 三、常见问题

**别人的电脑打不开网页，自己电脑可以**
Windows 把当前网络标记成了"公用网络"，防火墙规则不生效。重新运行 `windows\setup.ps1 -PrivateNetwork`，或在 Windows 设置 → 网络和 Internet → WLAN/以太网 → 网络配置文件类型 选"专用网络"。另外确认本机 IP 没变（`ipconfig`）。

**电脑重启后网页打不开**
浏览器访问服务随 Ubuntu 启动，先打开一次 Ubuntu 终端即可。检查：`tmux-web-ctl status`。

**浏览器里 Claude Code 连不上（`ECONNRESET`、一直重试），Windows Terminal 里正常**
- 原因：WSL 只给从 Windows 打开的终端自动设置代理（`.wslconfig` 的 `autoProxy`），浏览器里的 tmux 由系统服务启动，拿不到代理
- 解决：`tmux-web-ctl proxy http://127.0.0.1:7890`（换成你的代理地址），然后退出 claude，在新窗口（`前缀 c`）重新运行 `claude --continue`
- 网页本身打不开、报 502：浏览器访问 `localhost` / 内网 IP 也走了代理，在 Clash 等代理软件的绕过列表里加上 `localhost`、`127.0.0.1`、`192.168.*`

**浏览器里复制 / 粘贴不了**
- 复制：在 Claude Code、Neovim 里用 `Shift+拖选`，松开即复制；提示"点一下页面或按任意键完成复制"时照做
- 粘贴：`Ctrl+V` 或 `Ctrl+Shift+V`；仍不行的话检查浏览器是否禁止了该网站的剪贴板权限
- 旧版安装需更新网页：重新运行 `install.sh`

**按 `前缀 %` 没有分屏**
- 先看状态栏窗口名后有没有 `[已放大 前缀z还原]`：窗口被放大（`前缀 z`）时只显示一个面板，其实已经分屏了，按 `前缀 z` 还原
- 确认是英文输入法，中文输入法下 `Shift+5` 打出的是全角 `％`

**鼠标点了面板却无法输入**
该面板停在了复制模式（右上角有行号提示），单击一下面板或按 `Esc` 退出。旧版配置单击不会退出，重新运行 `install.sh` 或更新 `~/.tmux.conf` 即可。

**Claude Code 里的链接打不开 / 没有跳转到浏览器**
- 原因：Ubuntu 不继承 Windows 的 PATH 时（`--no-windows-path`），WSL 里找不到浏览器；tmux 开着鼠标模式，直接单击链接会被 tmux 接走
- `echo $BROWSER` 应显示 `~/.local/bin/win-open`；没有的话重新运行 `install.sh`，或在 `~/.bashrc` 加 `export BROWSER="$HOME/.local/bin/win-open"`，然后**退出并重新启动 claude**
- 手动打开：`前缀 u` 弹出链接菜单；或 `Ctrl+Shift+单击`（Windows Terminal）；或 `win-open 链接`

**Neovim 里退不出当前文件**
- 先按 `Esc`，确认左下角是 `NORMAL`：在 `INSERT` 模式下按的 `:q` 只会被当成文字打进去
- 本配置已把录宏从 `q` 改到 `Q`（`Q` + 寄存器开始，再按 `Q` 停止），单按 `q` 不会再误录宏；右下角出现 `recording @x` 时按 `Q` 停止
- 文件改过没保存（标签上有 `●`）时 `:q` 会被拒绝：`:q!` 不保存退出，`:wq` 保存退出，`:qa!` 全部不保存直接退出 Neovim

**打开大项目后整个窗口卡住很久**
项目放在 Windows 盘（`/mnt/c`、`/mnt/d`）时，WSL 读写要经过跨系统的文件共享，比 WSL 自己的磁盘慢十倍以上；jdtls 分析整个项目、文件树刷新状态时会大量读文件，Neovim 会长时间无响应。把项目放到 WSL 里（如 `~/project`）即可：

```bash
rsync -a --exclude='target/' --chmod=D755,F644 /mnt/d/项目/ ~/项目/   # target 是编译产物，不用复制
cd ~/项目 && git config core.autocrlf true   # Windows 上检出的文件是 CRLF 换行，不设置 git 会认为全部文件都改了
```

Windows 里的 IDEA 等工具可以通过 `\\wsl$\Ubuntu\home\<用户名>\项目` 访问 WSL 里的项目。

**Java 跳转不可用 / 一直在导入**
- 确认在项目根目录（`pom.xml` 所在层）打开 `nvim .`
- 依赖下载失败多半是网络：公司 Nexus 或 Maven 中央仓库要走代理时，安装时加 `--proxy`；查看 `~/.m2/settings.xml` 里的 `<proxies>`
- 清掉 jdtls 缓存重来：`rm -rf ~/.cache/nvim/jdtls/项目名`

**图标显示成方框或乱码**
终端字体没设成 Nerd Font。Windows Terminal → 设置 → 默认值 → 外观 → 字体 选 `JetBrainsMono Nerd Font Mono`（字体由 setup.ps1 安装，找不到就注销重新登录一次）。

**项目里出现 `.project`、`.classpath`、`.settings`**
本套配置已让 jdtls 不再生成这些文件。以前生成的可以直接删除。

**想换回原来的 Neovim / tmux 配置**
安装时的备份在 `~/.config/nvim.bak.时间`、`~/.tmux.conf.bak.时间` 等，删掉新配置、把备份改回原名即可。

---

## 四、卸载

```bash
sudo systemctl disable --now tmux-web
sudo rm -f /etc/systemd/system/tmux-web.service /usr/local/bin/tmux-web /usr/local/bin/tmux-web-ctl
rm -rf ~/.config/tmux-web ~/.config/nvim ~/.local/share/nvim ~/.local/state/nvim ~/.cache/nvim ~/.tmux.conf
```

Windows 端：防火墙里删除名为 `tmux-web 7681` 的规则（`Remove-NetFirewallRule -DisplayName 'tmux-web 7681'`，管理员 PowerShell）。

---

## 目录说明

```
install.sh            Ubuntu 端一键安装
windows/setup.ps1     Windows 端：字体、WSL 镜像网络、防火墙
windows/wt-keys.ps1   Windows Terminal：让 Ctrl+Shift+字母、Alt+Enter 交给编辑器（IDEA 快捷键）
config/nvim/          Neovim 配置（LazyVim），lazy-lock.json 锁定插件版本
  lua/plugins/theme.lua      IDEA 配色
  lua/plugins/java.lua       jdtls 设置（内存、下载源码、不生成 Eclipse 元数据）
  lua/plugins/lang.lua       各语言语法解析与语言服务
  lua/plugins/idea-ui.lua    IDEA 式界面行为
  lua/plugins/explorer.lua   文件树
  lua/plugins/markdown.lua   Markdown 渲染
  lua/config/idea_keys.lua   IDEA 快捷键（Windows 默认键位）
  lua/config/find_bar.lua    Ctrl+F 查找栏
  lua/config/zh*.lua         中文按键提示、F1 帮助面板
config/tmux.conf      tmux 配置
bin/win-open          用 Windows 默认浏览器打开链接（BROWSER 变量指向它）
bin/tmux-open-url     tmux 前缀 u：列出面板里的链接并打开
web/                  浏览器访问（ttyd）：启动脚本、systemd 服务、管理命令、嵌入字体的网页生成
```

## License

MIT
