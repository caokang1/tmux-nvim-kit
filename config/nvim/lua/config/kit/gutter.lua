-- IDEA 左侧图标（gutter icons）：Java 文件行号旁显示
--   ↓  接口 / 类有子类型，接口方法 / 可重写的方法有实现（被重写），@Autowired 等注入的字段的类型有实现（Spring Bean）
--   ↑  实现了接口方法（I 色）/ 重写了父类方法（O 色）
-- 鼠标点击图标：↓ 列出实现，↑ 跳到父方法。空格 u O 开关。
--
-- 性能（首要）：
--   * 文件结构（类、方法、字段、修饰符、@Override）用 treesitter 本地解析，按 changedtick 缓存，不问语言服务
--   * 只为窗口可见范围（上下各多算 20 行）里的声明发请求；滚动 / 修改后 200ms 再算（节流）
--   * 请求异步、全局最多 2 个同时进行、单个 8 秒超时；结果按"类名#方法名(参数)"缓存，改动本文件不会让已有图标闪烁重算
--   * 类没有子类型时，它的方法不可能被重写，不再逐个问"有没有实现"
--   * ↑ 先看 @Override 和 extends / implements 判断是接口还是类；只有既 extends 又 implements 时才问 jdtls 父方法在哪
--   * 保存任何 Java 文件 / jdtls 完成构建后，继承关系可能变了：旧结果先继续显示，后台重算可见范围
local K = require("config.idea_keys")
local sc = require("config.kit.signclick")

local M = { enabled = true }
local ns = vim.api.nvim_create_namespace("kit_gutter")
local MAX_INFLIGHT, TIMEOUT, MARGIN, DELAY = 2, 8000, 20, 200

-- 配色：参考 theme.lua 的 IDEA 调色板
local function set_hl()
  vim.api.nvim_set_hl(0, "KitGutterDown", { fg = "#56A8F5", default = true }) -- 有实现：方法蓝
  vim.api.nvim_set_hl(0, "KitGutterImpl", { fg = "#6AAB73", default = true }) -- 实现接口：绿
  vim.api.nvim_set_hl(0, "KitGutterOverride", { fg = "#CF8E6D", default = true }) -- 重写父类：橙
end
set_hl()

-- ================= 文件结构（treesitter） =================
local S = {} -- S[buf] = { tick, items, by_id, res = {}, old = {} }

local function st(buf)
  S[buf] = S[buf] or { res = {}, old = {} }
  return S[buf]
end

local type_nodes = { class_declaration = "class", interface_declaration = "interface", enum_declaration = "enum", record_declaration = "record" }
local body_nodes = { class_body = true, interface_body = true, enum_body = true, enum_body_declarations = true }
local inject_ann = { Autowired = true, Resource = true, Inject = true }
-- Object 的方法：类只 implements 接口时，重写它们仍是"重写父类"
local object_methods = { toString = true, equals = true, hashCode = true, clone = true, finalize = true }

-- 修饰符：返回 { words = {public=true,...}, ann = {Override=true,...} }
local function modifiers(node, buf)
  local m = { words = {}, ann = {} }
  for child in node:iter_children() do
    if child:type() == "modifiers" then
      for c in child:iter_children() do
        local t = c:type()
        if t == "marker_annotation" or t == "annotation" then
          local name = c:field("name")[1]
          if name then
            local txt = vim.treesitter.get_node_text(name, buf):match("([%w_]+)$")
            if txt then m.ann[txt] = true end
          end
        elseif not c:named() then
          m.words[t] = true
        end
      end
    end
  end
  return m
end

local function has_child(node, t)
  for c in node:iter_children() do
    if c:type() == t then return true end
  end
  return false
end

local function parse(buf)
  local s = st(buf)
  local tick = vim.api.nvim_buf_get_changedtick(buf)
  if s.tick == tick and s.items then return s.items end
  local items, by_id = {}, {}
  s.tick, s.items, s.by_id = tick, items, by_id
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "java", { error = false })
  if not ok or not parser then return items end
  local tree = parser:parse()[1]
  if not tree then return items end

  local function add(it)
    if by_id[it.id] then return end -- 同名重载且参数文本完全相同（不合法代码），忽略
    items[#items + 1] = it
    by_id[it.id] = it
  end

  local walk_body
  local function visit_type(node, outer)
    local name = node:field("name")[1]
    if not name then return end
    local tk = type_nodes[node:type()]
    local m = modifiers(node, buf)
    local r, c = name:range()
    local it = {
      kind = "type", tk = tk, row = r, col = c,
      name = vim.treesitter.get_node_text(name, buf),
      final = m.words.final or tk == "enum" or tk == "record",
      super = node:field("superclass")[1] ~= nil,
      ifaces = node:field("interfaces")[1] ~= nil or has_child(node, "extends_interfaces"),
    }
    it.id = (outer and outer.id .. "$" or "") .. it.name
    add(it)
    local body = node:field("body")[1]
    if body then walk_body(body, it) end
  end

  local function visit_method(node, owner)
    local name = node:field("name")[1]
    if not name then return end
    local m = modifiers(node, buf)
    local params = node:field("parameters")[1]
    local ptxt = params and vim.treesitter.get_node_text(params, buf):gsub("%s+", "") or "()"
    local r, c = name:range()
    local nm = vim.treesitter.get_node_text(name, buf)
    add({
      kind = "method", row = r, col = c, name = nm, owner = owner,
      id = owner.id .. "#" .. nm .. ptxt,
      override = m.ann.Override or false,
      -- 能被重写：非 static / private / final；接口里的 static / private 方法同样不能
      overridable = not (m.words.static or m.words.private or m.words.final),
    })
  end

  local function visit_field(node, owner)
    local m = modifiers(node, buf)
    local inject = false
    for a in pairs(m.ann) do
      if inject_ann[a] then inject = true end
    end
    if not inject then return end
    local ty = node:field("type")[1]
    -- 只处理简单类型（UserService / com.x.UserService），List<UserService> 之类不处理
    if ty and ty:type() == "scoped_type_identifier" then
      local last
      for c in ty:iter_children() do
        if c:type() == "type_identifier" then last = c end
      end
      ty = last
    end
    if not ty or ty:type() ~= "type_identifier" then return end
    local decl = node:field("declarator")[1]
    local dname = decl and decl:field("name")[1]
    if not dname then return end
    local tr, tc = ty:range()
    local r = dname:range()
    local tname = vim.treesitter.get_node_text(ty, buf)
    add({
      kind = "field", row = r, trow = tr, tcol = tc, owner = owner, tname = tname,
      id = owner.id .. "." .. vim.treesitter.get_node_text(dname, buf) .. ":" .. tname,
    })
  end

  walk_body = function(body, owner)
    for child in body:iter_children() do
      local t = child:type()
      if type_nodes[t] then
        visit_type(child, owner)
      elseif t == "method_declaration" then
        visit_method(child, owner)
      elseif t == "field_declaration" then
        visit_field(child, owner)
      elseif body_nodes[t] then
        walk_body(child, owner)
      end
    end
  end

  for child in tree:root():iter_children() do
    if type_nodes[child:type()] then visit_type(child, nil) end
  end
  return items
end
M.parse = parse

-- ================= 结果缓存 =================
-- 键："down:<id>" → true/false，"up:<id>" → "I"/"O"/false；"pending" 表示排队或请求中
local function get(buf, key)
  local s = st(buf)
  local v = s.res[key]
  if v == nil or v == "pending" then
    local o = s.old[key]
    if o ~= nil then return o end
  end
  if v == "pending" then return nil end
  return v
end

-- ================= 请求队列 =================
local queue, inflight = {}, 0
local pump

local function client_for(buf)
  return vim.lsp.get_clients({ bufnr = buf, name = "jdtls" })[1]
end

-- 发一个 LSP 请求，超时或出错时 cb(nil)
local function request(buf, method, params, cb)
  local client = client_for(buf)
  if not client then return cb(nil) end
  M.requests = (M.requests or 0) + 1
  local done = false
  local timer = vim.defer_fn(function()
    if done then return end
    done = true
    cb(nil)
  end, TIMEOUT)
  local ok = client:request(method, params, function(err, result)
    if done then return end
    done = true
    pcall(function() timer:stop() timer:close() end)
    cb(not err and result or nil, err)
  end, buf)
  if not ok and not done then
    done = true
    pcall(function() timer:stop() timer:close() end)
    cb(nil)
  end
end

local redraw, schedule_update

local function finish(buf, key, val)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  local s = st(buf)
  s.res[key] = val
  s.old[key] = nil
  redraw(buf)
end

pump = function()
  while inflight < MAX_INFLIGHT and #queue > 0 do
    local job = table.remove(queue, 1)
    if vim.api.nvim_buf_is_valid(job.buf) then
      inflight = inflight + 1
      local fired = false
      local cb
      cb = function(val)
        if fired then return end
        fired = true
        inflight = inflight - 1
        if val == nil then
          -- 超时 / 出错：不缓存，下次滚动或修改时重试
          if vim.api.nvim_buf_is_valid(job.buf) then st(job.buf).res[job.key] = nil end
        else
          finish(job.buf, job.key, val)
          if job.after then job.after() end
        end
        vim.schedule(pump)
      end
      local ok = pcall(job.run, cb)
      if not ok then cb(nil) end
    end
  end
end

local function pos_params(buf, row, col)
  return { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = row, character = col } }
end

-- 列字节位置 → UTF-16（jdtls 用 UTF-16 计列；名字前面有中文时不同）
local function utf16_col(buf, row, col)
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local ok, c = pcall(vim.str_utfindex, line, "utf-16", col)
  if ok then return c end
  return col
end

-- 父方法所在类型是接口还是类：读那个文件，从父方法那行往上找最近的类型声明
local kind_cache = {} -- [uri .. ":" .. line] = "I"/"O"
local text_cache = {} -- [jdt uri] = lines

local function decl_kind(lines, line)
  for i = math.min(line + 1, #lines), 1, -1 do
    local l = lines[i]
    local trimmed = l:match("^%s*(.-)$")
    if not (trimmed:sub(1, 1) == "*" or trimmed:sub(1, 2) == "//" or trimmed:sub(1, 2) == "/*") then
      if l:find("%f[%w_@]interface%s+[%w_]") then return "I" end
      if l:find("%f[%w_]class%s+[%w_]") or l:find("%f[%w_]enum%s+[%w_]") or l:find("%f[%w_]record%s+[%w_]") then
        return "O"
      end
    end
  end
  return "O"
end

local function classify(buf, loc, cb)
  local uri = loc.uri or loc.targetUri
  local range = loc.range or loc.targetSelectionRange
  if not uri or not range then return cb("O") end
  local key = uri .. ":" .. range.start.line
  if kind_cache[key] then return cb(kind_cache[key]) end
  local function done(lines)
    local k = decl_kind(lines or {}, range.start.line)
    kind_cache[key] = k
    cb(k)
  end
  if uri:sub(1, 7) == "file://" then
    local fname = vim.uri_to_fname(uri)
    local b = vim.fn.bufnr(fname)
    if b > 0 and vim.api.nvim_buf_is_loaded(b) then
      return done(vim.api.nvim_buf_get_lines(b, 0, -1, false))
    end
    local ok, lines = pcall(vim.fn.readfile, fname)
    return done(ok and lines or {})
  end
  if text_cache[uri] then return done(text_cache[uri]) end
  request(buf, "java/classFileContents", { uri = uri }, function(text)
    if type(text) ~= "string" then return cb("O") end
    text_cache[uri] = vim.split(text, "\n", { plain = true })
    done(text_cache[uri])
  end)
end

-- 生成各类任务
local function job_down(buf, it, row, col)
  return {
    buf = buf, key = "down:" .. it.id,
    run = function(cb)
      local cur = st(buf).by_id and st(buf).by_id[it.id] or it
      local r, c = cur[row], cur[col]
      request(buf, "textDocument/implementation", pos_params(buf, r, utf16_col(buf, r, c)), function(res)
        if res == nil then return cb(nil) end
        if res.uri or res.targetUri then res = { res } end
        -- 在类型引用上（注入字段的类型）问实现，没有实现时 jdtls 会返回类型自身的声明，去掉它
        local n = 0
        for _, loc in ipairs(res) do
          local uri, range = loc.uri or loc.targetUri, loc.range or loc.targetSelectionRange
          local self_decl = it.tname and uri and range
            and vim.fn.fnamemodify(vim.uri_to_fname(uri), ":t:r") == it.tname
            and range["end"].character - range.start.character == #it.tname
          if not self_decl then n = n + 1 end
        end
        cb(n > 0)
      end)
    end,
  }
end

local function job_up(buf, it)
  return {
    buf = buf, key = "up:" .. it.id,
    run = function(cb)
      local cur = st(buf).by_id and st(buf).by_id[it.id] or it
      request(buf, "java/findLinks", { type = "superImplementation", position = pos_params(buf, cur.row, utf16_col(buf, cur.row, cur.col)) }, function(res)
        if res == nil then return cb(nil) end
        if not res[1] then return cb(false) end
        classify(buf, res[1], cb)
      end)
    end,
  }
end

-- ↑ 不问语言服务就能判断的情况；返回 nil 表示要问
local function quick_up(it)
  if not it.override then return false end
  local o = it.owner
  if o.tk == "interface" then return "I" end
  if object_methods[it.name] and not o.super then return "O" end
  if o.tk == "enum" or o.tk == "record" then return "I" end
  if o.super and not o.ifaces then return "O" end
  if o.ifaces and not o.super then return "I" end
  if not o.super and not o.ifaces then return "O" end
  return nil
end

-- ================= 计算 / 显示 =================
local function visible_ranges(buf)
  local ranges = {}
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do
    local top = vim.fn.line("w0", win) - 1 - MARGIN
    local bot = vim.fn.line("w$", win) - 1 + MARGIN
    ranges[#ranges + 1] = { top, bot }
  end
  return ranges
end

local function in_ranges(ranges, row)
  for _, r in ipairs(ranges) do
    if row >= r[1] and row <= r[2] then return true end
  end
  return false
end

local function enabled_for(buf)
  return M.enabled and vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].filetype == "java"
end

-- 根据已有结果算出每行的图标：{ [行 0 基] = { up = "I"/"O", down = true, item = it } }
function M.icons(buf)
  buf = buf == 0 and vim.api.nvim_get_current_buf() or buf
  local out = {}
  if not enabled_for(buf) then return out end
  for _, it in ipairs(parse(buf)) do
    local up = it.kind == "method" and get(buf, "up:" .. it.id) or nil
    local down = get(buf, "down:" .. it.id)
    if (up and up ~= false) or down == true then
      local e = out[it.row] or { item = it }
      if up then e.up = up end
      if down == true then e.down = true end
      out[it.row] = e
    end
  end
  return out
end

-- 点击图标：↓ 列出实现，↑ 跳到父方法
local function click(buf, e)
  return function()
    local it = e.item
    if e.up and not e.down then
      pcall(vim.api.nvim_win_set_cursor, 0, { it.row + 1, it.col })
      require("jdtls").super_implementation()
    elseif e.down and not e.up then
      if it.kind == "field" then
        pcall(vim.api.nvim_win_set_cursor, 0, { it.trow + 1, it.tcol })
      else
        pcall(vim.api.nvim_win_set_cursor, 0, { it.row + 1, it.col })
      end
      Snacks.picker.lsp_implementations()
    else
      pcall(vim.api.nvim_win_set_cursor, 0, { it.row + 1, it.col })
      vim.ui.select({ "跳到父方法（↑）", "列出实现（↓）" }, { prompt = "左侧图标" }, function(_, idx)
        if idx == 1 then require("jdtls").super_implementation() elseif idx == 2 then Snacks.picker.lsp_implementations() end
      end)
    end
  end
end

redraw = function(buf)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local handlers = {}
  local nlines = vim.api.nvim_buf_line_count(buf)
  for row, e in pairs(M.icons(buf)) do
    if row < nlines then
      local text, hl, tip
      if e.up then
        hl = e.up == "I" and "KitGutterImpl" or "KitGutterOverride"
        text = e.down and "↑↓" or "↑"
        tip = e.up == "I" and "实现了接口方法" or "重写了父类方法"
        if e.down then tip = tip .. "；有实现" end
      else
        hl, text, tip = "KitGutterDown", "↓", "有实现"
      end
      -- 优先级低于诊断（错误 / 警告图标更重要），同一行只能显示一个图标
      pcall(vim.api.nvim_buf_set_extmark, buf, ns, row, 0, { sign_text = text, sign_hl_group = hl, priority = 8 })
      handlers[row + 1] = { fn = click(buf, e), label = tip }
    end
  end
  sc.set(buf, "gutter", handlers)
end

-- 为可见范围里还不知道结果的声明排队请求（all=true 时整个文件，用于测试 / 计时）
function M.update(buf, all)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if not enabled_for(buf) then
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
      sc.clear(buf, "gutter")
    end
    return
  end
  if not client_for(buf) then return end
  local s = st(buf)
  local items = parse(buf)
  local ranges = visible_ranges(buf)
  local wanted = {}
  local jobs = {}
  local function want(job)
    wanted[job.key] = true
    local v = s.res[job.key]
    if v == nil then
      s.res[job.key] = "pending"
      jobs[#jobs + 1] = job
    end
  end
  local function after_type() schedule_update(buf, all) end

  for _, it in ipairs(items) do
    if all or in_ranges(ranges, it.row) then
      if it.kind == "type" then
        if not it.final then
          local j = job_down(buf, it, "row", "col")
          j.after = after_type
          want(j)
        end
      elseif it.kind == "field" then
        want(job_down(buf, it, "trow", "tcol"))
      elseif it.kind == "method" then
        local q = quick_up(it)
        if q == nil then
          want(job_up(buf, it))
        else
          s.res["up:" .. it.id] = q
        end
        -- ↓：接口方法问；类的方法只在类有子类型时问
        local o = it.owner
        if it.overridable and not o.final then
          local sub = o.tk == "interface" or s.res["down:" .. o.id]
          if sub == true then
            want(job_down(buf, it, "row", "col"))
          elseif sub == false then
            s.res["down:" .. it.id] = false
          elseif s.res["down:" .. o.id] == nil then
            -- 类型自身不在可见范围：先问类型，回来后再算方法
            local j = job_down(buf, o, "row", "col")
            j.after = after_type
            want(j)
          end
        else
          s.res["down:" .. it.id] = false
        end
      end
    end
  end

  -- 丢掉排队中、已经滚出可见范围的旧任务
  local keep = {}
  for _, j in ipairs(queue) do
    if j.buf ~= buf or wanted[j.key] then
      keep[#keep + 1] = j
    else
      s.res[j.key] = nil
    end
  end
  queue = keep
  -- 类型的任务先做（决定了方法要不要问）
  table.sort(jobs, function(a, b) return (a.after and 0 or 1) < (b.after and 0 or 1) end)
  vim.list_extend(queue, jobs)
  redraw(buf)
  pump()
end

-- 还没完成的请求数（测试用）
function M.pending(buf)
  local n = inflight
  for _, j in ipairs(queue) do
    if not buf or j.buf == buf then n = n + 1 end
  end
  return n
end

local timers = {}
-- 还有排队 / 进行中的请求或待执行的重算（测试用）
function M.busy(buf)
  return M.pending(buf) > 0 or timers[buf] ~= nil
end

-- 继承关系可能变了：旧结果先留着显示，全部重算
function M.invalidate(buf)
  for b, s in pairs(S) do
    if not buf or b == buf then
      for k, v in pairs(s.res) do
        if v ~= "pending" then s.old[k] = v end
      end
      s.res = {}
    end
  end
  kind_cache = {}
  text_cache = {}
end

schedule_update = function(buf, all)
  if timers[buf] then return end
  timers[buf] = vim.defer_fn(function()
    timers[buf] = nil
    if vim.api.nvim_buf_is_valid(buf) then
      if vim.fn.mode() == "i" then return end -- 输入时不算，离开输入模式（InsertLeave）再算
      M.update(buf, all)
    end
  end, DELAY)
end

-- ================= 自动命令 / 开关 =================
local group = vim.api.nvim_create_augroup("kit_gutter", { clear = true })
vim.api.nvim_create_autocmd({ "BufWinEnter", "BufEnter", "WinScrolled", "TextChanged", "InsertLeave", "WinResized" }, {
  group = group,
  callback = function(ev)
    local buf = ev.event == "WinScrolled" and vim.api.nvim_get_current_buf() or ev.buf
    if ev.event == "WinScrolled" or ev.event == "WinResized" then
      -- 滚动的可能不是当前窗口（鼠标滚轮滚另一个窗口）
      for w in pairs(vim.v.event or {}) do
        local win = tonumber(w)
        if win and vim.api.nvim_win_is_valid(win) then
          local b = vim.api.nvim_win_get_buf(win)
          if vim.bo[b].filetype == "java" then schedule_update(b) end
        end
      end
    end
    if vim.bo[buf].filetype == "java" then schedule_update(buf) end
  end,
})
vim.api.nvim_create_autocmd("LspAttach", {
  group = group,
  callback = function(ev)
    local c = vim.lsp.get_client_by_id(ev.data.client_id)
    if c and c.name == "jdtls" then schedule_update(ev.buf) end
  end,
})
-- 保存 Java 文件：子类 / 实现可能有增减（不只是本文件）
vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  pattern = "*.java",
  callback = function()
    M.invalidate()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(win)
      if vim.bo[b].filetype == "java" then schedule_update(b) end
    end
  end,
})
-- jdtls 导入 / 构建完成：导入前问到的"没有实现"可能不准，重算（最多 5 秒一次）
local last_progress = 0
vim.api.nvim_create_autocmd("LspProgress", {
  group = group,
  pattern = "end",
  callback = function(ev)
    local c = vim.lsp.get_client_by_id(ev.data.client_id)
    if not c or c.name ~= "jdtls" then return end
    local now = vim.uv.now()
    if now - last_progress < 5000 then return end
    last_progress = now
    vim.defer_fn(function()
      M.invalidate()
      for _, win in ipairs(vim.api.nvim_list_wins()) do
        local b = vim.api.nvim_win_get_buf(win)
        if vim.bo[b].filetype == "java" then schedule_update(b) end
      end
    end, 1000)
  end,
})
vim.api.nvim_create_autocmd("BufWipeout", {
  group = group,
  callback = function(ev) S[ev.buf] = nil end,
})
vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = set_hl })

function M.toggle(on)
  if on == nil then on = not M.enabled end
  M.enabled = on
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "java" then
      if on then M.update(b) else
        vim.api.nvim_buf_clear_namespace(b, ns, 0, -1)
        sc.clear(b, "gutter")
      end
    end
  end
end

-- 空格 u G 已被 LazyVim 的"Git 改动标记"开关占用，用 空格 u O（Override）
if Snacks and Snacks.toggle then
  Snacks.toggle({
    name = "左侧实现/重写图标",
    get = function() return M.enabled end,
    set = function(on) M.toggle(on) end,
  }):map("<leader>uO")
else
  vim.keymap.set("n", "<leader>uO", function() M.toggle() end, { desc = "切换左侧实现/重写图标" })
end

-- ================= Ctrl+Alt+B：在注入字段 / 变量声明的名字上也能跳到实现 =================
-- jdtls 对变量名问"实现"返回空；IDEA 在 @Autowired 的 UserService userService 上能列出实现类。
-- 光标在字段 / 局部变量 / 参数的名字上且类型是简单类名时，改为在类型名上查实现
function M.impl_position(buf, row, col)
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { row, col }, ignore_injections = true })
  if not ok or not node or node:type() ~= "identifier" then return nil end
  local p = node:parent()
  if not p then return nil end
  local decl
  if p:type() == "variable_declarator" then
    decl = p:parent()
  elseif p:type() == "formal_parameter" then
    decl = p
  end
  if not decl or (p:field("name")[1] and p:field("name")[1]:id() ~= node:id()) then return nil end
  local ty = decl:field("type")[1]
  if ty and ty:type() == "scoped_type_identifier" then
    local last
    for c in ty:iter_children() do
      if c:type() == "type_identifier" then last = c end
    end
    ty = last
  end
  if not ty or ty:type() ~= "type_identifier" then return nil end
  local r, c = ty:range()
  return r, c
end

K.map(K.NI, "<C-M-b>", K.n(function()
  if vim.bo.filetype == "java" then
    local pos = vim.api.nvim_win_get_cursor(0)
    local r, c = M.impl_position(0, pos[1] - 1, pos[2])
    if r then vim.api.nvim_win_set_cursor(0, { r + 1, c }) end
  end
  Snacks.picker.lsp_implementations()
end), "跳转到实现")

return M
