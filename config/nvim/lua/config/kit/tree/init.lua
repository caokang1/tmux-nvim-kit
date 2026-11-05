-- 通用树形面板（IDEA 的 Find / Hierarchy 工具窗口）：底部分屏，普通缓冲区 + extmark 高亮
--
-- 为什么自己写而不用 trouble.nvim：trouble 的 source 是"一次给出全部结果"，做不到层级树那样
-- "展开某个节点时才去问语言服务、先显示 加载中…"的逐层异步懒加载；这里的实现不到 500 行，够用。
--
-- 节点（node）是普通 table：
--   chunks   = { { "文字", "高亮组" }, ... }   显示内容（不含缩进、展开符号、图标）
--   icon, icon_hl                               图标及其高亮
--   children = { node, ... }                    已知的子节点；nil 且有 load 时表示"还没加载"
--   load     = function(node, done)             懒加载：异步取到子节点后调用 done(children)
--   expanded = true/false                       是否展开
--   loc      = { uri = ..., range = LSP range, encoding = "utf-16" }  可跳转的位置
--   occurrence = true                           Ctrl+Alt+↑/↓ 逐个跳转时会停在这个节点（如"用法"行）
--
-- 所有面板共用底部同一个窗口（和 IDEA 的工具窗口一样，后打开的替换前一个），每个面板有自己的缓冲区。
local M = {}

local api = vim.api
local ns = api.nvim_create_namespace("kit_tree")
local ns_preview = api.nvim_create_namespace("kit_tree_preview")
local FT = "kit_tree"
local HEIGHT = 12

M.panels = {} -- name -> panel
M.last = nil -- 最近一次显示的面板（Ctrl+Alt+↑/↓ 作用于它）

-- 配色：链接到主题（theme.lua 的 IDEA 配色）里已有的组，换主题时跟着变
local function setup_hl()
  local links = {
    KitTreeTitle = "Title",
    KitTreeDim = "Comment",
    KitTreeCount = "Comment",
    KitTreeLnum = "LineNr",
    KitTreeExpander = "Comment",
    KitTreeLoading = "Comment",
    KitTreeMatch = "LspReferenceText",
    KitTreeRead = "LspReferenceRead",
    KitTreeWrite = "LspReferenceWrite",
    KitTreeWriteTag = "DiagnosticWarn",
    KitTreeReadTag = "DiagnosticInfo",
    KitTreeCurrent = "Function",
    KitTreePreview = "Search",
    KitTreeHint = "Special",
  }
  for k, v in pairs(links) do api.nvim_set_hl(0, k, { link = v, default = true }) end
end
setup_hl()
api.nvim_create_autocmd("ColorScheme", { group = api.nvim_create_augroup("kit_tree_hl", { clear = true }), callback = setup_hl })

-- 图标：优先 mini.icons（LazyVim 已装），没有时用简单字符
function M.icon(category, name, fallback)
  local ok, mi = pcall(require, "mini.icons")
  if ok then
    local ok2, icon, hl = pcall(mi.get, category, name)
    if ok2 and icon then return icon, hl end
  end
  return fallback or "•", "KitTreeDim"
end

-- ---------------------------------------------------------------- 树数据工具

-- 给子节点设置 parent 指针
local function adopt(parent, children)
  for _, c in ipairs(children or {}) do
    c.parent = parent
    adopt(c, c.children)
  end
end

local function expandable(node)
  if node.children then return #node.children > 0 end
  return node.load ~= nil
end
M.expandable = expandable

-- 深度优先遍历所有已加载的节点（不管是否展开）
function M.walk(roots, fn)
  local function rec(list, depth)
    for _, n in ipairs(list or {}) do
      if fn(n, depth) == false then return false end
      if rec(n.children, depth + 1) == false then return false end
    end
  end
  rec(roots, 0)
end

local function node_text(node)
  local s = {}
  for _, c in ipairs(node.chunks or {}) do s[#s + 1] = c[1] end
  return table.concat(s)
end
M.node_text = node_text

-- ---------------------------------------------------------------- 面板

local Panel = {}
Panel.__index = Panel

-- opts: name（面板标识）、title（标题，字符串或返回字符串的函数）、hint（标题行右侧的切换选项提示）、
--       keys = { [lhs] = { fn = function(panel) end, desc = "说明" } }、empty（没有结果时显示的文字）
function M.new(opts)
  local p = M.panels[opts.name]
  if not p then
    p = setmetatable({ name = opts.name, preview = true, roots = {}, lines = {}, gen = 0 }, Panel)
    M.panels[opts.name] = p
  end
  p.title = opts.title or p.title or opts.name
  p.hint = opts.hint
  p.keys = opts.keys or p.keys or {}
  p.empty = opts.empty or "没有结果"
  p.loading_text = nil
  return p
end

function M.get(name) return M.panels[name] end

-- 当前标签页里显示任一面板的窗口（所有面板共用一个底部窗口）
local function find_panel_win()
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if vim.bo[api.nvim_win_get_buf(w)].filetype == FT then return w end
  end
end

local function is_code_win(w)
  if not (w and api.nvim_win_is_valid(w)) then return false end
  if api.nvim_win_get_config(w).relative ~= "" then return false end
  local b = api.nvim_win_get_buf(w)
  return vim.bo[b].filetype ~= FT and (vim.bo[b].buftype == "" or vim.bo[b].buftype == "nofile" and vim.api.nvim_buf_get_name(b):match("^jdt://"))
end

-- 跳转/预览用的代码窗口：打开面板时所在的窗口；它被关掉了就找另一个普通窗口；都没有就在面板上方新建
function Panel:code_win()
  if is_code_win(self.target) and api.nvim_win_get_tabpage(self.target) == api.nvim_get_current_tabpage() then
    return self.target
  end
  for _, w in ipairs(api.nvim_tabpage_list_wins(0)) do
    if is_code_win(w) then self.target = w return w end
  end
  local cur = api.nvim_get_current_win()
  if self.win and api.nvim_win_is_valid(self.win) then api.nvim_set_current_win(self.win) end
  vim.cmd("aboveleft new")
  self.target = api.nvim_get_current_win()
  if api.nvim_win_is_valid(cur) then api.nvim_set_current_win(cur) end
  return self.target
end

function Panel:ensure_buf()
  if self.buf and api.nvim_buf_is_valid(self.buf) then return self.buf end
  local b = api.nvim_create_buf(false, true)
  self.buf = b
  vim.bo[b].buftype = "nofile"
  vim.bo[b].bufhidden = "hide"
  vim.bo[b].swapfile = false
  vim.bo[b].modifiable = false
  vim.bo[b].filetype = FT
  pcall(api.nvim_buf_set_name, b, "kit://" .. self.name)
  self:map_keys()
  local group = api.nvim_create_augroup("kit_tree_" .. self.name, { clear = true })
  api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = b,
    callback = function()
      -- 标题行之外的位置变化时预览（去抖：按住方向键连续移动时只预览停下的那一行）
      self.preview_token = (self.preview_token or 0) + 1
      local token = self.preview_token
      vim.defer_fn(function()
        if token == self.preview_token and self.preview and api.nvim_get_current_buf() == b then
          self:preview_node(self:cursor_node())
        end
      end, 60)
    end,
  })
  api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = b,
    callback = function() M.last = self end,
  })
  return b
end

-- 打开（或切换到）面板窗口；focus=false 时焦点留在原窗口
function Panel:show(focus)
  local cur = api.nvim_get_current_win()
  if is_code_win(cur) then self.target = cur end
  self:ensure_buf()
  local w = find_panel_win()
  if not w then
    vim.cmd("botright " .. HEIGHT .. "split")
    w = api.nvim_get_current_win()
  end
  self.win = w
  api.nvim_win_set_buf(w, self.buf)
  local wo = vim.wo[w]
  wo.number, wo.relativenumber, wo.signcolumn, wo.foldcolumn = false, false, "no", "0"
  wo.wrap, wo.spell, wo.list, wo.cursorline, wo.winfixheight = false, false, false, true, true
  wo.statuscolumn = ""
  wo.foldenable = false
  M.last = self
  self:update_title()
  if focus == false then
    if api.nvim_win_is_valid(cur) then api.nvim_set_current_win(cur) end
  else
    api.nvim_set_current_win(w)
  end
  return w
end

function Panel:is_visible()
  return self.win and api.nvim_win_is_valid(self.win) and api.nvim_win_get_buf(self.win) == self.buf
end

function Panel:close()
  self:clear_preview()
  if self:is_visible() then
    -- 预览时打开的文件保留在代码窗口里，补上"已列出"标记让它出现在标签栏
    local cw = self.target
    if is_code_win(cw) then vim.bo[api.nvim_win_get_buf(cw)].buflisted = true end
    if #api.nvim_tabpage_list_wins(0) > 1 then
      pcall(api.nvim_win_close, self.win, true)
    else
      pcall(vim.cmd, "enew")
    end
  end
  self.win = nil
end

function Panel:title_text()
  local t = type(self.title) == "function" and self.title(self) or self.title
  return t
end

-- 顶部一行（winbar）：标题 + 切换选项提示
function Panel:update_title()
  if not self:is_visible() then return end
  local function esc(s) return (tostring(s or ""):gsub("%%", "%%%%")) end
  local parts = { "%#KitTreeTitle# " .. esc(self:title_text()) }
  if self.loading_text then parts[#parts + 1] = "  %#KitTreeLoading#" .. esc(self.loading_text) end
  parts[#parts + 1] = "%=%#KitTreeDim#"
  local hint = {}
  if self.hint then hint[#hint + 1] = type(self.hint) == "function" and self.hint(self) or self.hint end
  hint[#hint + 1] = "p 预览:" .. (self.preview and "开" or "关")
  hint[#hint + 1] = "? 按键 "
  parts[#parts + 1] = esc(table.concat(hint, "  "))
  vim.wo[self.win].winbar = table.concat(parts)
end

-- 替换整棵树（新的查找结果）
function Panel:set_roots(roots)
  self.gen = self.gen + 1
  self.roots = roots or {}
  adopt(nil, self.roots)
  self.loading_text = nil
  self:render()
  if self:is_visible() then
    local lnum = 1
    -- 光标放在第一个"用法"行（IDEA 打开后选中第一个结果）
    for i, n in ipairs(self.lines) do
      if n and n.occurrence then lnum = i break end
    end
    if self.focus_first ~= false and #self.lines > 0 then
      pcall(api.nvim_win_set_cursor, self.win, { math.min(lnum, #self.lines), 0 })
    end
  end
end

-- 查找进行中：显示"加载中"提示
function Panel:set_loading(text)
  self.gen = self.gen + 1
  self.roots = {}
  self.loading_text = text or "加载中…"
  self:render()
end

-- 把可见节点画成文本行，self.lines[行号] = 节点（"加载中…"这类占位行对应 false）
function Panel:render()
  local b = self:ensure_buf()
  local text, marks, lines = {}, {}, {}
  local function add(node, depth)
    local exp = " "
    if node.loading then
      exp = "▾"
    elseif expandable(node) then
      exp = node.expanded and "▾" or "▸"
    end
    local prefix = string.rep("  ", depth) .. exp .. " "
    local s = prefix
    local hls = { { 0, #prefix, "KitTreeExpander" } }
    if node.icon then
      hls[#hls + 1] = { #s, #s + #node.icon, node.icon_hl or "KitTreeDim" }
      s = s .. node.icon .. " "
    end
    for _, c in ipairs(node.chunks or {}) do
      local t = (c[1] or ""):gsub("\n", " ")
      if c[2] then hls[#hls + 1] = { #s, #s + #t, c[2] } end
      s = s .. t
    end
    text[#text + 1] = s
    lines[#lines + 1] = node
    marks[#text] = hls
    if node.loading then
      text[#text + 1] = string.rep("  ", depth + 1) .. "  加载中…"
      lines[#lines + 1] = false
      marks[#text] = { { 0, #text[#text], "KitTreeLoading" } }
    elseif node.expanded then
      for _, c in ipairs(node.children or {}) do add(c, depth + 1) end
    end
  end
  for _, r in ipairs(self.roots) do add(r, 0) end
  if #text == 0 then
    text = { "  " .. (self.loading_text or self.empty) }
    lines = { false }
    marks = { { { 0, #text[1], "KitTreeLoading" } } }
  end
  self.lines = lines
  vim.bo[b].modifiable = true
  api.nvim_buf_set_lines(b, 0, -1, false, text)
  vim.bo[b].modifiable = false
  api.nvim_buf_clear_namespace(b, ns, 0, -1)
  for i, hls in pairs(marks) do
    for _, h in ipairs(hls) do
      if h[2] > h[1] then
        api.nvim_buf_set_extmark(b, ns, i - 1, h[1], { end_col = h[2], hl_group = h[3], priority = 100 + (h[3] == "KitTreeExpander" and 0 or 1) })
      end
    end
  end
  self:update_title()
end

function Panel:lnum_of(node)
  for i, n in ipairs(self.lines) do
    if n == node then return i end
  end
end

function Panel:cursor_node()
  if not self:is_visible() then return nil end
  local l = api.nvim_win_get_cursor(self.win)[1]
  return self.lines[l] or nil
end

function Panel:set_cursor(node)
  local l = self:lnum_of(node)
  if l and self:is_visible() then api.nvim_win_set_cursor(self.win, { l, 0 }) end
end

-- 展开节点；需要时异步加载子节点，加载完调用 cb(node)
function Panel:expand(node, cb)
  if not node or not expandable(node) then
    if cb then cb(node) end
    return
  end
  node.expanded = true
  if node.children or not node.load then
    self:render()
    if cb then cb(node) end
    return
  end
  if node.loading then return end
  node.loading = true
  local gen = self.gen
  self:render()
  local ok, err = pcall(node.load, node, function(children)
    vim.schedule(function()
      if gen ~= self.gen then return end -- 期间换了新的查找结果
      node.loading = false
      node.children = children or {}
      adopt(node, node.children)
      self:render()
      if cb then cb(node) end
    end)
  end)
  if not ok then
    node.loading = false
    node.children = {}
    self:render()
    vim.notify("加载子节点出错：" .. tostring(err), vim.log.levels.WARN)
  end
end

function Panel:collapse(node)
  node.expanded = false
  self:render()
  self:set_cursor(node)
end

-- ---------------------------------------------------------------- 预览 / 跳转

-- uri 对应的缓冲区（jdt:// 依赖库文件由 nvim-jdtls 的 BufReadCmd 读取内容）
local function load_buf(uri)
  local b = vim.uri_to_bufnr(uri)
  if not api.nvim_buf_is_loaded(b) then
    pcall(vim.fn.bufload, b)
  end
  return b
end
M.load_buf = load_buf

local function loc_pos(b, loc)
  local r = loc.range.start
  local line = api.nvim_buf_get_lines(b, r.line, r.line + 1, false)[1] or ""
  local col = r.character
  local ok, c = pcall(vim.str_byteindex, line, loc.encoding or "utf-16", col, false)
  if ok then col = c end
  return r.line + 1, math.min(col, #line)
end

local function loc_end(b, loc)
  local r = loc.range["end"]
  local line = api.nvim_buf_get_lines(b, r.line, r.line + 1, false)[1] or ""
  local ok, c = pcall(vim.str_byteindex, line, loc.encoding or "utf-16", r.character, false)
  return r.line, ok and math.min(c, #line) or #line
end

-- 在代码窗口里显示位置；focus=true 时焦点移到代码窗口（Enter 跳转），否则只是预览
function Panel:show_loc(loc, focus)
  local win = self:code_win()
  -- 在代码窗口里读入文件：读入时的自动命令（恢复上次位置、折叠 import 等）作用于代码窗口而不是面板
  local b
  api.nvim_win_call(win, function() b = load_buf(loc.uri) end)
  if not api.nvim_buf_is_valid(b) then return end
  local prev_listed = vim.bo[b].buflisted
  -- 跳转时先进入代码窗口再切换缓冲区、设置光标：反过来做的话，进入窗口时的自动命令可能把光标挪走
  if focus then
    api.nvim_set_current_win(win)
    vim.cmd("normal! m'")
  end
  if api.nvim_win_get_buf(win) ~= b then
    api.nvim_win_call(win, function() vim.cmd("keepjumps buffer " .. b) end)
  end
  -- 预览时不把文件加进标签栏（IDEA 的预览也不新开标签）；Enter 跳转或关闭面板时才算真正打开
  vim.bo[b].buflisted = focus and true or prev_listed
  local lnum, col = loc_pos(b, loc)
  -- 反编译的依赖库文件里 jdtls 给出的位置常是 (0,0)：按名字找声明所在行
  if lnum == 1 and col == 0 and loc.symbol then
    local pat = loc.kind == "type" and ("\\v<(class|interface|enum|record|\\@interface)\\s+" .. loc.symbol .. ">")
      or ("\\v<" .. loc.symbol .. "\\s*\\(")
    local found
    api.nvim_win_call(win, function()
      vim.api.nvim_win_set_cursor(win, { 1, 0 })
      found = vim.fn.search(pat, "cW")
    end)
    if found > 0 then
      local line = api.nvim_buf_get_lines(b, found - 1, found, false)[1]
      local s = vim.fn.match(line, pat)
      lnum, col = found, math.max(s, 0)
      if loc.kind == "type" then col = (line:find(loc.symbol, col + 1, true) or col + 1) - 1 end
    end
  end
  pcall(api.nvim_win_set_cursor, win, { lnum, col })
  api.nvim_win_call(win, function() vim.cmd("normal! zvzz") end)
  self:clear_preview()
  local el, ec = loc_end(b, loc)
  pcall(api.nvim_buf_set_extmark, b, ns_preview, lnum - 1, col, { end_row = el, end_col = ec, hl_group = "KitTreePreview", priority = 200 })
  self.preview_buf = b
  self.preview_seq = (self.preview_seq or 0) + 1
  return win
end

function Panel:clear_preview()
  if self.preview_buf and api.nvim_buf_is_valid(self.preview_buf) then
    api.nvim_buf_clear_namespace(self.preview_buf, ns_preview, 0, -1)
  end
end

-- 跳过去后高亮停留一会儿再清掉，方便看清是哪一处（期间又预览了别处则不清）
function Panel:clear_preview_later()
  local seq = self.preview_seq
  vim.defer_fn(function()
    if seq == self.preview_seq then self:clear_preview() end
  end, 1500)
end

function Panel:preview_node(node)
  if node and node.loc then
    -- 已经在代码窗口里显示过的用法：Ctrl+Alt+↓ 从它的下一个开始
    self.visited = node
    pcall(self.show_loc, self, node.loc, false)
  end
end

-- Enter：有位置的节点跳转（面板保留，焦点去代码窗口），分组节点展开/折叠
function Panel:activate(node)
  node = node or self:cursor_node()
  if not node then return end
  if node.loc then
    self.visited = node
    self:show_loc(node.loc, true)
    self:clear_preview_later()
  elseif expandable(node) then
    if node.expanded then self:collapse(node) else self:expand(node) end
  end
end

-- ---------------------------------------------------------------- 逐个跳转（Ctrl+Alt+↑/↓）

-- 按树的顺序列出所有"用法"节点（含折叠起来的）
function Panel:occurrences()
  local res = {}
  M.walk(self.roots, function(n) if n.occurrence and n.loc then res[#res + 1] = n end end)
  return res
end

-- 跳到下一个 / 上一个用法：展开所在分组、面板光标跟随，代码窗口跳到该处；焦点不变
function Panel:next_occurrence(dir)
  local occ = self:occurrences()
  if #occ == 0 then
    vim.notify("没有可跳转的用法", vim.log.levels.INFO)
    return
  end
  local cur = self:cursor_node()
  local idx
  if cur then
    -- 光标所在节点在全部节点中的顺序
    local order, pos = {}, 0
    M.walk(self.roots, function(n) pos = pos + 1 order[n] = pos end)
    local cp = order[cur] or 0
    if cur.occurrence and self.visited == cur then
      for i, n in ipairs(occ) do if n == cur then idx = i + dir end end
    elseif dir > 0 then
      for i, n in ipairs(occ) do if order[n] >= cp then idx = i break end end
    else
      for i = #occ, 1, -1 do if order[occ[i]] <= cp then idx = i break end end
    end
  end
  idx = idx or (dir > 0 and 1 or #occ)
  if idx > #occ or idx < 1 then
    vim.notify(dir > 0 and "已经是最后一个用法，从头开始" or "已经是第一个用法，从末尾开始", vim.log.levels.INFO)
    idx = dir > 0 and 1 or #occ
  end
  local node = occ[idx]
  local p = node.parent
  while p do p.expanded = true p = p.parent end
  local was_visible = self:is_visible()
  if not was_visible then self:show(false) end
  self:render()
  self:set_cursor(node)
  self.visited = node
  -- 焦点在面板里：只预览，焦点留在面板；否则代码窗口跳过去（记入跳转历史，Ctrl+Alt+← 能回来）
  local in_panel = api.nvim_get_current_win() == self.win
  self:show_loc(node.loc, not in_panel)
  if not in_panel then self:clear_preview_later() end
  return node
end

-- ---------------------------------------------------------------- 按键

function Panel:help_lines()
  local l = {
    "Enter / 双击   跳转到代码（面板保留）；分组节点展开/折叠",
    "→ / l          展开（需要时加载子节点）",
    "← / h          折叠，或回到上一级",
    "p              光标移动时自动在代码窗口预览 开/关",
    "Ctrl+Alt+↓/↑   下一个 / 上一个用法",
    "q / Esc        关闭面板",
  }
  local extra = {}
  for lhs, k in pairs(self.keys) do
    if k.desc then extra[#extra + 1] = string.format("%-14s %s", k.label or lhs, k.desc) end
  end
  table.sort(extra)
  vim.list_extend(l, extra)
  return l
end

function Panel:map_keys()
  local b = self.buf
  local function m(lhs, fn, desc)
    vim.keymap.set("n", lhs, function() fn(self) end, { buffer = b, nowait = true, silent = true, desc = desc })
  end
  m("<CR>", function(p) p:activate() end, "跳转")
  m("<2-LeftMouse>", function(p) p:activate() end, "跳转")
  for _, k in ipairs({ "l", "<Right>" }) do
    m(k, function(p)
      local n = p:cursor_node()
      if not n then return end
      if expandable(n) and not n.expanded then
        p:expand(n)
      elseif n.expanded and n.children and n.children[1] then
        p:set_cursor(n.children[1])
      end
    end, "展开")
  end
  for _, k in ipairs({ "h", "<Left>" }) do
    m(k, function(p)
      local n = p:cursor_node()
      if not n then return end
      if n.expanded and expandable(n) then
        p:collapse(n)
      elseif n.parent then
        p:set_cursor(n.parent)
      end
    end, "折叠 / 上一级")
  end
  m("p", function(p)
    p.preview = not p.preview
    if not p.preview then p:clear_preview() end
    p:update_title()
    vim.notify("自动预览：" .. (p.preview and "开" or "关"), vim.log.levels.INFO)
  end, "自动预览 开/关")
  m("q", function(p) p:close() end, "关闭")
  m("<Esc>", function(p) p:close() end, "关闭")
  m("?", function(p)
    vim.notify(table.concat(p:help_lines(), "\n"), vim.log.levels.INFO, { title = p:title_text() })
  end, "显示按键")
  for lhs, k in pairs(self.keys) do
    m(lhs, k.fn, k.desc)
  end
end

-- 重新设置自定义按键（面板复用时 keys 可能变化）
function Panel:refresh_keys()
  if self.buf and api.nvim_buf_is_valid(self.buf) then self:map_keys() end
end

M.Panel = Panel
return M
