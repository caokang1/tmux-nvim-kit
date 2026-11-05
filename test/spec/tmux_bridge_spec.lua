-- tmux_bridge：Ctrl+B / 第二前缀 / 前缀 j 的 tmux 绑定，tmux-jump 和 Lua 两套解析，open()，发送给 Claude Code
-- 用独立的 tmux 服务器（tmux -L kit-test），不碰用户正在用的 tmux；最后一个用例关闭它
local B = require("config.kit.tmux_bridge")
local root = vim.env.NVIM_KIT_ROOT
local JUMP = root .. "/bin/tmux-jump"
local SOCK = "kit-test"
local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")

local function sh(cmd, opts)
  local r = vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {})):wait(20000)
  return r.stdout or "", r.code, r.stderr
end
local function tm(...) return sh(vim.list_extend({ "tmux", "-L", SOCK }, { ... })) end

local CLAUDE_OUT = [[
● Read(demo-app/src/main/java/com/example/demo/controller/UserController.java)
  ⎿  Read 40 lines
● 问题在 demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java:26 这里，
  另见 @demo-app/src/main/java/com/example/demo/service/UserService.java#L5-12 和 README.md#L3
  编译错误：demo-app/src/main/java/com/example/demo/entity/User.java:10:15: error
  时间 10:00:01.456，访问 http://localhost:8080/a.js:10 或 https://x.com/b/c.java:3
  不存在的 nope/Missing.java:7，再次 demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java:26
	at com.example.demo.service.impl.UserServiceImpl.lambda$getUser$0(UserServiceImpl.java:27)
	at app//com.example.demo.controller.UserController$Inner.detail(UserController.java:31)
	at java.base/java.lang.Thread.run(Thread.java:840)
	at Foo.main(Foo.java:3)
]]
local claude_file = tmp .. "/claude.txt"
vim.fn.writefile(vim.split(CLAUDE_OUT, "\n"), claude_file)

-- Lua 解析结果转成和 tmux-jump --parse-only 一样的文本
local function lua_parse_lines(text)
  local out = {}
  for _, it in ipairs(B.recent_unique(B.parse(text))) do
    out[#out + 1] = table.concat({ it.kind, it.path, it.line, it.col, it.text }, "\t")
  end
  return out
end
local function lines_of(s) return vim.split(vim.trim(s), "\n", { trimempty = true }) end

-- 假的 Claude Code：命令名是 claude，打开括号粘贴，把收到的字节原样记到文件
local fake_dir = tmp .. "/bin"
vim.fn.mkdir(fake_dir, "p")
vim.fn.writefile({
  "import os, sys, tty",
  "out = open(sys.argv[1], 'ab', buffering=0)",
  "fd = sys.stdin.fileno()",
  "tty.setraw(fd)",
  "sys.stdout.write('\\x1b[?2004h'); sys.stdout.flush()",
  "while True:",
  "    b = os.read(fd, 4096)",
  "    if not b: break",
  "    out.write(b)",
}, fake_dir .. "/fake.py")
vim.uv.fs_symlink(vim.fn.exepath("python3"), fake_dir .. "/claude")

local panes = {}

return {
  ["1 tmux.conf：Ctrl+B 按面板分流、第二前缀 Ctrl+Space、前缀 j"] = function(t)
    sh({ "tmux", "-L", SOCK, "kill-server" })
    local _, code, err = sh({ "tmux", "-L", SOCK, "-f", root .. "/config/tmux.conf", "new-session", "-d", "-s", "spec",
      "-x", "200", "-y", "50", "-c", t.fixture, "sh", "-c", "cat logs/app.log; exec sleep 600" })
    t.eq(code, 0, "启动 kit-test 服务器失败：" .. err)
    t.eq(vim.trim(tm("show", "-gv", "prefix")), "None", "prefix")
    t.eq(vim.trim(tm("show", "-gv", "prefix2")), "C-Space", "prefix2")
    local root_cb = tm("list-keys", "-T", "root", "C-b")
    t.ok(root_cb:find("@nvim_socket", 1, true) and root_cb:find("send-keys C-b", 1, true)
      and root_cb:find("switch-client -T prefix", 1, true), "根按键表 C-b：" .. root_cb)
    t.ok(tm("list-keys", "-T", "prefix", "C-b"):find("send-keys C-b", 1, true), "前缀 C-b 应发送 C-b（Claude 转后台）")
    t.ok(tm("list-keys", "-T", "prefix", "j"):find("tmux-jump", 1, true), "前缀 j 未绑定")
    t.ok(tm("list-keys", "-T", "copy-mode", "C-b"):find("switch-client -T prefix", 1, true), "复制模式里 C-b 仍是前缀")
    t.ok(tm("list-keys", "-T", "copy-mode-vi", "C-b"):find("switch-client -T prefix", 1, true), "复制模式(vi)里 C-b 仍是前缀")
    t.ok(tm("list-keys", "-T", "prefix", "?"):find("tmux-help", 1, true), "前缀 ? 应保持")
    t.eq(vim.trim(tm("show", "-sv", "extended-keys")), "on", "extended-keys")
    -- 第二个面板当作 nvim 面板，第三个是假的 Claude Code
    panes.log = vim.trim(tm("display", "-p", "-t", "spec", "#{pane_id}"))
    panes.nvim = vim.trim(tm("split-window", "-t", "spec", "-P", "-F", "#{pane_id}", "sleep 600"))
    panes.claude = vim.trim(tm("split-window", "-t", "spec", "-P", "-F", "#{pane_id}", "-c", t.fixture,
      fake_dir .. "/claude", fake_dir .. "/fake.py", tmp .. "/claude.bytes"))
    t.ok(panes.nvim:match("^%%%d+$") and panes.claude:match("^%%%d+$"), "建面板失败")
  end,

  ["2 Lua 解析：日志里的 Java 堆栈"] = function(t)
    local items = B.parse(vim.fn.readfile(t.fixture .. "/logs/app.log"))
    t.eq(#items, 3, "堆栈行数")
    t.eq({ items[1].kind, items[1].path, items[1].file, items[1].line },
      { "java", "com/example/demo/service/impl/UserServiceImpl.java", "UserServiceImpl.java", 26 })
    t.eq(items[3].path, "org/springframework/web/servlet/FrameworkServlet.java")
  end,

  ["3 Lua 解析：Claude 输出（文件:行:列、#L、@引用、URL 和时间不误判、模块前缀、内部类）"] = function(t)
    local got = {}
    for _, it in ipairs(B.parse(CLAUDE_OUT)) do got[#got + 1] = it.kind .. " " .. it.path .. ":" .. it.line .. ":" .. it.col end
    t.eq(got, {
      "loc demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java:26:0",
      "loc demo-app/src/main/java/com/example/demo/service/UserService.java:5:0",
      "loc README.md:3:0",
      "loc demo-app/src/main/java/com/example/demo/entity/User.java:10:15",
      "loc nope/Missing.java:7:0",
      "loc demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java:26:0",
      "java com/example/demo/service/impl/UserServiceImpl.java:27:0",
      "java com/example/demo/controller/UserController.java:31:0",
      "java java/lang/Thread.java:840:0",
      "java Foo.java:3:0",
    })
    local uniq = B.recent_unique(B.parse(CLAUDE_OUT))
    t.eq(uniq[1].path, "Foo.java", "最近的在前")
    t.eq(#uniq, 9, "重复的 UserServiceImpl.java:26 只留一条")
  end,

  ["4 bash 解析（tmux-jump --parse-only）与 Lua 一致"] = function(t)
    for _, f in ipairs({ t.fixture .. "/logs/app.log", claude_file }) do
      local out, code = sh({ JUMP, "--parse-only", f })
      t.eq(code, 0, "tmux-jump 退出码")
      t.eq(lines_of(out), lua_parse_lines(vim.fn.readfile(f)), "两套解析结果不同：" .. f)
    end
  end,

  ["5 解析成真实文件：bash 与 Lua 一致，Java 堆栈按包路径找到项目里的文件"] = function(t)
    local out = sh({ JUMP, "--parse-only", claude_file, "--cwd", t.fixture, "--cwd", tmp })
    local bash = {}
    for _, l in ipairs(lines_of(out)) do
      local f, ln, col = unpack(vim.split(l, "\t"))
      bash[#bash + 1] = f:sub(#t.fixture + 2) .. ":" .. ln .. ":" .. col
    end
    local lua = {}
    for _, it in ipairs(B.resolve(B.recent_unique(B.parse(CLAUDE_OUT)), { t.fixture, tmp })) do
      lua[#lua + 1] = it.filename:sub(#t.fixture + 2) .. ":" .. it.line .. ":" .. it.col
    end
    local P = "demo-app/src/main/java/com/example/demo/"
    t.eq(bash, {
      P .. "controller/UserController.java:31:0",
      P .. "service/impl/UserServiceImpl.java:27:0",
      P .. "service/impl/UserServiceImpl.java:26:0",
      P .. "entity/User.java:10:15",
      P .. "service/UserService.java:5:0",
      "README.md:3:0",
    })
    t.eq(lua, bash, "Lua 和 bash 解析出的文件不同")
    -- 日志：Spring 的堆栈行不在项目里，不列出
    local log = lines_of(sh({ JUMP, "--parse-only", t.fixture .. "/logs/app.log", "--cwd", t.fixture }))
    t.eq(#log, 2, "日志可跳转的行数")
    t.ok(log[2]:find(P .. "service/impl/UserServiceImpl.java\t26\t0", 1, true), log[2])
  end,

  ["6 open_now / open：相对路径、行列定位，从浮窗里调用也打开在代码窗口"] = function(t)
    t.ok(B.open_now("demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java", 26, 0), "打开失败")
    t.ok(vim.api.nvim_buf_get_name(0):find("UserServiceImpl.java$"), "文件不对")
    t.eq(vim.fn.line("."), 26, "行")
    local fbuf = vim.api.nvim_create_buf(false, true)
    vim.bo[fbuf].buftype = "nofile"
    local fwin = vim.api.nvim_open_win(fbuf, true, { relative = "editor", row = 1, col = 1, width = 20, height = 5 })
    t.eq(B.open(t.fixture .. "/demo-app/src/main/java/com/example/demo/entity/User.java", 3, 5), "ok")
    t.wait(3000, function() return vim.api.nvim_buf_get_name(0):find("User.java$") ~= nil end, "open 异步打开")
    t.ok(not vim.api.nvim_win_is_valid(fwin), "浮窗应已关闭")
    t.eq(vim.api.nvim_win_get_cursor(0), { 3, 4 }, "行列")
    t.ok(not B.open_now(t.fixture .. "/nope.java", 1, 0), "不存在的文件返回 false")
  end,

  ["7 发送给 Claude 的文本格式"] = function(t)
    local base = "/home/u/proj"
    t.eq(B.claude_text(base .. "/src/A.java", base, 12, nil, nil, "java"), "@src/A.java#L12 ")
    t.eq(B.claude_text(base .. "/src/A.java", base, 3, 5, { "int a;", "  int b;", "}" }, "java"),
      "@src/A.java#L3-5\n```java\nint a;\n  int b;\n}\n```\n")
    t.eq(B.claude_text(base .. "/src/A.java", base .. "/", 7, 7, { "x" }, "java"), "@src/A.java#L7\n```java\nx\n```\n")
    t.eq(B.claude_text("/other/B.md", base, 1, 2, { "```sh", "ls", "```" }, "markdown"),
      "@/other/B.md#L1-2\n````markdown\n```sh\nls\n```\n````\n", "Claude 目录外用绝对路径；代码里有 ``` 时加长围栏")
    t.ok(B.is_claude("claude", "", nil))
    t.ok(B.is_claude("node", "", " node /usr/lib/node_modules/@anthropic-ai/claude-code/cli.js"))
    t.ok(B.is_claude("2.1.3", "✳ Claude Code", nil), "按标题识别")
    t.ok(not B.is_claude("bash", "kk@host: ~", nil))
    t.ok(not B.is_claude("node", "", " node server.js"))
  end,

  ["8 tmux：登记 socket、找 Claude 面板、括号粘贴发送"] = function(t)
    B.tmux_cmd = { "tmux", "-L", SOCK }
    B.pane = panes.nvim
    B.register(3000)
    t.eq(vim.trim(tm("show", "-pv", "-t", panes.nvim, "@nvim_socket")), vim.v.servername, "@nvim_socket")
    t.ok(tonumber(vim.trim(tm("show", "-pv", "-t", panes.nvim, "@nvim_focus"))), "@nvim_focus")
    -- 根按键表 C-b 的判断条件：登记了 socket 的面板算 nvim 面板，其他不算
    local cond = "#{||:#{@nvim_socket},#{m/r:^(n?vim|vi|view|nvimdiff)$,#{pane_current_command}}}"
    t.eq(vim.trim(tm("display", "-p", "-t", panes.nvim, cond)), "1", "nvim 面板")
    t.eq(vim.trim(tm("display", "-p", "-t", panes.claude, cond)), "0", "Claude 面板")

    t.wait(5000, function() return vim.trim(tm("display", "-p", "-t", panes.claude, "#{pane_current_command}")) == "claude" end,
      "假 Claude 启动")
    local id, cwd = B.find_claude_pane()
    t.eq(id, panes.claude, "Claude 面板")
    t.eq(cwd, t.fixture, "Claude 工作目录")
    local text = B.claude_text(t.fixture .. "/pom.xml", cwd, 1, 2, { "<a>", "</a>" }, "xml")
    t.ok(B.send_to_pane(id, text), "发送失败")
    t.wait(3000, function() return vim.fn.filereadable(tmp .. "/claude.bytes") == 1
      and table.concat(vim.fn.readfile(tmp .. "/claude.bytes", "b"), "\n"):find("\27%[201~") ~= nil end, "收到粘贴")
    local got = table.concat(vim.fn.readfile(tmp .. "/claude.bytes", "b"), "\n")
    t.eq(got, "\27[200~@pom.xml#L1-2\r```xml\r<a>\r</a>\r```\r\27[201~", "括号粘贴内容（tmux 把换行转成回车）")
    t.eq(vim.trim(tm("display", "-p", "-t", "spec", "#{pane_id}")), panes.claude, "焦点切到 Claude 面板")
  end,

  ["9 tmux-jump：找 nvim 面板、抓其他面板内容；--open 远程打开"] = function(t)
    local spath = vim.trim(tm("display", "-p", "#{socket_path}"))
    local env = { TMUX = spath .. ",0,0", TMUX_JUMP_DRY_RUN = "1" }
    local win = vim.trim(tm("display", "-p", "-t", panes.log, "#{window_id}"))
    local out, code, err = sh({ JUMP, win, panes.log, "" }, { env = env })
    t.eq(code, 0, err)
    local l = lines_of(out)
    t.eq(l[1], "nvim\t" .. panes.nvim .. "\t" .. vim.v.servername, "选中的 nvim 面板")
    t.ok(l[2] and l[2]:find("controller/UserController.java\t31\t0", 1, true), "最近的堆栈行在前：" .. out)
    t.ok(l[3] and l[3]:find("service/impl/UserServiceImpl.java\t26\t0", 1, true), "日志里的堆栈：" .. out)
    t.eq(#l, 3, "两个可跳转位置：" .. out)

    -- 没有 nvim 的窗口：提示（display-message 没有客户端时报错也不影响），不输出列表
    B.unregister(3000)
    out = sh({ JUMP, win, panes.log, "" }, { env = env })
    t.eq(vim.trim(out), "", "没有 nvim 时不应列出")
    B.register(3000)

    vim.cmd("enew")
    local p = vim.system({ JUMP, "--open", vim.v.servername, panes.nvim,
      t.fixture .. "/demo-app/src/main/java/com/example/demo/controller/UserController.java", "31", "0" },
      { env = { TMUX = spath .. ",0,0" } })
    t.wait(8000, function() return vim.api.nvim_buf_get_name(0):find("UserController.java$") ~= nil end, "远程打开")
    t.eq(vim.fn.line("."), 31, "行")
    t.eq(p:wait(5000).code, 0, "--open 退出码")
    t.eq(vim.trim(tm("display", "-p", "-t", "spec", "#{pane_id}")), panes.nvim, "焦点切到 nvim 面板")
  end,

  ["a 空格 j s：粘贴堆栈解析成快速修复列表"] = function(t)
    t.ok(vim.fn.maparg("<leader>js", "n") ~= "", "空格 j s 未映射")
    t.ok(vim.fn.maparg("<leader>as", "n") ~= "", "空格 a s（普通）未映射")
    t.ok(vim.fn.maparg("<leader>as", "x") ~= "", "空格 a s（可视）未映射")
    if vim.env.TMUX then t.ok(vim.fn.maparg("<C-b>", "t") ~= "", "终端模式 Ctrl+B 未映射") end
    local win = B.analyze_stack()
    t.eq(vim.bo.filetype, "kit_stack", "粘贴窗口")
    vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.fn.readfile(t.fixture .. "/logs/app.log"))
    vim.cmd("stopinsert")
    local submit
    for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
      if m.lhs == "<CR>" then submit = m.callback end
    end
    t.ok(submit, "回车解析")
    submit()
    t.ok(not win:valid(), "粘贴窗口应已关闭")
    local qf = vim.fn.getqflist({ title = 1, items = 1 })
    t.eq(qf.title, "分析堆栈")
    t.eq(#qf.items, 2, "项目里的两行堆栈")
    t.ok(vim.api.nvim_buf_get_name(qf.items[1].bufnr):find("UserServiceImpl.java$"), "第一项")
    t.eq(qf.items[1].lnum, 26)
    pcall(vim.cmd, "Trouble qflist close")
    pcall(vim.cmd, "cclose")
    -- 再次打开时保留上次粘贴的内容
    win = B.analyze_stack()
    t.eq(vim.api.nvim_buf_line_count(0) >= 5, true, "保留上次内容")
    win:close()
  end,

  ["z 关闭 kit-test 服务器"] = function()
    sh({ "tmux", "-L", SOCK, "kill-server" })
  end,
}
