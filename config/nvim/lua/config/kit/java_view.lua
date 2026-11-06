-- Java 文件阅读（IDEA 打开 .java 时的样子）：
--   * import 块默认折叠成一行 "󰋺 import ... (12)"，其他代码保持展开
--   * Alt+- / Alt+= 折叠 / 展开当前块；Alt+Shift+- / Alt+Shift+= 全部折叠（只折方法体，类本身不折）/ 全部展开
--     （IDEA 的 Ctrl+- / Ctrl+= 在终端里是字号缩放，不占用；za / zM / zR 等 Vim 原有按键照常可用）
--   * Ctrl+F12 文件结构弹框里再按 Ctrl+F12：显示 / 隐藏继承来的成员（灰色标出来自哪个父类）
local K = require("config.idea_keys")
local M = {}

-- ================= 折叠 =================
-- Java 窗口统一用 treesitter 计算折叠：打开文件时就有（不用等 jdtls 启动），import 块、方法体、类体都能折。
-- LazyVim 在 jdtls 附加后会改用 LSP 折叠，这里的设置是脚本显式设的，LazyVim 不会覆盖
local FOLDEXPR = "v:lua.vim.treesitter.foldexpr()"
local FOLDTEXT = "v:lua.require'config.kit.java_view'.foldtext()"

-- 折叠行显示：import 块 → "󰋺 import ... (条数)"；其他 → 第一行（带语法高亮）+ " ⋯ }"
local function line_chunks(buf, row, text)
  local hls = {}
  local ok, parser = pcall(vim.treesitter.get_parser, buf)
  if ok and parser then
    parser:for_each_tree(function(tree, ltree)
      local query = vim.treesitter.query.get(ltree:lang(), "highlights")
      if not query then return end
      for id, node in query:iter_captures(tree:root(), buf, row, row + 1) do
        local name = query.captures[id]
        if name ~= "spell" and name ~= "nospell" and not name:find("^_") then
          local sr, sc, er, ec = node:range()
          if sr <= row and er >= row then
            sc = sr < row and 0 or sc
            ec = er > row and #text or ec
            for c = sc + 1, math.min(ec, #text) do hls[c] = "@" .. name .. "." .. ltree:lang() end
          end
        end
      end
    end)
  end
  local chunks, cur, hl = {}, {}, nil
  local tab = (" "):rep(vim.bo[buf].tabstop)
  for c = 1, #text do
    local h = hls[c] or "Normal"
    if h ~= hl and #cur > 0 then
      chunks[#chunks + 1] = { table.concat(cur), hl }
      cur = {}
    end
    hl = h
    local ch = text:sub(c, c)
    cur[#cur + 1] = ch == "\t" and tab or ch
  end
  if #cur > 0 then chunks[#chunks + 1] = { table.concat(cur), hl } end
  return chunks
end

function M.foldtext()
  local buf = vim.api.nvim_get_current_buf()
  local s, e = vim.v.foldstart, vim.v.foldend
  local first = vim.fn.getline(s)
  if first:match("^%s*import%s") then
    local n = 0
    for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, s - 1, e, false)) do
      if l:match("^%s*import%s") then n = n + 1 end
    end
    return { { "󰋺 import ...", "Comment" }, { (" (%d)"):format(n), "Comment" } }
  end
  local ok, chunks = pcall(line_chunks, buf, s - 1, first)
  if not ok then chunks = { { first:gsub("\t", (" "):rep(vim.bo[buf].tabstop)), "Normal" } } end
  local last = vim.trim(vim.fn.getline(e))
  chunks[#chunks + 1] = { " ⋯ ", "Comment" }
  if last:match("^[%)%]}]") then
    chunks[#chunks + 1] = { last, "Normal" }
  elseif last:match("^%*/") then
    chunks[#chunks + 1] = { "*/", "Comment" }
  end
  return chunks
end

---import 块的行范围（1 基，含两端）；不足两行（折不起来）返回 nil
function M.import_range(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "java")
  if not ok or not parser then return end
  local root = parser:parse()[1]:root()
  local first, last
  for child in root:iter_children() do
    if child:type() == "import_declaration" then
      local sr, _, er = child:range()
      first = first or sr
      last = er
    end
  end
  if first and last > first then return first + 1, last + 1 end
end

-- 窗口里的 Java 缓冲区使用 treesitter 折叠
local function setup_win(win)
  local wo = vim.wo[win][0]
  if wo.foldexpr ~= FOLDEXPR then
    wo.foldmethod = "expr"
    wo.foldexpr = FOLDEXPR
  end
  wo.foldtext = FOLDTEXT
end

-- 同一窗口换成别的文件时，窗口选项会沿用 Java 的设置（LazyVim 看到不是默认值就不再改），这里还原成 LazyVim 的默认做法
local function restore_win(win, buf)
  local wo = vim.wo[win][0]
  if wo.foldtext == FOLDTEXT then wo.foldtext = "" end
  if wo.foldexpr == FOLDEXPR then
    local ft = vim.bo[buf].filetype
    local ok, have = pcall(function() return LazyVim.treesitter.have(ft, "folds") end)
    if ok and have then
      wo.foldmethod = "expr"
      wo.foldexpr = "v:lua.LazyVim.treesitter.foldexpr()"
    else
      wo.foldmethod = "indent"
      wo.foldexpr = "0"
    end
  end
end

---在 win 里折叠 import 块；折叠还没计算好时稍后重试（treesitter 解析是异步更新折叠的）
function M.fold_imports(win, tries)
  tries = tries or 100
  if not vim.api.nvim_win_is_valid(win) then return end
  local buf = vim.api.nvim_win_get_buf(win)
  if vim.bo[buf].filetype ~= "java" then return end
  local s, e = M.import_range(buf)
  if not s then return end
  vim.api.nvim_win_call(win, function()
    local cur = vim.api.nvim_win_get_cursor(win)[1]
    if cur >= s and cur <= e then return end -- 光标在 import 里（例如从堆栈跳到这里），不折
    if vim.fn.foldclosed(s) ~= -1 then return end
    if vim.fn.foldlevel(s) > 0 then pcall(vim.cmd, s .. "foldclose") end
    if vim.fn.foldclosed(s) == -1 and tries > 0 then
      vim.defer_fn(function() M.fold_imports(win, tries - 1) end, 10)
    end
  end)
end

-- 方法体 / 构造方法所在的行（1 基）：全部折叠时逐个折起这些块
function M.method_rows(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "java")
  if not ok or not parser then return {} end
  local root = parser:parse()[1]:root()
  local query = vim.treesitter.query.parse("java", [[
    (method_declaration body: (block) @b)
    (constructor_declaration) @b
    (compact_constructor_declaration) @b
  ]])
  local rows = {}
  for _, node in query:iter_captures(root, buf, 0, -1) do
    local sr, _, er = node:range()
    if er > sr then rows[#rows + 1] = sr + 1 end
  end
  return rows
end

---全部折叠：Java 里像 IDEA 一样折叠所有方法体和 import（类本身不折），其他文件 zM
function M.fold_all()
  if vim.bo.filetype ~= "java" then
    vim.cmd("normal! zM")
    return
  end
  setup_win(vim.api.nvim_get_current_win())
  vim.wo.foldlevel = 99
  local rows = M.method_rows(0)
  local s = M.import_range(0)
  if s then table.insert(rows, 1, s) end
  -- 从下往上折：内部类的方法先折，外层方法再折
  for i = #rows, 1, -1 do
    pcall(vim.cmd, rows[i] .. "foldclose")
  end
end

function M.unfold_all()
  vim.wo.foldlevel = 99
  pcall(vim.cmd, "normal! zv")
end

local group = vim.api.nvim_create_augroup("kit_java_view", { clear = true })
vim.api.nvim_create_autocmd({ "FileType", "BufWinEnter" }, {
  group = group,
  callback = function(ev)
    local win = vim.api.nvim_get_current_win()
    if vim.api.nvim_win_get_buf(win) ~= ev.buf then return end
    if vim.bo[ev.buf].filetype ~= "java" then
      restore_win(win, ev.buf)
      return
    end
    setup_win(win)
    -- 同一窗口里已经折过这个缓冲区（FileType 和 BufWinEnter 都会触发）就不再重复
    local key = ev.buf .. ":" .. vim.b[ev.buf].changedtick
    if vim.w[win].kit_java_folded == key then return end
    vim.w[win].kit_java_folded = key
    vim.schedule(function() M.fold_imports(win) end)
  end,
})
for _, win in ipairs(vim.api.nvim_list_wins()) do
  if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "java" then setup_win(win) end
end

local function fold_cmd(keys)
  return function() pcall(vim.cmd, "normal! " .. keys) end
end
K.map(K.NI, "<M-->", K.n(fold_cmd("zc")), "折叠当前块（IDEA: Ctrl+-）")
K.map(K.NI, "<M-=>", K.n(fold_cmd("zo")), "展开当前块（IDEA: Ctrl+=）")
-- Alt+Shift+- 在终端里到达时是 Alt+_，Alt+Shift+= 是 Alt++
K.map(K.NI, "<M-_>", K.n(M.fold_all), "全部折叠（IDEA: Ctrl+Shift+-）")
K.map(K.NI, "<M-+>", K.n(M.unfold_all), "全部展开（IDEA: Ctrl+Shift+=）")

-- ================= 文件结构：继承的成员 =================
local SYMBOL_KIND = vim.lsp.protocol.SymbolKind
local TYPE_KINDS = { Class = true, Interface = true, Enum = true, Struct = true }
local cache = {} -- buf → { tick, members }

-- 光标所在（或文件中第一个）顶层类型的类名位置，供 prepareTypeHierarchy 使用
local function type_position(buf, client)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "java")
  if not ok or not parser then return end
  local root = parser:parse()[1]:root()
  local row = 0
  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then row = vim.api.nvim_win_get_cursor(win)[1] - 1 end
  local pick
  for child in root:iter_children() do
    local t = child:type()
    if t:match("_declaration$") and t ~= "import_declaration" and t ~= "package_declaration" then
      local name = child:field("name")[1]
      if name then
        local sr, _, er = child:range()
        if not pick or (row >= sr and row <= er) then pick = name end
        if row >= sr and row <= er then break end
      end
    end
  end
  if not pick then return end
  local r, c = pick:range()
  local line = vim.api.nvim_buf_get_lines(buf, r, r + 1, false)[1] or ""
  return { line = r, character = vim.str_utfindex(line, client.offset_encoding or "utf-16", c, false) }
end

-- 在 documentSymbol 结果里找名为 name 的类型，返回它的成员（不含构造方法、内部类型）
local function members_of(symbols, name)
  local function find(list)
    for _, s in ipairs(list or {}) do
      local kind = SYMBOL_KIND[s.kind]
      if TYPE_KINDS[kind] and s.name:gsub("<.*$", "") == name then return s end
      local r = find(s.children)
      if r then return r end
    end
  end
  local t = find(symbols)
  local out = {}
  for _, c in ipairs(t and t.children or {}) do
    local kind = SYMBOL_KIND[c.kind]
    if kind ~= "Constructor" and not TYPE_KINDS[kind] then out[#out + 1] = c end
  end
  return out
end

-- 父类里的 private 成员子类看不到，不算继承（IDEA 也不显示）。documentSymbol 不带修饰符，
-- 项目里的源码文件直接看声明那几行；依赖库（jdt://）里的类读不到文本，不过滤
---@param files? table<string, string[]|false> 已读过的文件（同一次查询里一个父类只读一次）
function M.is_private(uri, sym, files)
  if not uri:match("^file:") then return false end
  files = files or {}
  if files[uri] == nil then
    local ok, l = pcall(vim.fn.readfile, vim.uri_to_fname(uri))
    files[uri] = ok and l or false
  end
  local lines = files[uri]
  if not lines then return false end
  local first = sym.range and sym.range.start.line or 0
  local last = (sym.selectionRange or sym.range).start.line
  local text = table.concat(vim.list_slice(lines, first + 1, last + 1), " ")
  local before = text:match("^(.-)" .. vim.pesc(sym.name:gsub("%(.*$", ""))) or text
  return before:find("%f[%w]private%f[%W]") ~= nil
end

---异步取当前类继承来的成员：jdtls 类型层级取所有父类型 / 接口（逐层向上），再取各自的 documentSymbol
---（依赖库里的父类用 jdt:// 地址，jdtls 能直接返回）。结果按"近的父类在前"排列：
---cb({ { from = 父类型名, uri = 文件地址, symbol = DocumentSymbol }, ... })，出错时 cb(nil, 原因)
function M.collect_inherited(buf, cb)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local client = vim.lsp.get_clients({ bufnr = buf, method = "typeHierarchy/supertypes" })[1]
  if not client then return cb(nil, "Java 语言服务还没有启动") end
  local tick = vim.b[buf].changedtick
  if cache[buf] and cache[buf].tick == tick then return cb(cache[buf].members) end
  local pos = type_position(buf, client)
  if not pos then return cb({}) end
  local params = { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = pos }
  client:request("textDocument/prepareTypeHierarchy", params, function(err, res)
    if err or not res or not res[1] then return cb(nil, err and err.message or "取不到类型层级") end
    local groups, seen, pending, order, finished = {}, {}, 0, 0, false
    local files = {}
    local function finish()
      if pending > 0 or finished then return end
      finished = true
      local members = {}
      for i = 1, order do
        for _, m in ipairs(groups[i] or {}) do members[#members + 1] = m end
      end
      cache[buf] = { tick = tick, members = members }
      cb(members)
    end
    local function visit(item)
      pending = pending + 1
      client:request("typeHierarchy/supertypes", { item = item }, function(_, sups)
        for _, s in ipairs(sups or {}) do
          local key = s.uri .. "#" .. s.name
          if not seen[key] then
            seen[key] = true
            order = order + 1
            local idx = order
            pending = pending + 1
            client:request("textDocument/documentSymbol", { textDocument = { uri = s.uri } }, function(_, syms)
              local name = s.name:gsub("<.*$", "")
              groups[idx] = vim.tbl_map(function(sym)
                return { from = name, uri = s.uri, symbol = sym }
              end, vim.tbl_filter(function(sym) return not M.is_private(s.uri, sym, files) end, members_of(syms, name)))
              pending = pending - 1
              finish()
            end, buf)
            visit(s)
          end
        end
        pending = pending - 1
        finish()
      end, buf)
    end
    visit(res[1])
  end, buf)
end

local function structure_title(on)
  return on and "文件结构（含继承的成员，Ctrl+F12 隐藏）" or "文件结构（Ctrl+F12 显示继承的成员）"
end

-- 把继承的成员转成 picker 的条目，挂在当前类下面
local function inherited_items(members, parent, client, want, own)
  local items = {}
  for _, m in ipairs(members) do
    local s = m.symbol
    local kind = SYMBOL_KIND[s.kind] or "Unknown"
    if want(kind) then
      local range = s.selectionRange or s.range
      local item = {
        kind = kind, name = s.name, detail = s.detail, parent = parent, tree = true,
        text = kind .. " " .. s.name .. " " .. m.from,
        inherited_from = m.from, item = s,
        -- 本类里有同名同参数的成员：父类的这个已被重写 / 隐藏
        overridden = own and own[s.name] or nil,
        pos = { range.start.line + 1, range.start.character },
        end_pos = { range["end"].line + 1, range["end"].character },
        loc = { uri = m.uri, range = range, encoding = client and client.offset_encoding or "utf-16" },
      }
      if m.uri:match("^file:") then
        item.file = vim.uri_to_fname(m.uri)
      else
        -- 依赖库里的类（jdt://）：交给 nvim-jdtls 加载反编译 / 源码内容
        item.buf = vim.uri_to_bufnr(m.uri)
        item.file = m.uri
      end
      items[#items + 1] = item
    end
  end
  return items
end

---Ctrl+F12 文件结构：Java 文件里可切换"显示继承的成员"，其他文件照旧
function M.structure()
  local buf = vim.api.nvim_get_current_buf()
  if vim.bo[buf].filetype ~= "java" then
    return Snacks.picker.lsp_symbols({ filter = LazyVim.config.kind_filter })
  end
  local lsp = require("snacks.picker.source.lsp")
  return Snacks.picker.lsp_symbols({
    title = structure_title(false),
    filter = LazyVim.config.kind_filter,
    inherited = false,
    toggles = { inherited = { icon = "继承", value = true } },
    finder = function(opts, ctx)
      local base = lsp.symbols(opts, ctx)
      if not opts.inherited or type(base) ~= "function" then return base end
      return function(cb)
        local cls, last ---@type table?, table?
        local own = {} -- 本类成员名（含参数），用来标出被重写的父类方法
        base(function(item)
          if not cls and item.parent and item.parent.root and TYPE_KINDS[item.kind] then cls = item end
          if cls and item.parent == cls then
            last = item
            own[item.name] = true
          end
          cb(item)
        end)
        -- 取数据和组装条目都在主循环里做（协程里不能调用大部分 nvim API）
        local async = ctx.async
        local done, items = false, {}
        vim.schedule(function()
          M.collect_inherited(buf, function(res, err)
            if err then vim.notify("取继承的成员失败：" .. err, vim.log.levels.WARN) end
            local filter = opts.filter[vim.bo[buf].filetype]
            if filter == nil then filter = opts.filter.default end
            local function want(kind) return type(filter) == "boolean" or vim.tbl_contains(filter, kind) end
            local client = vim.lsp.get_clients({ bufnr = buf, name = "jdtls" })[1]
            items = inherited_items(res or {}, cls or { root = true, text = "" }, client, want, own)
            local bufmap = lsp.bufmap()
            for _, item in ipairs(items) do item.buf = item.buf or bufmap[item.file] end
            done = true
            async:resume()
          end)
        end)
        while not done do async:suspend() end
        if async:aborted() then return end
        if #items > 0 and last then last.last = nil end
        if #items > 0 then items[#items].last = true end
        for _, item in ipairs(items) do
          cb(item)
        end
      end
    end,
    format = function(item, picker)
      local ret = require("snacks.picker.format").lsp_symbol(item, picker)
      if item.inherited_from then
        -- 继承来的成员整体变灰，后面标出来源类
        for _, r in ipairs(ret) do
          if type(r[1]) == "string" and r[2] and not tostring(r[2]):find("Icon") and not tostring(r[2]):find("Tree") then
            r[2] = "Comment"
          end
        end
        ret[#ret + 1] = { "  ← " .. item.inherited_from .. (item.overridden and "（已重写）" or ""), "Comment" }
      end
      return ret
    end,
    actions = {
      kit_toggle_inherited = function(picker)
        picker.opts.inherited = not picker.opts.inherited
        picker.title = structure_title(picker.opts.inherited)
        picker:update_titles()
        picker.list:set_target()
        picker:find()
      end,
    },
    win = {
      input = { keys = { ["<C-F12>"] = { "kit_toggle_inherited", mode = { "n", "i" }, desc = "显示 / 隐藏继承的成员" } } },
      list = { keys = { ["<C-F12>"] = { "kit_toggle_inherited", mode = { "n", "i" }, desc = "显示 / 隐藏继承的成员" } } },
    },
  })
end

K.map(K.NI, "<C-F12>", K.n(M.structure), "文件结构（再按 Ctrl+F12 显示继承的成员）")

return M
