# IDEA 看代码体验增强：文件查看与代码跳转

日期：2026-11-04

## 一、为什么做

tmux-nvim-kit 的定位是"像 IDEA 一样好用的轻量看代码环境"。用户是 Java 程序员，反馈日常最不顺手的两件事：

1. **看具体文件**：Java、Markdown 等文件打开后，不如 IDEA 好读
2. **代码跳转**：不如 IDEA 顺手

用户没有回忆起具体哪一步卡住，把方案交给了我们来定。下面所有具体功能都是**我们的判断**：逐一对照 IDEA 的同名功能，补上目前缺失或做得不像的部分。

成功的标准：一个习惯 IDEA 的 Java 程序员读一个陌生的 Spring Boot + MyBatis 项目时，**从入口追到实现、从实现回到调用方，全程不用想"这个在 nvim 里怎么做"**。

## 二、目标 / 非目标 / 反目标

**目标**
- 跳转：按 IDEA 的按键得到 IDEA 的结果，包括它的"聪明行为"（在声明处按 Ctrl+B 显示用法、左侧图标点击跳到实现/父类等）
- 层级/用法：类型层级、调用层级、查找用法改为 IDEA 那样的**可展开树**，而不是一次性的平铺列表
- Java 生态：Spring 接口地址搜索、MyBatis Mapper ↔ XML 互跳、配置项 ↔ 代码互跳
- 文件查看：Java 文件默认折叠 import；Markdown 链接可点击跳转、有大纲；依赖库/反编译文件标签显示类名
- 与右侧 Claude Code 配合：Claude 输出里的 `文件:行号`、Java 异常堆栈，可以一键在左侧 nvim 打开

**非目标**
- 运行、调试、测试运行器、构建（用户明确不做）
- 代码编辑能力的增强（重构、补全等保持现状）
- 支持 Java 以外语言的同等深度

**反目标**（做了也算失败）
- 打开文件或跳转明显变慢（大项目里每次跳转多等 1 秒以上）
- 破坏现有的 IDEA 键位、浏览器访问、中文帮助
- 新增的东西没有中文说明，用户不知道怎么用
- 为了一个功能引入需要额外系统依赖、install.sh 装不上的插件

## 三、约束

- Neovim 0.11+、LazyVim、snacks.nvim 作为 picker；jdtls 由 nvim-jdtls 提供（见 `config/nvim/lua/plugins/java.lua`）
- 运行环境：WSL + tmux，Windows Terminal 和浏览器（ttyd）两种终端都要能用；浏览器会抢 Ctrl+N/W/T
- 所有新按键要遵循 `config/nvim/lua/config/idea_keys.lua` 的约定：IDEA Windows 默认键位优先；Ctrl+Shift+字母 同时提供 Alt+Shift+字母 备用
- 所有新功能要进中文帮助（`config/nvim/lua/config/zh_help.lua`）、which-key 中文说明，README 快捷键表同步更新
- 新插件要写进 `lazy-lock.json`，install.sh 一次装好，无需额外手工步骤

**按键冲突规则（我们的决定）**：不占用 Windows Terminal / 浏览器自身的功能键（F11 全屏、Ctrl+-/=/0 缩放、Ctrl+Shift+V/C），也不覆盖 LazyVim 和 tmux 已有的按键；冲突时改用 Alt 组合或 `空格` 开头的组合。需要 Ctrl+Shift 组合（如 Ctrl+Shift+Space）时，同步修改 `windows/wt-keys.ps1` 和 `web/build_index.py`，属于本次范围。

## 四、功能清单（按优先级分三批）

### 第一批：跳转本身顺手

**1.1 Ctrl+B 单按即可跳转（我们的决定）**
现在 Ctrl+B 是 tmux 前缀，在 nvim 里要连按两次。方案：tmux 里 `bind -n C-b`，若当前面板运行的是 nvim，就把 Ctrl+B 直接发给 nvim；其他面板仍作为 tmux 前缀。同时增加第二前缀 `Ctrl+Space`（`prefix2`），任何面板都能用，nvim 面板里用它代替 Ctrl+B 做 tmux 操作。README、tmux 中文速查表、Claude Code 说明里"连按两次 Ctrl+B"的描述同步改掉。
判断"当前面板是 nvim"用 `#{pane_current_command}`；nvim 里开的终端（Alt+F12）中按 Ctrl+B 会被 nvim 收到，需在 nvim 终端模式把 Ctrl+B 透传给 tmux 前缀或给出替代——由实现者决定细节。

**1.2 在声明处按 Ctrl+B 显示用法**
IDEA：光标已在方法/类/字段的声明上时，Ctrl+B 弹出用法列表。现在会"跳到自己"。实现：定义结果与光标位置相同时，改调查找用法。

**1.3 左侧图标：已实现 / 重写 / 被重写（IDEA gutter icons）**
在 Java 文件行号旁显示：接口方法"有实现 ↓"、实现方法"实现了接口 ↑"、重写方法"重写了父类 ↑"、被子类重写"↓"。鼠标点击图标或光标在该行按 Ctrl+U（父类）/ Ctrl+Alt+B（实现）跳转。数据来源：jdtls（implementation / super_implementation / type hierarchy）。要求：**只计算可见范围内的方法、异步、带缓存**，不能拖慢打开文件。

**1.4 查找用法面板（IDEA 的 Find 工具窗口）**
Alt+F7：在底部打开持久面板，用法按 **模块/包 → 文件 → 行** 分组成树，区分"读/写"（字段）、"测试代码/生产代码"；Enter 跳转但面板保留，可连续逐个查看；Ctrl+Alt+↑/↓ 上/下一个用法（IDEA 同键）。Ctrl+Alt+F7 保留现在的弹框（快速查看）。

**1.5 类型层级 / 调用层级为可展开树**
- Ctrl+H：类型层级树，可切换"父类型 / 子类型 / 完整层级"
- Ctrl+Alt+H：调用层级树，可切换"谁调用了它 / 它调用了谁"，节点可以逐层展开（现在只有一层）
- 两者均为侧边/底部面板，带代码预览，Enter 跳转

**1.6 书签（IDEA Bookmarks）**
F11 / Shift+F11 在 Windows Terminal 和浏览器里是全屏，**不占用**（见第三节按键冲突规则）→ **我们的决定**：`Alt+F11` 切换书签，`Ctrl+F11` 带助记符（0-9/A-Z），`Alt+Shift+F11` 书签列表；`空格 m` 开头提供同样功能作为备用。按项目保存，重开 nvim 仍在。

**1.7 依赖库和反编译文件**
跳进 jar 里的类（`jdt://` 缓冲区）后：标签页显示类名（如 `ArrayList.class`）而不是长 URI；面包屑显示所属 jar；在这类文件里 Ctrl+B / Alt+F7 照常可用；Alt+F1 提示"依赖库文件，不在项目中"而不是报错。

**1.8 Search Everywhere（双击 Shift 的替代）**
一个统一入口：类、文件、符号、操作、最近文件一起搜，Tab 切换分类（IDEA 同款）。终端里无法检测双击 Shift → **我们的决定**：映射为 `Ctrl+Shift+Space`（和 Ctrl+Shift+字母 一样由 `wt-keys.ps1` 和浏览器页面发出可区分编码），不覆盖 LazyVim 原有的 `空格 空格`（查找文件），备用键为 `空格 s e`。Ctrl+N 增加"包含依赖库中的类"开关（IDEA 再按一次 Ctrl+N）。

### 第二批：Java / Spring 生态

**2.1 接口地址搜索（IDEA Endpoints / RestfulTool）**
快捷键 Ctrl+Alt+N 已被"内联"占用 → **我们的决定**：`Ctrl+\`（IDEA RestfulTool 插件默认键）。输入 `/api/user/list` 或片段，列出匹配的 Controller 方法（解析 `@RequestMapping/@GetMapping/...` 及类上的前缀，支持常量拼接的简单情形），预览并跳转。用 ripgrep + treesitter 解析，不依赖项目编译。

**2.2 MyBatis Mapper 接口 ↔ XML 互跳（MyBatisX）**
- Mapper 接口方法左侧图标，点击/Ctrl+B 跳到 XML 中对应 `<select id=...>`
- XML 中 `id="xxx"`、`namespace` 上 Ctrl+B 跳回接口/方法；`resultMap`、`<include refid>` 在 XML 内跳转
- 匹配规则：XML `namespace` = 接口全限定名

**2.3 配置项 ↔ 代码**
- `application.yml/properties` 中的配置键上 Ctrl+B / Alt+F7：列出 `@Value("${key}")`、`@ConfigurationProperties(prefix)` 字段的使用处
- 代码中 `@Value("${key}")` 上 Ctrl+B：跳到各 profile 配置文件中的定义

**2.4 Spring Bean 跳转**
`@Autowired`/构造注入的接口字段上 Ctrl+Alt+B 跳到实现类（jdtls implementation 已支持，此项主要是确认可用并加左侧图标）。

### 第三批：文件查看 + 与 Claude 配合

**3.1 Java 文件阅读**
- 打开 Java 文件时 import 块默认折叠（IDEA 默认行为），显示 `import ...` 一行
- Ctrl+-/=（字号缩放）不占用 → **我们的决定**：`Alt+-` / `Alt+=` 折叠/展开当前块，`Alt+Shift+-` / `Alt+Shift+=` 全部折叠/展开；`za`/`zM`/`zR` 等 Vim 原有按键照常可用
- Ctrl+F12 文件结构弹框：可输入过滤；再按一次 Ctrl+F12 显示继承来的成员（IDEA 同款）

**3.2 Markdown 阅读**
- 渲染状态下 Ctrl+点击 / Ctrl+B 打开链接：相对路径文件、`#锚点`、`文件.md#锚点`、URL（URL 用 Windows 浏览器）
- Ctrl+F12 / Alt+7 显示标题大纲，可跳转
- 代码块里的 `类名`、`路径:行号` 不做特殊处理（非目标）

**3.3 从 Claude Code / 日志直接在 nvim 打开（IDEA 的"分析堆栈"）**
- 每个 nvim 启动时以项目对应的 socket 监听（`--listen`），记录在 tmux 窗口选项里
- tmux `前缀 j`（**我们的决定**，不占用 tmux 原有的 `前缀 o` 切换面板）：在当前窗口其他面板的可见内容里提取 `路径:行号`、`路径#L行号`、Java 堆栈行 `at com.x.Foo.bar(Foo.java:42)`，列出供选择，选中后在同窗口的 nvim 里打开并定位到行（堆栈行按类名在项目中解析文件）。socket 按**面板**登记；窗口里有多个 nvim 时用最近活动的那个，一个都没有时提示"当前窗口没有打开的 nvim"，不自动启动
- nvim 内 `空格 j s`：粘贴一段堆栈，转成可跳转的列表（IDEA Analyze Stack Trace）

### 第四批：补充功能（用户确认"按推荐的来"）

**4.1 复制引用（IDEA Copy Reference，Ctrl+Alt+Shift+C）**
弹出选择：`相对路径:行号`、`绝对路径:行号`、`全限定名#方法`（Java，用 treesitter 取包名/类名/方法名）、`文件名`。复制到系统剪贴板（浏览器里进入当前设备剪贴板，沿用现有 OSC52 机制）。终端里 Ctrl+Alt+Shift+C 不一定可区分 → 备用 `空格 c r`（**我们的决定**）。

**4.2 选中代码发送给 Claude**
可视模式 `空格 a s`（**我们的决定**）：把 `@相对路径#L起-止` 加选中代码粘贴到同 tmux 窗口中运行 claude 的面板输入框（不按回车，由用户补充问题后自己发送），并切换焦点到该面板。找不到 claude 面板时提示。普通模式下只发送 `@相对路径#L行号`。

**4.3 文件树压缩空包（IDEA Compact Middle Packages）**
只有一个子目录、没有文件的目录链合并显示为一个节点，如 `src/main/java/com/example/demo`。展开/折叠作用于整个链。

**4.4 全局搜索限定范围（IDEA Find in Files Scope）**
在 Ctrl+Shift+F 弹框中 `Alt+S` 切换范围：整个项目 / 当前模块（离当前文件最近的 pom.xml 所在目录）/ 当前目录 / 自选目录；`Alt+T` 切换排除测试代码（`src/test/**`）。默认排除 `target/`、`node_modules/`、`.git/`。当前范围显示在标题栏。

**4.5 Git Annotate（IDEA Annotate with Git Blame）**
`Alt+Shift+G`（**我们的决定**，IDEA 无默认键）或右键菜单：在左侧显示每行作者和日期（gitsigns blame），再按关闭；在注释栏上按回车查看该提交的改动。

**4.6 properties 中的 Unicode 转义显示为中文（IDEA Transparent native-to-ascii）**
打开 `*.properties` 时，`\uXXXX` 用 conceal/虚拟文本显示为对应字符；编辑时（插入模式所在行）显示原文；文件内容不改写。

## 五、实现方式（已定的部分）

- 新功能以独立 Lua 模块放在 `config/nvim/lua/config/`（如 `usages_tree.lua`、`gutter.lua`、`spring.lua`、`mybatis.lua`），按键统一在 `idea_keys.lua` 注册
- 能用现有插件就不自己写；可选的候选（由实现者评估取舍）：树形用法/层级可考虑 `trouble.nvim`（已安装）的自定义 source 或自写树视图；书签可考虑 `bookmarks`/`arrow` 类插件；不得引入需要 Node/Python 额外安装的插件
- **多轮 agent 循环开发**（用户授权）：每批拆成若干独立功能，每个功能一轮：实现 → 用 headless nvim 在一个示例 Spring Boot + MyBatis 项目上自动验证 → 修复 → 下一轮。每轮结束提交一次 commit
- 验证用示例项目放在 `test/fixtures/`（小型 Spring Boot + MyBatis，含接口/实现/继承/Controller/Mapper XML/yml），不进 install。**我们的决定**：它是能被 jdtls 真实导入的 Maven 项目；依赖下载一次后缓存在 `~/.m2`，headless 测试先等待 jdtls 导入完成（超时 5 分钟）再验证跳转类功能；纯文本解析类功能（接口地址、MyBatis、配置项、Markdown、堆栈）不依赖 jdtls，可单独快速测试

## 六、留给实现者

- 每个功能的具体插件选型与数据结构
- 树形面板的具体外观（以 IDEA 为参照，配色沿用 `theme.lua`）
- 性能手段（缓存、节流、只算可见区）
- headless 测试的写法
- 1.1 中 nvim 内置终端如何处理 Ctrl+B
