-- Neovim 和 tmux 里其他面板（Claude Code、日志）的配合：
--   * 登记 socket：在 tmux 里启动时把自己的 server socket 写到面板选项 @nvim_socket，获得焦点的时间写到 @nvim_focus，
--     tmux 的 前缀 j（bin/tmux-jump）据此找到同窗口里最近用过的 Neovim，调用下面的 open() 打开文件。
--     tmux.conf 也据 @nvim_socket 判断"这个面板是 Neovim"，把 Ctrl+B 直接交给它（单按 Ctrl+B 跳转到声明）
--   * 内置终端（Alt+F12）里 Ctrl+B：当作 tmux 前缀（和 shell / Claude Code 面板里一样），连按两次把 Ctrl+B 发给终端里的程序
--   * 空格 j s：粘贴一段 Java 堆栈 / 日志 / Claude 的输出，解析成可跳转的列表（IDEA 的 Analyze Stack Trace）
--   * 空格 a s：把当前行（普通模式）或选中的代码（可视模式）发到同窗口的 Claude Code 输入框，不按回车
-- 解析规则和 bin/tmux-jump 里的 perl 版本保持一致，两边都有测试（test/spec/tmux_bridge_spec.lua）
local K = require("config.idea_keys")
local M = {}

-- 调用 tmux 的命令（测试时换成独立的 tmux -L kit-test 服务器）
M.tmux_cmd = { "tmux" }
M.pane = vim.env.TMUX_PANE

local function tmux(args, opts)
  local cmd = vim.list_extend(vim.deepcopy(M.tmux_cmd), args)
  return vim.system(cmd, vim.tbl_extend("force", { text = true }, opts or {}))
end

local function in_tmux() return vim.env.TMUX ~= nil and M.pane ~= nil end

local function now_ms()
  local s, us = vim.uv.gettimeofday()
  return string.format("%d", s * 1000 + math.floor(us / 1000))
end

-- ================= 登记 socket =================
function M.socket()
  if vim.v.servername == "" then pcall(vim.fn.serverstart) end
  return vim.v.servername
end

-- 写入 / 清除面板选项。异步执行，不拖慢启动；退出时等它完成（最多 300 毫秒），否则 nvim 退得太快命令可能没执行
function M.register(wait)
  local p = tmux({ "set", "-p", "-t", M.pane, "@nvim_socket", M.socket(), ";",
    "set", "-p", "-t", M.pane, "@nvim_focus", now_ms() })
  if wait then p:wait(wait) end
  return p
end

function M.unregister(wait)
  local p = tmux({ "set", "-p", "-u", "-t", M.pane, "@nvim_socket", ";", "set", "-p", "-u", "-t", M.pane, "@nvim_focus" })
  if wait then p:wait(wait) end
  return p
end

function M.touch()
  return tmux({ "set", "-p", "-t", M.pane, "@nvim_focus", now_ms() })
end

-- 内置终端里再开的 nvim（$NVIM 非空）不登记，否则会顶替外层 nvim 的 socket
if in_tmux() and not vim.env.NVIM and not vim.env.NVIM_KIT_TEST then
  M.register()
  local g = vim.api.nvim_create_augroup("kit_tmux_bridge", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = g, callback = function() M.unregister(300) end })
  -- Ctrl+Z 挂起后面板里是 shell，要让 Ctrl+B 回到 tmux 前缀
  vim.api.nvim_create_autocmd("VimSuspend", { group = g, callback = function() M.unregister(300) end })
  vim.api.nvim_create_autocmd("VimResume", { group = g, callback = function() M.register() end })
  vim.api.nvim_create_autocmd("FocusGained", { group = g, callback = function() M.touch() end })
end

-- ================= 打开文件（tmux-jump 远程调用） =================
-- 当前窗口是文件树、终端、浮窗等时，换到一个普通的代码窗口里打开
local function code_window()
  local cur = vim.api.nvim_get_current_win()
  local function ok(w)
    local b = vim.api.nvim_win_get_buf(w)
    return vim.api.nvim_win_get_config(w).relative == "" and vim.bo[b].buftype == ""
  end
  if ok(cur) then return cur end
  local prev = vim.fn.win_getid(vim.fn.winnr("#"))
  if prev ~= 0 and ok(prev) then return prev end
  for _, w in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if ok(w) then return w end
  end
  return cur
end

-- 立即打开（测试和 空格 j s 用）：相对路径相对 nvim 的当前目录；行、列从 1 开始，列为 0 表示行首
function M.open_now(path, line, col)
  path = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  if vim.fn.filereadable(path) == 0 then
    vim.notify("文件不存在：" .. path, vim.log.levels.WARN)
    return false
  end
  local mode = vim.fn.mode()
  if mode == "i" or mode == "t" then vim.cmd("stopinsert") end
  local w = code_window()
  -- 当前窗口是浮窗（终端、选择框）时先关掉，否则文件开在浮窗下面看不见
  local cur = vim.api.nvim_get_current_win()
  if cur ~= w and vim.api.nvim_win_get_config(cur).relative ~= "" then pcall(vim.api.nvim_win_close, cur, false) end
  vim.api.nvim_set_current_win(w)
  vim.cmd("normal! m'")
  if vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":p") ~= path then
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end
  local last = vim.api.nvim_buf_line_count(0)
  line = math.max(1, math.min(tonumber(line) or 1, last))
  col = tonumber(col) or 0
  pcall(vim.api.nvim_win_set_cursor, 0, { line, math.max(0, col - 1) })
  if col == 0 then vim.cmd("normal! ^") end
  vim.cmd("normal! zvzz")
  return true
end

-- 供 nvim --remote-expr 调用：先返回，再在主循环里打开（远程调用时 nvim 可能正处在输入模式、弹框等状态）
function M.open(path, line, col)
  vim.schedule(function() M.open_now(path, line, col) end)
  return "ok"
end

-- ================= 解析 文件:行号 / Java 堆栈 =================
local PATH = "[%w_%./~%-]*%.%a[%w_]*" -- 必须带扩展名，避免把 10:00:01、localhost:8080 当成位置

-- 在 s 里找所有 pat 的匹配，跳过前面紧挨路径字符或冒号的（排除 https://x/a.js:1 这类 URL）
local function scan(s, pat, fn)
  local init = 1
  while true do
    local a, b, c1, c2 = s:find(pat, init)
    if not a then return end
    local prev = a > 1 and s:sub(a - 1, a - 1) or ""
    if prev ~= "" and prev:match("[%w_%./~:%-]") then
      init = a + 1
    else
      b = fn(a, b, c1, c2) or b
      init = b + 1
    end
  end
end

local function blank(s, a, b) return s:sub(1, a - 1) .. string.rep(" ", b - a + 1) .. s:sub(b + 1) end

-- 解析一行。返回 { kind = "java"|"loc", path, line, col, pos }，按在行里的位置排序
-- Java 堆栈的 path 是 包路径/文件名（com/x/Foo.java），另有 file = 文件名
function M.parse_line(l)
  local hits = {}
  local rest = l
  local init = 1
  while true do
    local a, b, q, file, ln = l:find("%f[%w_]at%s+([^%s(]+)%(([%w_$]+%.%a+):(%d+)%)", init)
    if not a then break end
    q = q:gsub(".*/", "") -- 去掉模块前缀：app//、java.base/
    local cls = q:gsub("%.[^.]*$", "") -- 去掉方法名
    local pkg = cls:match("^(.*)%.") or ""
    pkg = pkg:gsub("%.", "/")
    hits[#hits + 1] = { kind = "java", path = (pkg ~= "" and pkg .. "/" or "") .. file, file = file,
      line = tonumber(ln), col = 0, pos = a }
    rest = blank(rest, a, b)
    init = b + 1
  end
  scan(rest, "(" .. PATH .. ")#L(%d+)", function(a, b, p, ln)
    hits[#hits + 1] = { kind = "loc", path = p, line = tonumber(ln), col = 0, pos = a }
    local e = select(2, rest:find("^%-L?%d+", b + 1))
    if e then b = e end
    rest = blank(rest, a, b)
    return b
  end)
  scan(rest, "(" .. PATH .. "):(%d+)", function(a, b, p, ln)
    local c = rest:match("^:(%d+)", b + 1)
    hits[#hits + 1] = { kind = "loc", path = p, line = tonumber(ln), col = tonumber(c) or 0, pos = a }
    return c and b + #c + 1 or b
  end)
  table.sort(hits, function(x, y) return x.pos < y.pos end)
  return hits
end

-- 解析整段文本，按出现顺序返回（每项多一个 lnum = 文本中的行号、text = 去掉首尾空白的原文）
function M.parse(text)
  local out = {}
  local lines = type(text) == "table" and text or vim.split(text, "\r?\n")
  for i, l in ipairs(lines) do
    l = l:gsub("\r", "")
    local ctx = vim.trim(l):gsub("\t", " ")
    for _, h in ipairs(M.parse_line(l)) do
      h.lnum, h.text = i, ctx
      out[#out + 1] = h
    end
  end
  return out
end

-- 最近的（文本中靠后的）在前并去重，与 tmux-jump 的列表顺序相同
function M.recent_unique(items)
  local sorted = vim.list_slice(items)
  table.sort(sorted, function(a, b)
    if a.lnum ~= b.lnum then return a.lnum > b.lnum end
    return a.pos < b.pos
  end)
  local seen, out = {}, {}
  for _, it in ipairs(sorted) do
    local key = it.kind .. "\t" .. it.path .. "\t" .. it.line
    if not seen[key] then seen[key] = true out[#out + 1] = it end
  end
  return out
end

-- 把解析结果对应到真实文件，找不到的去掉；结果的 filename 为绝对路径
-- bases：相对路径依次相对这些目录查找；Java 堆栈在 bases[1]（项目根）里用 rg 按 包路径/文件名 查找
function M.resolve(items, bases)
  local globs, files = {}, {}
  for _, it in ipairs(items) do
    if it.kind == "java" and not files[it.file] then
      files[it.file] = true
      vim.list_extend(globs, { "-g", it.file })
    end
  end
  local found = {}
  if #globs > 0 then
    local cmd = vim.list_extend({ "rg", "--files" }, globs)
    cmd[#cmd + 1] = bases[1]
    local r = vim.system(cmd, { text = true }):wait(10000)
    found = vim.split(vim.trim(r.stdout or ""), "\n", { trimempty = true })
    table.sort(found)
  end
  local out, done = {}, {}
  for _, it in ipairs(items) do
    local abs
    if it.kind == "java" then
      local tail = "/" .. it.path
      for _, f in ipairs(found) do
        if f:sub(-#tail) == tail then abs = f break end
      end
    else
      local p = it.path:gsub("^~/", vim.env.HOME .. "/")
      if p:sub(1, 1) == "/" then
        if vim.fn.filereadable(p) == 1 then abs = p end
      else
        for _, b in ipairs(bases) do
          local c = (b .. "/" .. p):gsub("/%./", "/")
          if vim.fn.filereadable(c) == 1 then abs = c break end
        end
      end
    end
    if abs and not done[abs .. "\t" .. it.line] then
      done[abs .. "\t" .. it.line] = true
      out[#out + 1] = vim.tbl_extend("force", it, { filename = abs })
    end
  end
  return out
end

-- ================= 空格 j s：分析堆栈 =================
local function project_root()
  local ok, root = pcall(function() return LazyVim.root() end)
  return ok and root or vim.fn.getcwd()
end

-- 解析粘贴的文本，放进快速修复列表（按堆栈原来的顺序），用 Trouble 面板显示；返回条目数
function M.stack_to_qf(lines)
  local root = project_root()
  local bases = { root }
  if vim.fn.getcwd() ~= root then bases[2] = vim.fn.getcwd() end
  local items = M.resolve(M.parse(lines), bases)
  local qf = {}
  for _, it in ipairs(items) do
    qf[#qf + 1] = { filename = it.filename, lnum = it.line, col = it.col, text = it.text }
  end
  vim.fn.setqflist({}, " ", { title = "分析堆栈", items = qf })
  return #qf
end

M.last_stack = nil

function M.analyze_stack()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].filetype = "kit_stack"
  if M.last_stack then vim.api.nvim_buf_set_lines(buf, 0, -1, false, M.last_stack) end
  local win
  local function submit()
    local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
    M.last_stack = lines
    vim.cmd("stopinsert")
    if win and win:valid() then win:close() end
    local n = M.stack_to_qf(lines)
    if n == 0 then
      vim.notify("没有找到项目里的 文件:行号 或 Java 堆栈行", vim.log.levels.WARN)
      return
    end
    local ok = pcall(vim.cmd, "Trouble qflist open focus=true")
    if not ok then vim.cmd("copen") end
    vim.notify(string.format("找到 %d 个位置，回车跳转", n))
  end
  win = Snacks.win({
    buf = buf,
    position = "float",
    width = 0.7,
    height = 0.6,
    border = "rounded",
    title = " 分析堆栈：粘贴 Java 堆栈 / 日志 / Claude 的输出 ",
    title_pos = "center",
    footer = " Ctrl+S 或 普通模式回车：解析 · q / Esc 关闭 ",
    footer_pos = "center",
    enter = true,
    wo = { wrap = false, number = true },
    keys = {
      q = "close",
      ["<Esc>"] = "close",
      ["<CR>"] = { submit, mode = "n", desc = "解析" },
      ["<C-s>"] = { submit, mode = { "n", "i" }, desc = "解析" },
    },
  })
  if not M.last_stack then vim.cmd("startinsert") end
  return win
end

-- ================= 空格 a s：发送给 Claude Code =================
-- 生成要粘贴的文本。path 是绝对路径，base 是 Claude 的工作目录（@ 引用相对它解析），
-- 在 base 下面就写相对路径，否则写绝对路径。lines 为 nil 时只发引用（普通模式）
function M.claude_text(path, base, l1, l2, lines, ft)
  local rel = path
  if base and base ~= "" then
    local prefix = base:gsub("/$", "") .. "/"
    if path:sub(1, #prefix) == prefix then rel = path:sub(#prefix + 1) end
  end
  local ref = "@" .. rel .. "#L" .. l1 .. ((l2 and l2 ~= l1) and ("-" .. l2) or "")
  if not lines then return ref .. " " end
  local body = table.concat(lines, "\n")
  -- 代码里本身有 ``` 时用更长的围栏，避免提前结束代码块
  local fence = "```"
  while body:find(fence, 1, true) do fence = fence .. "`" end
  return ref .. "\n" .. fence .. (ft or "") .. "\n" .. body .. "\n" .. fence .. "\n"
end

-- 面板是不是 Claude Code：前台命令名是 claude；或者是 node/bun 且命令行里有 claude；或者标题是 Claude Code 设的
function M.is_claude(cmd, title, args)
  if cmd == "claude" then return true end
  if (cmd == "node" or cmd == "bun") and args and args:find("claude") then return true end
  return title ~= nil and title:find("Claude Code", 1, true) ~= nil
end

-- 找同一 tmux 窗口里的 Claude Code 面板，返回 面板id, 工作目录；有多个时优先刚离开的那个（pane_last）
function M.find_claude_pane()
  local r = tmux({ "list-panes", "-t", M.pane, "-F",
    "#{pane_id}\t#{pane_current_command}\t#{pane_pid}\t#{pane_last}\t#{pane_current_path}\t#{pane_title}" }):wait(3000)
  if r.code ~= 0 then return nil end
  local ps
  local function child_args(pid)
    if not ps then
      ps = {}
      local out = vim.system({ "ps", "-e", "-o", "pid=,ppid=,args=" }, { text = true }):wait(3000).stdout or ""
      for line in out:gmatch("[^\n]+") do
        local p, pp, a = line:match("^%s*(%d+)%s+(%d+)%s+(.*)$")
        if p then ps[#ps + 1] = { pid = p, ppid = pp, args = a } end
      end
    end
    local s = ""
    for _, x in ipairs(ps) do
      if x.ppid == pid then s = s .. " " .. x.args end
    end
    return s
  end
  local best
  for line in (r.stdout or ""):gmatch("[^\n]+") do
    local id, cmd, pid, last, cwd, title = unpack(vim.split(line, "\t", { plain = true }))
    if id ~= M.pane then
      local args = (cmd == "node" or cmd == "bun") and child_args(pid) or nil
      if M.is_claude(cmd, title, args) and (not best or last == "1") then best = { id = id, cwd = cwd } end
    end
  end
  if best then return best.id, best.cwd end
end

-- 用括号粘贴（paste-buffer -p）送进输入框：Claude 不会把里面的换行当成提交
function M.send_to_pane(pane, text)
  local r = tmux({ "load-buffer", "-b", "kit-claude", "-" }, { stdin = text }):wait(3000)
  if r.code ~= 0 then return false, r.stderr end
  r = tmux({ "paste-buffer", "-p", "-d", "-b", "kit-claude", "-t", pane, ";", "select-pane", "-t", pane }):wait(3000)
  return r.code == 0, r.stderr
end

function M.send_to_claude(visual)
  if not in_tmux() then
    vim.notify("不在 tmux 里，无法发送给 Claude Code", vim.log.levels.WARN)
    return
  end
  local path = vim.api.nvim_buf_get_name(0)
  if path == "" or vim.bo.buftype ~= "" then
    vim.notify("当前不是文件", vim.log.levels.WARN)
    return
  end
  local l1, l2, lines = vim.fn.line("."), nil, nil
  if visual then
    l1, l2 = vim.fn.line("v"), vim.fn.line(".")
    if l1 > l2 then l1, l2 = l2, l1 end
    lines = vim.api.nvim_buf_get_lines(0, l1 - 1, l2, false)
    vim.api.nvim_feedkeys(vim.keycode("<Esc>"), "nx", false)
  end
  local pane, cwd = M.find_claude_pane()
  if not pane then
    vim.notify("当前 tmux 窗口里没有找到运行 Claude Code 的面板", vim.log.levels.WARN)
    return
  end
  local ok, err = M.send_to_pane(pane, M.claude_text(vim.fn.fnamemodify(path, ":p"), cwd, l1, l2, lines, vim.bo.filetype))
  if not ok then vim.notify("发送失败：" .. tostring(err), vim.log.levels.WARN) end
end

-- ================= 内置终端里的 Ctrl+B =================
-- tmux 看到的前台程序是 nvim，会把 Ctrl+B 交给 nvim；终端里的程序（shell、Claude Code）习惯上 Ctrl+B 是 tmux 前缀，
-- 所以这里转成 tmux 前缀，和直接在 tmux 面板里一样：Ctrl+B 再按 % 分屏、方向键切面板……
-- 连按两次 Ctrl+B 时 tmux 会把第二个 Ctrl+B 发回 nvim（tmux.conf 的 bind C-b send-keys C-b），这时交给终端里的程序
-- （例如 Claude Code 的 Ctrl+B 转后台），和 tmux 里"连按两次发给程序"的习惯一致
local last_cb = 0
function M.terminal_ctrl_b()
  local t = vim.uv.now()
  if t - last_cb < 1000 then
    last_cb = 0
    return "<C-b>"
  end
  last_cb = t
  tmux({ "switch-client", "-T", "prefix" })
  return ""
end

if vim.env.TMUX then
  vim.keymap.set("t", "<C-b>", M.terminal_ctrl_b, { expr = true, desc = "tmux 前缀（连按两次发给终端里的程序）" })
  vim.api.nvim_create_autocmd("FocusLost", { callback = function() last_cb = 0 end })
end

-- ================= 按键 =================
pcall(function()
  require("which-key").add({ { "<leader>j", group = "跳转（堆栈 / 日志）" }, { "<leader>a", group = "Claude Code" } })
end)
K.map("n", "<leader>js", M.analyze_stack, "分析堆栈：粘贴堆栈 / 日志，列出可跳转的位置")
K.map("n", "<leader>as", function() M.send_to_claude(false) end, "把当前行的引用 @文件#L行 发给 Claude Code")
K.map("x", "<leader>as", function() M.send_to_claude(true) end, "把选中的代码发给 Claude Code（不按回车）")

return M
