-- IDEA（Windows 默认键位）快捷键：和 Vim 原有按键冲突时以 IDEA 为准
--
-- 终端的限制：
--   * Ctrl+Shift+字母 和 Ctrl+字母 在普通终端里是同一个按键。浏览器页面和 Windows Terminal（wt-keys.ps1）
--     已改为发送可区分的编码，文件末尾把 Ctrl+Shift+X 映射为和 Alt+Shift+X 相同；Alt+Shift+X 作为备用
--     （方向键、F 键带 Ctrl+Shift 不受影响，如 Ctrl+Shift+↑、Ctrl+Shift+F12 照常可用）
--   * 双击 Shift、Ctrl+Tab、Ctrl+I（终端里等同 Tab）无法实现
--   * 浏览器会抢走 Ctrl+N / Ctrl+W / Ctrl+T，这几个只能在 Windows Terminal 里用；Ctrl+N 在浏览器里可用 Alt+N
--   * Ctrl+B 是 tmux 前缀键，编辑器里跳转到声明要连按两次 Ctrl+B（或 Ctrl+点击）
--
-- 被替换掉的 Vim 原有按键：
--   翻页 Ctrl+D/U/F/B → PageDown/PageUp 或鼠标滚轮；重做 Ctrl+R → Alt+Shift+Z；
--   跳回/前进 Ctrl+O/I → Ctrl+Alt+←/→；块选择 Ctrl+V → Alt+Shift+Insert；窗口切换 Ctrl+W/Ctrl+H → 鼠标点击或 空格 w

-- 输入模式下只在普通代码文件里生效；搜索框、文件树等特殊窗口（buftype 非空）里保持按键原本的作用，
-- 否则例如在文件树搜索框里按 Ctrl+F 会触发 Esc 把文件树关掉
local function special_buf()
  local ft = vim.bo.filetype
  -- 查找栏 / 帮助面板里按 IDEA 快捷键：照常执行（会先回到代码窗口），见 in_float_guard
  return vim.bo.buftype ~= "" and ft ~= "find_bar" and ft ~= "zh_help"
end

-- 这些键在输入模式下会"等待下一个键"（如 Ctrl+V 等你再按一个字符），原样交给输入框会让人以为卡死：
-- Ctrl+V 改为粘贴，其余忽略
local waiting_keys = { ["<C-v>"] = '<C-r><C-o>"', ["<C-q>"] = "", ["<C-k>"] = "", ["<C-o>"] = "", ["<C-g>"] = "", ["<C-x>"] = "" }
local function raw_key(lhs)
  local r = waiting_keys[lhs]
  if r == nil then return lhs end
  return r
end

-- 光标在查找栏 / 帮助面板里时，先回到代码窗口再执行（否则关闭文件等操作会作用在小浮窗上）；
-- 在输入框（如"跳转到行"）里则忽略，避免叠出多个输入框
local function in_float_guard(fn)
  return function(...)
    local ft = vim.bo.filetype
    if ft == "snacks_input" then
      return
    end
    if ft == "find_bar" or ft == "zh_help" then
      vim.cmd("stopinsert")
      vim.cmd("wincmd p")
    end
    return fn(...)
  end
end

local function map(modes, lhs, rhs, desc, opts)
  opts = vim.tbl_extend("force", { desc = desc, silent = true }, opts or {})
  modes = type(modes) == "table" and modes or { modes }
  if type(rhs) == "function" then
    rhs = in_float_guard(rhs)
  end
  for _, mode in ipairs(modes) do
    if mode == "i" then
      -- 特殊窗口里返回按键本身（不重映射 = 按键原本的作用）；代码文件里执行 IDEA 功能
      local o = vim.tbl_extend("force", opts, { expr = true, remap = false })
      local fn = rhs
      if type(rhs) == "string" and opts.remap then
        fn = function()
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(rhs, true, false, true), "m", false)
        end
      end
      if type(fn) == "function" then
        vim.keymap.set("i", lhs, function()
          if special_buf() then return raw_key(lhs) end
          vim.schedule(fn)
          return ""
        end, o)
      else
        vim.keymap.set("i", lhs, function()
          if special_buf() then return raw_key(lhs) end
          return rhs
        end, o)
      end
    else
      vim.keymap.set(mode, lhs, rhs, opts)
    end
  end
end

-- 在输入模式下执行跳转类操作前先回到普通模式
local function n(fn)
  return function()
    if vim.fn.mode() == "i" then
      vim.cmd("stopinsert")
      vim.schedule(fn)
    else
      fn()
    end
  end
end

local function has_lsp(method)
  return #vim.lsp.get_clients({ bufnr = 0, method = method }) > 0
end

local function is_java()
  return vim.bo.filetype == "java" and package.loaded["jdtls"] ~= nil
end

local function feed(keys, mode)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), mode or "m", false)
end

local function code_action(only)
  return n(function()
    vim.lsp.buf.code_action(only and { context = { only = { only }, diagnostics = {} } } or nil)
  end)
end

local NI, NIX, NX = { "n", "i" }, { "n", "i", "x" }, { "n", "x" }

-- 选中：Shift+方向键 / Shift+Home/End 开始选择，不按 Shift 移动时取消选择
vim.opt.keymodel = { "startsel", "stopsel" }
vim.opt.selectmode = ""

-- ================= 编辑 =================
map(NIX, "<C-s>", function()
  vim.cmd("stopinsert")
  local ok, err = pcall(vim.cmd, "wall")
  if not ok then vim.notify(err, vim.log.levels.WARN) end
end, "全部保存")
map("n", "<C-z>", "u", "撤销")
map("i", "<C-z>", "<C-o>u", "撤销")
map("x", "<C-z>", "<Esc>u", "撤销")
map("n", "<M-Z>", "<C-r>", "重做（IDEA: Ctrl+Shift+Z）")
map("i", "<M-Z>", "<C-o><C-r>", "重做（IDEA: Ctrl+Shift+Z）")

map("n", "<C-c>", '"+yy', "复制当前行")
map("i", "<C-c>", '<C-o>"+yy', "复制当前行")
map("v", "<C-c>", '"+y', "复制到系统剪贴板")
map("n", "<C-x>", '"+dd', "剪切当前行")
map("i", "<C-x>", '<C-o>"+dd', "剪切当前行")
map("v", "<C-x>", '"+d', "剪切")
-- 浏览器里 Ctrl+V 粘贴的是编辑器里复制的内容；外部复制的内容用 Ctrl+Shift+V（Windows Terminal 里 Ctrl+V 直接粘贴系统剪贴板）
-- 编辑器里还没复制过内容时给出提示，而不是报 E353
local function paste_or_hint()
  if vim.fn.getreg('"') == "" then
    vim.notify("编辑器里还没有复制过内容。从外部复制的内容：浏览器里用 Ctrl+Shift+V 粘贴", vim.log.levels.INFO)
    return
  end
  vim.cmd('normal! ""P')
end
map("n", "<C-v>", paste_or_hint, "粘贴")
map("i", "<C-v>", '<C-r><C-o>"', "粘贴")
map("x", "<C-v>", '"_dP', "粘贴替换选中内容")
map("n", "<M-S-Insert>", "<C-v>", "块选择（列选择）")
map(NIX, "<M-V>", n(function() Snacks.picker.registers() end), "从复制历史粘贴（IDEA: Ctrl+Shift+V）")

local function duplicate()
  local pos = vim.api.nvim_win_get_cursor(0)
  vim.cmd("t.")
  vim.api.nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })
end
map(NI, "<C-d>", duplicate, "复制一行到下方")
map("x", "<C-d>", ":t'><CR>gv", "复制选中的行到下方")
map("n", "<C-y>", '"_dd', "删除当前行")
map("i", "<C-y>", '<C-o>"_dd', "删除当前行")
map("n", "<C-a>", "ggVG", "全选")
map("i", "<C-a>", "<Esc>ggVG", "全选")

-- 终端里 Ctrl+/ 发出的是 Ctrl+_，两个都映射
for _, lhs in ipairs({ "<C-/>", "<C-_>" }) do
  map("n", lhs, "gcc", "注释 / 取消注释", { remap = true })
  map("i", lhs, "<Cmd>normal gcc<CR>", "注释 / 取消注释")
  map("x", lhs, "gc", "注释 / 取消注释", { remap = true })
end

local function expand_selection()
  require("flash").treesitter({ actions = { ["<c-w>"] = "next", ["<M-W>"] = "prev", ["<C-S-W>"] = "prev" } })
end
map(NX, "<C-w>", expand_selection, "扩大选区（再按扩大，Alt+Shift+W 缩小，回车确认）")

for _, k in ipairs({ "<M-S-Up>", "<C-S-Up>" }) do
  map(NIX, k, "<M-k>", "整行上移", { remap = true })
end
for _, k in ipairs({ "<M-S-Down>", "<C-S-Down>" }) do
  map(NIX, k, "<M-j>", "整行下移", { remap = true })
end
map(NX, "<M-J>", "J", "合并行（IDEA: Ctrl+Shift+J）")
map("n", "<M-U>", "g~iw", "切换大小写（IDEA: Ctrl+Shift+U）")
map("x", "<M-U>", "~", "切换大小写（IDEA: Ctrl+Shift+U）")
-- Shift+Enter 只在 Windows Terminal 里有效（浏览器分不出 Shift+Enter）；Ctrl+Alt+Enter 在终端里等同 Alt+Enter，无法实现
map(NI, "<S-CR>", "<Esc>o", "在下方开始新行")
map("x", "<Tab>", ">gv", "向右缩进")
map("x", "<S-Tab>", "<gv", "向左缩进")
map("x", "<BS>", '"_d', "删除选中内容")

map(NIX, "<C-M-l>", function() LazyVim.format({ force = true }) end, "格式化代码")
map(NI, "<C-M-o>", function()
  if is_java() then
    require("jdtls").organize_imports()
  else
    vim.lsp.buf.code_action({ apply = true, context = { only = { "source.organizeImports" }, diagnostics = {} } })
  end
end, "整理 import")
-- 终端里 Ctrl+Alt+I 到达时是 Alt+Tab，Ctrl+Alt+H 是 Alt+Backspace，两种写法都映射
for _, lhs in ipairs({ "<C-M-i>", "<M-Tab>" }) do
  map("n", lhs, "==", "自动缩进当前行")
  map("x", lhs, "=", "自动缩进选中行")
end

-- ================= 代码操作 / 重构 =================
map(NIX, "<M-CR>", code_action(), "显示意图操作（快速修复）")
map(NI, "<M-Insert>", code_action("source"), "生成代码（getter/setter、构造方法等）")
map("n", "<C-o>", code_action("source"), "重写 / 实现方法")
map(NI, "<S-F6>", n(function() vim.lsp.buf.rename() end), "重命名")
map(NI, "<C-M-v>", n(function()
  if is_java() then require("jdtls").extract_variable_all() else vim.lsp.buf.code_action({ context = { only = { "refactor.extract" }, diagnostics = {} } }) end
end), "提取变量")
map("x", "<C-M-v>", "<Esc><Cmd>lua require('jdtls').extract_variable_all(true)<CR>", "提取变量")
map(NI, "<C-M-c>", n(function()
  if is_java() then require("jdtls").extract_constant() else vim.lsp.buf.code_action({ context = { only = { "refactor.extract" }, diagnostics = {} } }) end
end), "提取常量")
map("x", "<C-M-c>", "<Esc><Cmd>lua require('jdtls').extract_constant(true)<CR>", "提取常量")
-- Ctrl+Alt+M 在终端里和 Alt+Enter 是同一个按键：选中代码后按 Alt+Enter，菜单里有"提取方法"
map(NI, "<C-M-n>", code_action("refactor.inline"), "内联")

-- ================= 跳转 =================
local function definition()
  if has_lsp("textDocument/definition") then
    Snacks.picker.lsp_definitions()
  else
    pcall(vim.cmd, "normal! gd") -- 光标不在标识符上（如点到空白处）时不报错
  end
end
map(NI, "<C-b>", n(definition), "跳转到声明（tmux 里连按两次 Ctrl+B）")
map(NI, "<C-M-b>", n(function() Snacks.picker.lsp_implementations() end), "跳转到实现")
map(NI, "<M-B>", n(function() Snacks.picker.lsp_type_definitions() end), "跳转到类型声明（IDEA: Ctrl+Shift+B）")
map(NI, "<C-u>", n(function()
  if is_java() then require("jdtls").super_implementation() else Snacks.picker.lsp_declarations() end
end), "跳转到父类方法")
map(NI, "<M-F7>", n(function() Snacks.picker.lsp_references() end), "查找用法")
map(NI, "<C-M-F7>", n(function() Snacks.picker.lsp_references() end), "查找用法")
map(NI, "<C-h>", n(function() vim.lsp.buf.typehierarchy("subtypes") end), "类型层级（子类）")
for _, lhs in ipairs({ "<C-M-h>", "<M-BS>" }) do
  map(NI, lhs, n(function() Snacks.picker.lsp_incoming_calls() end), "调用层级（谁调用了它）")
end
map(NI, "<M-I>", n(function() Snacks.picker.lsp_definitions({ auto_confirm = false }) end), "快速查看定义（IDEA: Ctrl+Shift+I）")
map(NI, "<C-q>", n(function() vim.lsp.buf.hover() end), "查看文档")
map(NI, "<C-p>", function() vim.lsp.buf.signature_help() end, "查看参数信息")

local function goto_class() Snacks.picker.lsp_workspace_symbols({ filter = LazyVim.config.kind_filter }) end
map(NI, "<C-n>", n(goto_class), "查找类 / 方法")
map(NI, "<M-n>", n(goto_class), "查找类 / 方法（浏览器里代替 Ctrl+N）")
map(NI, "<M-N>", n(function() LazyVim.pick("files")() end), "查找文件（IDEA: Ctrl+Shift+N）")
map(NI, "<M-A>", n(function() Snacks.picker.keymaps() end), "查找操作（IDEA: Ctrl+Shift+A）")
-- 只列出当前项目里的文件：避免从别的位置（如搬家前的 /mnt/d 旧项目）的历史记录里误打开文件
map(NI, "<C-e>", n(function() Snacks.picker.recent({ title = "最近的文件（当前项目）", filter = { cwd = true } }) end), "最近的文件（当前项目）")
map(NI, "<M-E>", n(function() Snacks.picker.jumps() end), "最近的位置（IDEA: Ctrl+Shift+E）")
map(NI, "<C-F12>", n(function() Snacks.picker.lsp_symbols({ filter = LazyVim.config.kind_filter }) end), "文件结构")
map(NI, "<M-7>", n(function() vim.cmd("Trouble symbols toggle") end), "结构面板")

map(NI, "<C-g>", n(function()
  vim.ui.input({ prompt = "跳转到行[:列]：" }, function(input)
    local l, c = (input or ""):match("^%s*(%d+)%s*[:,]?%s*(%d*)%s*$")
    if not l then return end
    vim.cmd("normal! m'")
    local last = vim.api.nvim_buf_line_count(0)
    vim.api.nvim_win_set_cursor(0, { math.min(tonumber(l), last), math.max((tonumber(c) or 1) - 1, 0) })
    vim.cmd("normal! zz")
  end)
end), "跳转到行")

map(NI, "<C-M-Left>", n(function() vim.cmd([[execute "normal! \<C-o>"]]) end), "后退（上一个位置）")
map(NI, "<C-M-Right>", n(function() vim.cmd([[execute "normal! \<C-i>"]]) end), "前进")

local function method(dir)
  return n(function()
    local lhs = dir > 0 and "]f" or "[f"
    if vim.fn.maparg(lhs, "n") ~= "" then
      feed(lhs, "m")
    else
      feed(dir > 0 and "]m" or "[m", "n")
    end
  end)
end
map(NI, "<M-Down>", method(1), "下一个方法")
map(NI, "<M-Up>", method(-1), "上一个方法")
map(NI, "<F2>", n(function() vim.diagnostic.jump({ count = 1, float = true }) end), "下一个问题")
map(NI, "<S-F2>", n(function() vim.diagnostic.jump({ count = -1, float = true }) end), "上一个问题")

-- ================= 查找 / 替换 =================
map(NI, "<C-f>", function() require("config.find_bar").open() end, "在文件中查找")
map("x", "<C-f>", function()
  local fb = require("config.find_bar")
  local t = fb.selection()
  vim.schedule(function() fb.open(t) end)
end, "查找选中内容")
map(NI, "<F3>", n(function() require("config.find_bar").next(1) end), "下一个匹配")
map(NI, "<S-F3>", n(function() require("config.find_bar").next(-1) end), "上一个匹配")

local function replace(all_files)
  return function()
    local prefills = all_files and {} or { paths = vim.fn.expand("%") }
    if vim.fn.mode():match("[vV\22]") then
      require("grug-far").with_visual_selection({ prefills = prefills })
    else
      vim.cmd("stopinsert")
      prefills.search = vim.fn.expand("<cword>")
      require("grug-far").open({ prefills = prefills })
    end
  end
end
map(NIX, "<C-r>", replace(false), "在文件中替换")
map(NIX, "<M-R>", replace(true), "在所有文件中替换（IDEA: Ctrl+Shift+R）")
-- 在文件中查找（IDEA: Ctrl+Shift+F）：上方输入框、中间结果列表、下方预览；默认按普通文字、不区分大小写搜索
-- Alt+C 区分大小写，Alt+W 整词，Alt+X 正则；在输入框里写 "关键字 -- -g *.java" 可以限定文件类型
local function find_in_files(search)
  local function rg_args(o)
    local a = { o.case and "--case-sensitive" or "--ignore-case" }
    if o.word then a[#a + 1] = "--word-regexp" end
    return a
  end
  local function flip(name)
    return function(picker)
      picker.opts[name] = not picker.opts[name]
      picker.opts.args = rg_args(picker.opts)
      picker.list:set_target()
      picker:find()
    end
  end
  local both = { "i", "n" }
  Snacks.picker.grep({
    title = "在文件中查找",
    cwd = LazyVim.root(),
    search = search,
    regex = false,
    case = false,
    word = false,
    args = rg_args({}),
    layout = { preset = "vertical" },
    -- 边输入边搜时最多取 1000 条（IDEA 的弹框也只显示前 100 多条），输入第一个字时不必处理几十万条结果；
    -- 压缩过的 js/css 一行几十万字符，搜代码时用不到
    limit_live = 1000,
    exclude = { "*.min.js", "*.min.css", "*.map" },
    toggles = {
      case = { icon = "Aa", value = true },
      word = { icon = "W", value = true },
      regex = { icon = ".*", value = true },
    },
    actions = { idea_case = flip("case"), idea_word = flip("word") },
    win = {
      input = {
        keys = {
          ["<a-c>"] = { "idea_case", mode = both, desc = "区分大小写" },
          ["<a-w>"] = { "idea_word", mode = both, desc = "整词匹配" },
          ["<a-x>"] = { "toggle_regex", mode = both, desc = "正则" },
        },
      },
    },
  })
end
map(NI, "<M-F>", n(function() find_in_files() end), "在所有文件中查找（IDEA: Ctrl+Shift+F）")
map("x", "<M-F>", function()
  local t = require("config.find_bar").selection()
  vim.schedule(function() find_in_files(t) end)
end, "在所有文件中查找选中内容")

-- ================= 标签页 / 工具窗口 =================
map(NI, "<M-Left>", n(function() vim.cmd("BufferLineCyclePrev") end), "左边的标签页")
map(NI, "<M-Right>", n(function() vim.cmd("BufferLineCycleNext") end), "右边的标签页")
map(NI, "<C-F4>", n(function() Snacks.bufdelete() end), "关闭标签页")
map(NI, "<M-F1>", n(function() Snacks.explorer.reveal() end), "在文件树中定位当前文件")
map(NI, "<M-6>", n(function() vim.cmd("Trouble diagnostics toggle") end), "问题面板")
map(NI, "<M-9>", n(function() Snacks.lazygit({ cwd = LazyVim.root.git() }) end), "Git 面板（lazygit）")
map(NI, "<C-k>", n(function() Snacks.lazygit({ cwd = LazyVim.root.git() }) end), "提交（打开 lazygit）")
map(NI, "<M-F12>", n(function() Snacks.terminal(nil, { cwd = LazyVim.root() }) end), "终端")
map("t", "<M-F12>", "<Cmd>close<CR>", "隐藏终端")
map(NI, "<C-S-F12>", n(function() Snacks.zen.zoom() end), "最大化编辑区 / 还原")

-- ================= 真正的 Ctrl+Shift+字母 =================
-- 浏览器页面（build_index.py 注入的脚本）和 Windows Terminal（setup.ps1 写入的按键设置）会把 Ctrl+Shift+字母
-- 以扩展按键编码发出，tmux 原样转给 Neovim，这里让它和对应的 Alt+Shift+字母 功能相同。
-- 不包括 Ctrl+Shift+V（浏览器 / Windows Terminal 的粘贴）。
for _, L in ipairs({ "A", "B", "E", "F", "I", "J", "N", "R", "U", "W", "Z" }) do
  for _, mode in ipairs({ "n", "i", "x" }) do
    local m = vim.fn.maparg("<M-" .. L .. ">", mode, false, true)
    if next(m) then
      vim.keymap.set(mode, "<C-S-" .. L .. ">", m.callback or m.rhs, {
        expr = m.expr == 1,
        remap = m.noremap == 0,
        silent = m.silent == 1,
        desc = m.desc and m.desc:gsub("（IDEA: Ctrl%+Shift%+%a）", ""),
      })
    end
  end
end
