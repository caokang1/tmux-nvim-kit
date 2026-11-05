-- 查找用法面板（IDEA 的 Find 工具窗口，Alt+F7）
--   * 用法按 生产代码/测试代码/依赖库 → 模块（最近 pom.xml 的 artifactId）→ 包 → 文件 → 行 分组成树
--   * 字段、变量的用法标出"读 / 写"（按该处代码是否赋值、++/-- 判断，不用为每个文件再问语言服务）
--   * Enter 跳转但面板保留；Ctrl+Alt+↓/↑ 在面板没有焦点时也能逐个跳到下一个/上一个用法
--   * Ctrl+Alt+F7 保留原来的弹框（快速查看）
local K = require("config.idea_keys")
local Tree = require("config.kit.tree")

local M = {}
local api = vim.api

-- ---------------------------------------------------------------- 读 / 写 判断

-- text 是该行代码，s/e 是标识符的字节范围 [s, e)（0 基）。返回 "write" 或 "read"
function M.access_kind(text, s, e)
  local before, after = text:sub(1, s), text:sub(e + 1)
  if after:match("^%s*%+%+") or after:match("^%s*%-%-") then return "write" end
  if before:match("%+%+%s*$") or before:match("%-%-%s*$") then return "write" end
  if after:match("^%s*==") then return "read" end
  -- =、+=、-=、*=、/=、%=、&=、|=、^=、<<=、>>=、>>>=（排除 ==、!=、<=、>=）
  if after:match("^%s*[%+%-%*/%%&|%^]?=") or after:match("^%s*<<=") or after:match("^%s*>>>?=") then
    return "write"
  end
  return "read"
end

-- 光标处的符号是不是变量/字段（是才区分读写；方法、类不区分）
function M.is_variable_at(buf, row, col)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { row, col } })
  if not ok or not node or node:type() ~= "identifier" then return false end
  local parent = node:parent()
  if not parent then return false end
  local pt = parent:type()
  local never = {
    method_declaration = true, constructor_declaration = true, class_declaration = true,
    interface_declaration = true, enum_declaration = true, record_declaration = true,
    annotation_type_declaration = true, method_reference = true, marker_annotation = true,
    annotation = true, scoped_identifier = true, package_declaration = true, import_declaration = true,
  }
  if never[pt] then return false end
  if pt == "method_invocation" then
    local name = parent:field("name")[1]
    if name and name:id() == node:id() then return false end
  end
  -- 标识符后面紧跟 "(" 是方法调用
  local line = api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local _, _, ec = node:range()
  if line:sub(ec + 1):match("^%s*%(") then return false end
  return true
end

-- ---------------------------------------------------------------- 文件信息（模块、包、是否测试）

local pom_cache = {} -- pom.xml 路径 -> artifactId

local function artifact_id(pom)
  if pom_cache[pom] == nil then
    local ok, lines = pcall(vim.fn.readfile, pom)
    local id = false
    if ok then
      local s = table.concat(lines, "\n"):gsub("<parent>.-</parent>", ""):gsub("<!%-%-.-%-%->", "")
      id = s:match("<artifactId>%s*(.-)%s*</artifactId>") or false
    end
    pom_cache[pom] = id
  end
  return pom_cache[pom] or nil
end

-- 文件所在模块：最近的 pom.xml 的 artifactId；没有 pom.xml 时用 build.gradle 所在目录名
function M.module_of(fname)
  local found = vim.fs.find({ "pom.xml", "build.gradle", "build.gradle.kts" }, { path = vim.fs.dirname(fname), upward = true })[1]
  if not found then return "（项目）" end
  if found:match("pom%.xml$") then
    return artifact_id(found) or vim.fs.basename(vim.fs.dirname(found))
  end
  return vim.fs.basename(vim.fs.dirname(found))
end

function M.is_test(fname)
  return fname:find("/src/test/", 1, true) ~= nil
end

-- jdt://contents/<jar>/<包>/<类>.class?... → jar、包、类名
function M.parse_jdt(uri)
  local jar, pkg, cls = uri:match("^jdt://contents/([^/]+)/([^/]+)/([^/?]+)")
  if not jar then return nil end
  return { jar = vim.uri_decode and vim.uri_decode(jar) or jar, package = pkg, class = cls }
end

-- 读取文件的所有行：已加载的缓冲区用缓冲区内容（可能还没保存），否则读磁盘；jdt:// 由 jdtls 提供
local function file_lines(uri, cache)
  if cache[uri] then return cache[uri] end
  local lines
  if uri:match("^file:") then
    local fname = vim.uri_to_fname(uri)
    local b = vim.fn.bufnr(fname)
    if b > 0 and api.nvim_buf_is_loaded(b) then
      lines = api.nvim_buf_get_lines(b, 0, -1, false)
    else
      local ok, l = pcall(vim.fn.readfile, fname)
      lines = ok and l or {}
    end
  else
    -- jdt://（依赖库）：内容要逐个向 jdtls 同步请求反编译，用法多时会卡很久，所以只用已经打开过的；
    -- 没打开过的只显示行号，跳转时再加载
    local b = vim.fn.bufnr(uri)
    lines = b > 0 and api.nvim_buf_is_loaded(b) and api.nvim_buf_get_lines(b, 0, -1, false) or {}
  end
  cache[uri] = lines
  return lines
end

local function package_of(lines)
  for i = 1, math.min(#lines, 50) do
    local p = lines[i]:match("^%s*package%s+([%w_%.]+)")
    if p then return p end
  end
end

-- 把语言服务返回的位置列表整理成带代码行、模块、包等信息的条目
-- opts.variable=true 时为每处用法判断读/写；opts.encoding 是位置的编码（默认 utf-16）
function M.collect(locations, opts)
  opts = opts or {}
  local enc = opts.encoding or "utf-16"
  local cache, items = {}, {}
  for _, loc in ipairs(locations or {}) do
    local uri = loc.uri or loc.targetUri
    local range = loc.range or loc.targetSelectionRange or loc.targetRange
    if uri and range then
      local lines = file_lines(uri, cache)
      local row = range.start.line
      local text = lines[row + 1] or ""
      local function bytecol(c)
        local ok, b = pcall(vim.str_byteindex, text, enc, c, false)
        return ok and math.min(b, #text) or math.min(c, #text)
      end
      local s = bytecol(range.start.character)
      local e = range["end"].line == row and bytecol(range["end"].character) or #text
      local it = { uri = uri, range = range, encoding = enc, lnum = row + 1, col = s, end_col = e, text = text }
      local jdt = not uri:match("^file:") and M.parse_jdt(uri)
      if uri:match("^file:") then
        local fname = vim.uri_to_fname(uri)
        it.fname = fname
        it.file = vim.fs.basename(fname)
        it.group = M.is_test(fname) and "test" or "main"
        it.module = M.module_of(fname)
        it.package = package_of(lines) or "（默认包）"
      else
        it.group = "lib"
        it.file = jdt and jdt.class or uri:match("([^/?]+)%?") or uri
        it.module = jdt and jdt.jar or "依赖库"
        it.package = jdt and jdt.package or package_of(lines) or "（默认包）"
        it.fname = uri
      end
      if opts.variable then it.access = M.access_kind(text, s, e) end
      items[#items + 1] = it
    end
  end
  return items
end

-- ---------------------------------------------------------------- 构建树

local GROUPS = {
  main = { order = 1, label = "生产代码", icon = "󰏗" },
  test = { order = 2, label = "测试代码", icon = "󰙨" },
  lib = { order = 3, label = "依赖库", icon = "" },
}

local function count_label(n)
  return { "  " .. n .. " 处用法", "KitTreeCount" }
end

-- 一行用法：行号 + 代码（去掉缩进，匹配处高亮）+ 读/写标记
local function usage_chunks(it)
  local text = it.text
  if text == "" then
    return { { string.format("%4d  ", it.lnum), "KitTreeLnum" }, { "（依赖库代码，Enter 打开查看）", "KitTreeDim" } }
  end
  local indent = #(text:match("^%s*"))
  local s, e = math.max(it.col - indent, 0), math.max(it.end_col - indent, 0)
  local code = text:sub(indent + 1)
  local max = 200
  local ch = {
    { string.format("%4d  ", it.lnum), "KitTreeLnum" },
    { code:sub(1, s) },
    { code:sub(s + 1, e), it.access == "write" and "KitTreeWrite" or it.access == "read" and "KitTreeRead" or "KitTreeMatch" },
    { code:sub(e + 1, max) },
  }
  if it.access then
    ch[#ch + 1] = it.access == "write" and { "  写", "KitTreeWriteTag" } or { "  读", "KitTreeReadTag" }
  end
  return ch
end

-- items（M.collect 的结果）→ 树：生产/测试/依赖库 → 模块 → 包 → 文件 → 行。分组节点默认全部展开（同 IDEA）
function M.build_tree(items)
  local roots, index = {}, {}
  local function child(parent_list, key, make)
    index[parent_list] = index[parent_list] or {}
    local n = index[parent_list][key]
    if not n then
      n = make()
      n.children = {}
      n.expanded = true
      n.count = 0
      index[parent_list][key] = n
      parent_list[#parent_list + 1] = n
    end
    n.count = n.count + 1
    return n
  end
  local file_icon = function(name) return Tree.icon("file", name, "") end
  for _, it in ipairs(items) do
    local g = GROUPS[it.group]
    local gn = child(roots, it.group, function()
      return { kind = "group", key = it.group, label = g.label, order = g.order, icon = g.icon, icon_hl = "Directory" }
    end)
    local mn = child(gn.children, it.module, function()
      local icon, hl = Tree.icon("lsp", "Module", "")
      return { kind = "module", label = it.module, icon = icon, icon_hl = hl }
    end)
    local pn = child(mn.children, it.package, function()
      local icon, hl = Tree.icon("lsp", "Package", "")
      return { kind = "package", label = it.package, icon = icon, icon_hl = hl }
    end)
    local fn = child(pn.children, it.uri, function()
      local icon, hl = file_icon(it.file)
      return { kind = "file", label = it.file, icon = icon, icon_hl = hl, uri = it.uri }
    end)
    fn.children[#fn.children + 1] = {
      kind = "usage",
      item = it,
      occurrence = true,
      access = it.access,
      chunks = usage_chunks(it),
      loc = { uri = it.uri, range = it.range, encoding = it.encoding },
    }
  end
  -- 排序：分组按 生产→测试→依赖库，其余按名字，行按行号
  local function sort(list)
    if not list or #list == 0 then return end
    if list[1].kind == "usage" then
      table.sort(list, function(a, b)
        if a.item.lnum ~= b.item.lnum then return a.item.lnum < b.item.lnum end
        return a.item.col < b.item.col
      end)
      return
    end
    table.sort(list, function(a, b)
      if a.order and b.order then return a.order < b.order end
      return a.label < b.label
    end)
    for _, n in ipairs(list) do
      n.chunks = { { n.label, n.kind == "file" and "Normal" or (n.kind == "group" and "KitTreeTitle" or nil) }, count_label(n.count) }
      sort(n.children)
    end
  end
  sort(roots)
  return roots
end

-- ---------------------------------------------------------------- 面板

M.state = {} -- 最近一次查找：{ symbol, total, reads, writes }

local function title()
  local s = M.state
  if not s.symbol then return "查找用法" end
  local t = "查找用法：" .. s.symbol
  if s.total then
    t = t .. "  共 " .. s.total .. " 处"
    if s.variable and s.total > 0 then t = t .. "（读 " .. s.reads .. "，写 " .. s.writes .. "）" end
  end
  return t
end

function M.panel()
  return Tree.new({
    name = "usages",
    title = title,
    hint = "Enter 跳转  →/← 展开/折叠  Ctrl+Alt+↓/↑ 下/上一个",
    empty = "没有找到用法",
    keys = {},
  })
end

local function lsp_client(buf, method)
  return vim.lsp.get_clients({ bufnr = buf, method = method })[1]
end

-- Alt+F7：在底部面板里列出光标处符号的用法（不含声明，同 IDEA）；cb(panel) 在结果显示后调用（测试用）
function M.find_usages(cb)
  local buf = api.nvim_get_current_buf()
  local client = lsp_client(buf, "textDocument/references")
  if not client then
    vim.notify("当前文件没有语言服务，无法查找用法", vim.log.levels.WARN)
    return
  end
  local pos = api.nvim_win_get_cursor(0)
  local symbol = vim.fn.expand("<cword>")
  local variable = M.is_variable_at(buf, pos[1] - 1, pos[2])
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  params.context = { includeDeclaration = false }
  local p = M.panel()
  M.state = { symbol = symbol, variable = variable }
  p:show(true)
  p:set_loading("正在查找 " .. symbol .. " 的用法…")
  local gen = p.gen
  client:request("textDocument/references", params, function(err, result)
    if gen ~= p.gen then return end
    if err then
      p.loading_text = nil
      p.empty = "查找用法出错：" .. tostring(err.message or err)
      p:set_roots({})
      return
    end
    local items = M.collect(result or {}, { variable = variable, encoding = client.offset_encoding })
    local reads, writes = 0, 0
    for _, it in ipairs(items) do
      if it.access == "write" then writes = writes + 1 elseif it.access == "read" then reads = reads + 1 end
    end
    M.state.total, M.state.reads, M.state.writes = #items, reads, writes
    p.empty = "没有找到 " .. symbol .. " 的用法"
    p:set_roots(M.build_tree(items))
    if cb then cb(p) end
  end, buf)
end

-- Ctrl+Alt+F7：原来的弹框（快速查看用法）。供其他模块调用（如"在声明处按 Ctrl+B 显示用法"）
function M.show_popup(opts)
  Snacks.picker.lsp_references(opts)
end

-- Ctrl+Alt+↓/↑：在最近显示的面板（通常是查找用法）里跳到下一个/上一个用法
function M.next(dir)
  local p = Tree.last or Tree.get("usages")
  if not p or #p:occurrences() == 0 then
    vim.notify("没有查找结果：先按 Alt+F7 查找用法", vim.log.levels.INFO)
    return
  end
  return p:next_occurrence(dir)
end

K.map(K.NI, "<M-F7>", K.n(function() M.find_usages() end), "查找用法（底部面板）")
K.map(K.NI, "<C-M-F7>", K.n(function() M.show_popup() end), "查找用法（弹框）")
K.map(K.NI, "<C-M-Down>", K.n(function() M.next(1) end), "下一个用法（查找结果）")
K.map(K.NI, "<C-M-Up>", K.n(function() M.next(-1) end), "上一个用法（查找结果）")

return M
