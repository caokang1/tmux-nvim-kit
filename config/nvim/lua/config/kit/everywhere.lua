-- Search Everywhere（IDEA 双击 Shift）和 Ctrl+N 查找类
--   Ctrl+Shift+Space / 空格 s e   一个入口搜 类、文件、符号（方法）、操作（快捷键）、最近的文件
--                                  Tab / Shift+Tab 在"全部 / 类 / 文件 / 符号 / 操作"之间切换；"全部"时每组只列前几条
--   Ctrl+N / Alt+N                查找类：默认只列项目里的类，弹框里再按 Ctrl+N / Alt+N 切换为包含依赖库（IDEA 同款）
--   （终端里分不出双击 Shift，所以用 Ctrl+Shift+Space；不占用 LazyVim 的 空格 空格）
--
-- 类和符号来自 jdtls 的 java/searchSymbols 请求（vscode-java 也用它）：sourceOnly 时只搜项目源码，
-- 比 workspace/symbol 快得多（示例项目约 20ms 对 500ms），也不会被依赖库里的同名类挤掉结果。
-- jdtls 的匹配是区分大小写的前缀 / 驼峰匹配（"USI" 能找到 UserServiceImpl，"usi" 不行），
-- 所以同时再按 *关键字* 搜一次（不区分大小写的包含匹配），合并后按模糊匹配得分排序。
-- 文件来自 rg --files（按项目缓存几秒），操作来自已映射的快捷键（有中文说明的）。
local K = require("config.idea_keys")
local Async = require("snacks.picker.util.async")
local M = {}

M.categories = { "all", "class", "file", "symbol", "action" }
M.names = { all = "全部", class = "类", file = "文件", symbol = "符号", action = "操作" }
-- "全部"里每组最多显示几条
M.group_limit = { class = 6, file = 6, symbol = 6, action = 4 }

local Kind = vim.lsp.protocol.SymbolKind
M.class_kinds = { [Kind.Class] = true, [Kind.Interface] = true, [Kind.Enum] = true, [Kind.Struct] = true }
M.symbol_kinds = {
  [Kind.Method] = true, [Kind.Function] = true, [Kind.Constructor] = true, [Kind.Field] = true,
  [Kind.Constant] = true, [Kind.EnumMember] = true, [Kind.Property] = true,
}

local function lib() return require("config.kit.libfiles") end

local kind_names
local function kind_name(kind)
  if not kind_names then
    kind_names = {}
    for k, v in pairs(Kind) do
      if type(v) == "number" then kind_names[v] = k end
    end
  end
  return kind_names[kind] or "Unknown"
end

local function new_matcher(query)
  local m = require("snacks.picker.core.matcher").new({})
  m:init(query or "")
  return m
end

-- ================= 类 / 符号：LSP =================
function M.jdtls()
  return vim.lsp.get_clients({ name = "jdtls" })[1]
end

local function under(path, root)
  return path:sub(1, #root + 1) == root .. "/"
end

-- 向语言服务查询符号，cb(结果列表)；返回取消函数。
-- opts.libs：包含依赖库；opts.limit：每次请求最多返回几条；opts.root：非 Java 项目按路径过滤项目内
function M.query_symbols(query, opts, cb)
  opts = opts or {}
  local results, seen, pending, reqs = {}, {}, 0, {}
  local function add(client, list)
    for _, s in ipairs(list or {}) do
      local loc = s.location
      if loc and loc.uri then
        local key = s.name .. "\0" .. loc.uri .. "\0" .. (loc.range and loc.range.start.line or -1)
        local file = vim.uri_to_fname(loc.uri)
        local in_project = not lib().is_lib(loc.uri) and (not opts.root or under(file, opts.root))
        if not seen[key] and (opts.libs or in_project) then
          seen[key] = true
          results[#results + 1] = { sym = s, client = client, in_project = in_project }
        end
      end
    end
  end
  local function done()
    pending = pending - 1
    if pending == 0 then cb(results) end
  end
  local function request(client, method, params, on_err)
    pending = pending + 1
    local ok, id = client:request(method, params, function(err, res)
      if err and on_err then
        on_err()
      elseif not err then
        add(client, res)
      end
      done()
    end)
    if ok and id then reqs[#reqs + 1] = { client, id } end
    if not ok then done() end
  end

  if query == "" then
    vim.schedule(function() cb({}) end)
    return function() end
  end
  pending = 1 -- 发请求期间不触发回调
  local jdtls = M.jdtls()
  if jdtls then
    local queries = { query }
    if not query:find("[*?]") then queries[2] = "*" .. query .. "*" end
    for _, q in ipairs(queries) do
      local params = { query = q, sourceOnly = not opts.libs, maxResults = opts.limit or 100 }
      request(jdtls, "java/searchSymbols", params, function()
        -- 旧版 jdtls 没有 java/searchSymbols：改用 workspace/symbol，再按路径过滤
        opts.root = opts.root or LazyVim.root()
        request(jdtls, "workspace/symbol", { query = q })
      end)
    end
  else
    opts.root = opts.root or LazyVim.root()
    for _, client in ipairs(vim.lsp.get_clients({ bufnr = opts.buf or 0, method = "workspace/symbol" })) do
      request(client, "workspace/symbol", { query = query })
    end
  end
  done()
  return function()
    for _, r in ipairs(reqs) do pcall(r[1].cancel_request, r[1], r[2]) end
  end
end

-- 在 snacks 的异步 finder 里等待查询结果（finder 运行在不能调用编辑器函数的回调环境里，请求要放回主循环发出）
local function await_symbols(query, opts)
  local async = Async.running()
  local res, cancel
  local function start()
    cancel = M.query_symbols(query, opts, function(r)
      res = r
      if async then async:resume() end
    end)
  end
  if async then
    vim.schedule(start)
    async:on("abort", vim.schedule_wrap(function() if cancel then cancel() end end))
  else
    start()
  end
  while res == nil do
    if async then async:suspend() else vim.wait(50) end
  end
  return res
end

local function symbol_item(r, cat, score)
  local s = r.sym
  local uri = s.location.uri
  local range = s.location.range
  local info = lib().parse(uri)
  local item = {
    cat = cat,
    kind = kind_name(s.kind),
    name = s.name,
    container = s.containerName,
    file = vim.uri_to_fname(uri),
    pos = { range.start.line + 1, range.start.character },
    lib = info,
    score_ = score,
    text = s.name .. " " .. (s.containerName or ""),
  }
  if info then item.preview_title = s.name .. " — " .. lib().jar_label(info) end
  return item
end

-- 结果分成类 / 符号两组，组内按匹配得分、项目内优先、名字长短排序
function M.symbol_items(results, query, cats)
  local m = new_matcher(query)
  local groups = { class = {}, symbol = {} }
  for _, r in ipairs(results) do
    local cat = M.class_kinds[r.sym.kind] and "class" or M.symbol_kinds[r.sym.kind] and "symbol" or nil
    if cat and cats[cat] then
      local item = symbol_item(r, cat, m:match({ text = r.sym.name }))
      item.in_project = r.in_project
      table.insert(groups[cat], item)
    end
  end
  for _, g in pairs(groups) do
    table.sort(g, function(a, b)
      if a.score_ ~= b.score_ then return a.score_ > b.score_ end
      if a.in_project ~= b.in_project then return a.in_project end
      if #a.name ~= #b.name then return #a.name < #b.name end
      return (a.container or "") < (b.container or "")
    end)
  end
  return groups
end

-- ================= 文件 =================
local file_cache = {} ---@type table<string, {time:number, files:string[]}>
M.file_cache_ms = 10000

function M.list_files(root, cb)
  local c = file_cache[root]
  if c and vim.uv.now() - c.time < M.file_cache_ms then return cb(c.files) end
  vim.system({ "rg", "--files", "--glob", "!.git" }, { cwd = root, text = true }, function(res)
    local files = vim.split(res.stdout or "", "\n", { trimempty = true })
    vim.schedule(function()
      file_cache[root] = { time = vim.uv.now(), files = files }
      cb(files)
    end)
  end)
end

local function await_files(root)
  local async = Async.running()
  local res
  local function start()
    M.list_files(root, function(f)
      res = f
      if async then async:resume() end
    end)
  end
  if async then vim.schedule(start) else start() end
  while res == nil do
    if async then async:suspend() else vim.wait(20) end
  end
  return res
end

-- 最近的文件（含看过的依赖库类）+ 项目里的文件；有关键字时最近的排在前面
function M.file_items(root, query, limit, recent)
  local m = new_matcher(query)
  local ret, seen = {}, {}
  recent = recent or lib().recent_items({ cwd = root })
  for i, it in ipairs(recent) do
    it = vim.deepcopy(it)
    local s = query == "" and 1 or m:match({ text = it.lib and it.text or it.file:sub(#root + 2) })
    if s > 0 then
      it.cat, it.recent, it.score_, it.order = "file", true, s + 1000, i
      ret[#ret + 1] = it
      seen[it.file] = true
    end
  end
  if query ~= "" then
    local yield = Async.yielder(5)
    for _, rel in ipairs(await_files(root)) do
      yield()
      local s = m:match({ text = rel })
      if s > 0 then
        local f = root .. "/" .. rel
        if not seen[f] then ret[#ret + 1] = { cat = "file", file = f, text = rel, score_ = s, order = 0 } end
      end
    end
  end
  table.sort(ret, function(a, b)
    if a.score_ ~= b.score_ then return a.score_ > b.score_ end
    if a.order ~= b.order then return a.order < b.order end
    return #a.text < #b.text
  end)
  if limit and #ret > limit then ret = vim.list_slice(ret, 1, limit) end
  return ret
end

-- ================= 操作（快捷键） =================
local function key_label(lhs)
  local k = vim.fn.keytrans(lhs)
  local leader = vim.g.mapleader == " " and "<Space>" or vim.fn.keytrans(vim.g.mapleader or "\\")
  if k:sub(1, #leader) == leader then k = "空格 " .. k:sub(#leader + 1) end
  return k
end

function M.keymaps(buf)
  local maps = vim.api.nvim_get_keymap("n")
  if buf and vim.api.nvim_buf_is_valid(buf) then vim.list_extend(maps, vim.api.nvim_buf_get_keymap(buf, "n")) end
  for _, km in ipairs(maps) do km.label = key_label(km.lhs) end
  return maps
end

function M.action_items(query, buf, limit, maps)
  local m = new_matcher(query)
  maps = maps or M.keymaps(buf)
  local ret, seen = {}, {}
  for _, km in ipairs(maps) do
    local desc = km.desc
    if desc and desc ~= "" and desc ~= "which_key_ignore" and not km.lhs:find("<Plug>", 1, true)
      and not km.lhs:find("Mouse") and not km.lhs:find("Scroll") then
      local label = km.label or key_label(km.lhs)
      local key = desc .. "\0" .. label
      if not seen[key] then
        seen[key] = true
        local text = desc .. " " .. label
        local s = query == "" and 1 or m:match({ text = text })
        if s > 0 then
          ret[#ret + 1] = {
            cat = "action", desc = desc, lhs = km.lhs, key = label, text = text, score_ = s,
            callback = km.expr ~= 1 and km.callback or nil,
            preview = { text = ("%s\n\n按键：%s"):format(desc, label), ft = "markdown" },
          }
        end
      end
    end
  end
  table.sort(ret, function(a, b)
    if a.score_ ~= b.score_ then return a.score_ > b.score_ end
    return #a.desc < #b.desc
  end)
  if limit and #ret > limit then ret = vim.list_slice(ret, 1, limit) end
  return ret
end

-- ================= 弹框 =================
local order = { class = 1, file = 2, symbol = 3, action = 4 }


-- 收集一个分类（或全部）的结果，按显示顺序返回；snacks finder 和测试共用
-- o = { category = "all"|"class"|..., libs = 是否含依赖库, root = 项目根目录, buf = 打开弹框时的缓冲区 }
-- 要调用编辑器函数的数据（最近的文件、快捷键）在主循环里先取好
function M.prepare(o)
  local root = o.root or LazyVim.root()
  local cat = o.category or "all"
  return {
    root = root,
    recent = (cat == "all" or cat == "file") and lib().recent_items({ cwd = root }) or {},
    maps = (cat == "all" or cat == "action") and M.keymaps(o.buf) or {},
  }
end

function M.collect(o, query, emit, pre)
  pre = pre or M.prepare(o)
  local cat = o.category or "all"
  local all = cat == "all"
  local root = pre.root
  local function want(c) return all or cat == c end
  local ret = {}
  local function push(list, group)
    local limit = all and M.group_limit[group] or nil
    for i, it in ipairs(list) do
      if limit and i > limit then break end
      it.rank = order[group] * 100000 + i
      ret[#ret + 1] = it
      if emit then emit(it) end
    end
  end
  -- 最近的文件、文件、操作在本地算，先显示；类和符号等语言服务返回后按 rank 排到前面
  if want("file") then push(M.file_items(root, query, not all and 200 or nil, pre.recent), "file") end
  if want("action") then push(M.action_items(query, o.buf, not all and 200 or nil, pre.maps), "action") end
  if (want("class") or want("symbol")) and query ~= "" then
    local results = await_symbols(query, { libs = o.libs, limit = all and 50 or 200, buf = o.buf })
    local groups = M.symbol_items(results, query, { class = want("class"), symbol = want("symbol") })
    if want("class") then push(groups.class, "class") end
    if want("symbol") then push(groups.symbol, "symbol") end
  end
  table.sort(ret, function(a, b) return a.rank < b.rank end)
  return ret
end

local function state(picker) return picker.opts.kit end

local function title(st)
  local parts = {}
  for _, c in ipairs(st.categories) do
    parts[#parts + 1] = c == st.category and ("[" .. M.names[c] .. "]") or M.names[c]
  end
  return "到处搜索  " .. table.concat(parts, " ") .. "  │ " .. (st.libs and "含依赖库" or "仅项目")
    .. "  (Tab 切换分类  Ctrl+N 依赖库)"
end

-- Ctrl+N：只有"类"一个分类的同一个弹框
local function class_title(st)
  return st.libs and "查找类（含依赖库）  Ctrl+N 只看项目" or "查找类（仅项目）  Ctrl+N 包含依赖库"
end

local labels = { class = "类  ", file = "文件", symbol = "符号", action = "操作" }

function M.format(item, picker)
  local ret = {}
  if #state(picker).categories > 1 and state(picker).category == "all" then
    ret[#ret + 1] = { item.recent and "最近" or labels[item.cat] or "", "SnacksPickerComment" }
    ret[#ret + 1] = { " │ ", "SnacksPickerDelim" }
  end
  if item.cat == "file" then
    if item.lib then
      vim.list_extend(ret, lib().format_item(item, picker))
    else
      vim.list_extend(ret, require("snacks.picker.format").filename(item, picker))
    end
  elseif item.cat == "action" then
    ret[#ret + 1] = { "  ", "SnacksPickerIcon" }
    ret[#ret + 1] = { item.desc, "SnacksPickerLabel" }
    ret[#ret + 1] = { "  " .. item.key, "SnacksPickerComment" }
  else
    local icon = LazyVim.config.icons.kinds[item.kind] or " "
    ret[#ret + 1] = { icon, "SnacksPickerIcon" .. item.kind }
    ret[#ret + 1] = { item.name, item.cat == "class" and "SnacksPickerFile" or "SnacksPickerLabel" }
    if item.container and item.container ~= "" then ret[#ret + 1] = { "  " .. item.container, "SnacksPickerComment" } end
    if item.lib then ret[#ret + 1] = { "  " .. lib().jar_label(item.lib), "SnacksPickerDir" } end
  end
  return ret
end

local function preview(ctx)
  if ctx.item.cat == "action" then return Snacks.picker.preview.preview(ctx) end
  return Snacks.picker.preview.file(ctx)
end

local function confirm(picker, item)
  if not item then return end
  if item.cat == "action" then
    picker:close()
    -- 回到原来的窗口后执行：Lua 映射直接调用，其余模拟按下这个快捷键
    vim.schedule(function()
      if item.callback then
        local ok, err = pcall(item.callback)
        if not ok then vim.notify(tostring(err), vim.log.levels.WARN) end
      else
        vim.api.nvim_input(item.lhs)
      end
    end)
    return
  end
  if item.lib and not item.buf then item.buf = vim.fn.bufadd(item.file) end
  return picker:action("jump")
end

local function retitle(picker)
  local st = state(picker)
  picker.title = st.make_title(st)
  picker:update_titles()
  picker.list:set_target(1)
  picker:find()
end

local function switch(dir)
  return function(picker)
    local st = state(picker)
    local i = 1
    for k, c in ipairs(st.categories) do
      if c == st.category then i = k end
    end
    st.category = st.categories[(i - 1 + dir) % #st.categories + 1]
    retitle(picker)
  end
end

local function toggle_libs(picker)
  state(picker).libs = not state(picker).libs
  retitle(picker)
end

local function open(st)
  local both = { "i", "n" }
  st = vim.tbl_extend("force", {
    category = "all",
    categories = M.categories,
    libs = false,
    root = LazyVim.root(),
    buf = vim.api.nvim_get_current_buf(),
    make_title = title,
  }, st or {})
  -- 文件列表最多沿用几秒（同一次搜索里反复输入不用重新列），新建的文件下次打开就能搜到
  local c = file_cache[st.root]
  if c and vim.uv.now() - c.time > 3000 then file_cache[st.root] = nil end
  return Snacks.picker.pick({
    source = "kit_everywhere",
    kit = st,
    title = st.make_title(st),
    search = st.search,
    live = true,
    supports_live = true,
    finder = function(opts, ctx)
      local query = vim.trim(ctx.filter.search)
      local pre = M.prepare(opts.kit)
      return function(cb) M.collect(opts.kit, query, cb, pre) end
    end,
    format = M.format,
    preview = preview,
    sort = { fields = { "rank" } },
    matcher = { sort_empty = true },
    confirm = confirm,
    actions = {
      kit_ev_next = switch(1),
      kit_ev_prev = switch(-1),
      kit_ev_libs = toggle_libs,
    },
    win = {
      input = {
        keys = {
          ["<Tab>"] = { "kit_ev_next", mode = both, desc = "下一个分类" },
          ["<S-Tab>"] = { "kit_ev_prev", mode = both, desc = "上一个分类" },
          ["<C-n>"] = { "kit_ev_libs", mode = both, desc = "包含依赖库 / 仅项目" },
          ["<M-n>"] = { "kit_ev_libs", mode = both, desc = "包含依赖库 / 仅项目" },
        },
      },
      list = {
        keys = {
          ["<Tab>"] = { "kit_ev_next", desc = "下一个分类" },
          ["<S-Tab>"] = { "kit_ev_prev", desc = "上一个分类" },
          ["<C-n>"] = { "kit_ev_libs", desc = "包含依赖库 / 仅项目" },
          ["<M-n>"] = { "kit_ev_libs", desc = "包含依赖库 / 仅项目" },
        },
      },
    },
  })
end

function M.everywhere(st)
  return open(st)
end

function M.goto_class(st)
  -- 没有 jdtls（非 Java 项目）时保持原来的行为
  if not M.jdtls() then
    return Snacks.picker.lsp_workspace_symbols({ filter = LazyVim.config.kind_filter })
  end
  return open(vim.tbl_extend("force", { category = "class", categories = { "class" }, make_title = class_title }, st or {}))
end

K.map(K.NI, "<C-S-Space>", K.n(function() M.everywhere() end), "到处搜索（IDEA: 双击 Shift）")
K.map("n", "<leader>se", function() M.everywhere() end, "到处搜索 Search Everywhere（类/文件/符号/操作）")
K.map(K.NI, "<C-n>", K.n(function() M.goto_class() end), "查找类（再按 Ctrl+N 包含依赖库）")
K.map(K.NI, "<M-n>", K.n(function() M.goto_class() end), "查找类（浏览器里代替 Ctrl+N）")

return M
