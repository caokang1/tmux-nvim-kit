-- 类型层级（Ctrl+H）/ 调用层级（Ctrl+Alt+H）：底部可展开的树（IDEA 的 Hierarchy 工具窗口）
--   * 子节点在展开时才去问语言服务（逐层异步懒加载），大项目里也不会一次查完整棵树
--   * 面板里 Alt+S 切换方向：类型层级 完整层级 → 子类型 → 父类型；调用层级 谁调用了它 ↔ 它调用了谁
--   * 依赖库（jdt://）里的类/方法照样显示，Enter 能跳进反编译/源码
local K = require("config.idea_keys")
local Tree = require("config.kit.tree")

local M = {}
local api = vim.api

local function kind_name(kind)
  return vim.lsp.protocol.SymbolKind[kind] or "Class"
end

local function request(st, method, params, cb)
  local ok = pcall(function()
    st.client:request(method, params, function(err, result)
      if err then
        vim.notify(method .. " 出错：" .. tostring(err.message or err), vim.log.levels.WARN)
        cb({})
      else
        cb(result or {})
      end
    end, st.buf)
  end)
  if not ok then cb({}) end
end

local function item_key(item)
  return (item.uri or "") .. "|" .. (item.name or "") .. "|" .. (item.detail or "")
end

-- 祖先里已经有同一个条目（递归调用 / 循环继承）时不再展开
local function in_ancestors(node, key)
  local p = node
  while p do
    if p.key == key then return true end
    p = p.parent
  end
end

local function loc_of(item, range)
  return { uri = item.uri, range = range or item.selectionRange or item.range, encoding = "utf-16" }
end

-- ================================================================ 类型层级

local TYPE_MODES = { "full", "sub", "super" }
local TYPE_LABEL = { full = "完整层级", sub = "子类型", super = "父类型" }

-- 节点文字：类名  包名
function M.type_chunks(item, current)
  return {
    { item.name, current and "KitTreeCurrent" or nil },
    { "  " .. (item.detail or ""), "KitTreeDim" },
  }
end

local function type_node(st, item, method, current)
  local icon, hl = Tree.icon("lsp", kind_name(item.kind), "C")
  local node = {
    item = item,
    key = item_key(item),
    icon = icon,
    icon_hl = hl,
    chunks = M.type_chunks(item, current),
    loc = vim.tbl_extend("force", loc_of(item), { symbol = item.name, kind = "type" }),
    occurrence = true,
  }
  if method then
    node.load = function(n, done)
      request(st, method, { item = item }, function(res)
        local kids = {}
        for _, it in ipairs(res) do
          if not in_ancestors(n, item_key(it)) then kids[#kids + 1] = type_node(st, it, method) end
        end
        table.sort(kids, function(a, b) return a.item.name < b.item.name end)
        done(kids)
      end)
    end
  end
  return node
end

-- 完整层级：沿父类（非接口）一路向上，直到 Object；接口本身没有父类链
local function class_chain(st, item, done, acc, depth)
  acc = acc or {}
  depth = depth or 0
  if depth > 30 then return done(acc) end
  request(st, "typeHierarchy/supertypes", { item = item }, function(res)
    local sup
    for _, it in ipairs(res) do
      if it.kind ~= vim.lsp.protocol.SymbolKind.Interface then sup = it break end
    end
    if not sup then return done(acc) end
    table.insert(acc, 1, sup)
    class_chain(st, sup, done, acc, depth + 1)
  end)
end

function M.build_type_tree(st, cb)
  local item, mode = st.item, st.mode
  if mode == "sub" or mode == "super" then
    local root = type_node(st, item, mode == "sub" and "typeHierarchy/subtypes" or "typeHierarchy/supertypes", true)
    return cb({ root }, root)
  end
  class_chain(st, item, function(chain)
    local cur = type_node(st, item, "typeHierarchy/subtypes", true)
    local top, parent = nil, nil
    for _, it in ipairs(chain) do
      local n = type_node(st, it, nil)
      n.children, n.expanded = {}, true
      if parent then parent.children = { n } else top = n end
      parent = n
    end
    if parent then parent.children = { cur } else top = cur end
    cb({ top }, cur)
  end)
end

-- 显示树并展开当前类型（加载第一层）；cb(panel) 在第一层加载完后调用（测试用）
local function show_tree(p, st, builder, cb)
  local gen = p.gen + 1
  p:set_loading("加载中…")
  gen = p.gen
  builder(st, function(roots, cur)
    vim.schedule(function()
      if gen ~= p.gen then return end
      p:set_roots(roots)
      p:expand(cur, function()
        p:set_cursor(cur)
        if cb then cb(p) end
      end)
    end)
  end)
end

local type_state = {}

function M.type_panel()
  return Tree.new({
    name = "type_hierarchy",
    title = function()
      return "类型层级：" .. ((type_state.item or {}).name or "") .. "  [" .. TYPE_LABEL[type_state.mode or "full"] .. "]"
    end,
    hint = "Alt+S 切换 完整层级/子类型/父类型",
    empty = "没有类型层级",
    keys = {
      ["<M-s>"] = {
        label = "Alt+S",
        desc = "切换 完整层级 / 子类型 / 父类型",
        fn = function(p)
          if not type_state.item then return end
          local i = vim.fn.index(TYPE_MODES, type_state.mode) + 1
          type_state.mode = TYPE_MODES[i % #TYPE_MODES + 1]
          show_tree(p, type_state, M.build_type_tree)
        end,
      },
    },
  })
end

local function prepare(method, cb)
  local buf = api.nvim_get_current_buf()
  local client = vim.lsp.get_clients({ bufnr = buf, method = method })[1]
  if not client then
    vim.notify("当前文件没有语言服务，无法显示层级", vim.log.levels.WARN)
    return
  end
  local params = vim.lsp.util.make_position_params(0, client.offset_encoding)
  client:request(method, params, function(err, result)
    if err or not result or not result[1] then
      vim.notify("光标处没有可显示层级的类 / 方法", vim.log.levels.INFO)
      return
    end
    cb({ client = client, buf = buf, item = result[1] })
  end, buf)
end

-- Ctrl+H：类型层级。mode = "full"（默认，同 IDEA 的 Class Hierarchy）/ "sub" / "super"
function M.type_hierarchy(mode, cb)
  local win = api.nvim_get_current_win()
  prepare("textDocument/prepareTypeHierarchy", function(st)
    vim.schedule(function()
      st.mode = mode or "full"
      type_state = st
      local p = M.type_panel()
      if api.nvim_win_is_valid(win) then api.nvim_set_current_win(win) end
      p:show(true)
      show_tree(p, st, M.build_type_tree, cb)
    end)
  end)
end

-- ================================================================ 调用层级

-- "getUser(Long) : User" + "com.example.demo.service.UserService" → 类名.方法名(参数)、包名
function M.call_label(item)
  local name = (item.name or ""):gsub("%s*:%s*[^:]*$", "")
  local detail = item.detail or ""
  local pkg, cls = detail:match("^(.*)%.([^.]+)$")
  if not cls then cls, pkg = detail, "" end
  return (cls ~= "" and (cls .. ".") or "") .. name, pkg
end

function M.call_chunks(item, extra, current)
  local label, pkg = M.call_label(item)
  local ch = { { label, current and "KitTreeCurrent" or nil } }
  if extra then ch[#ch + 1] = { extra, "KitTreeCount" } end
  ch[#ch + 1] = { "  " .. pkg, "KitTreeDim" }
  return ch
end

local call_state = {}
local CALL_LABEL = { incoming = "谁调用了它", outgoing = "它调用了谁" }

local function call_node(st, item, loc, extra, current)
  local icon, hl = Tree.icon("lsp", kind_name(item.kind), "m")
  local node = {
    item = item,
    key = item_key(item),
    icon = icon,
    icon_hl = hl,
    chunks = M.call_chunks(item, extra, current),
    loc = loc or vim.tbl_extend("force", loc_of(item), { symbol = (item.name or ""):match("^[%w_$]+") }),
    occurrence = true,
  }
  node.load = function(n, done)
    local method = st.dir == "incoming" and "callHierarchy/incomingCalls" or "callHierarchy/outgoingCalls"
    request(st, method, { item = item }, function(res)
      local kids = {}
      for _, r in ipairs(res) do
        local it = st.dir == "incoming" and r.from or r.to
        local ranges = r.fromRanges or {}
        -- 谁调用了它：跳到调用处（在调用方里）；它调用了谁：跳到被调用方法的声明
        local l = st.dir == "incoming" and ranges[1] and loc_of(it, ranges[1]) or loc_of(it)
        local extra2 = #ranges > 1 and ("  (" .. #ranges .. " 处)") or nil
        local child = call_node(st, it, l, extra2)
        if in_ancestors(n, child.key) then
          child.load = nil
          child.children = {}
          child.chunks[#child.chunks + 1] = { "  （递归）", "KitTreeDim" }
        end
        kids[#kids + 1] = child
      end
      table.sort(kids, function(a, b) return M.call_label(a.item) < M.call_label(b.item) end)
      done(kids)
    end)
  end
  return node
end

function M.build_call_tree(st, cb)
  local root = call_node(st, st.item, nil, nil, true)
  cb({ root }, root)
end

function M.call_panel()
  return Tree.new({
    name = "call_hierarchy",
    title = function()
      return "调用层级：" .. (call_state.item and M.call_label(call_state.item) or "") .. "  [" .. CALL_LABEL[call_state.dir or "incoming"] .. "]"
    end,
    hint = "Alt+S 切换 谁调用了它/它调用了谁",
    empty = "没有调用层级",
    keys = {
      ["<M-s>"] = {
        label = "Alt+S",
        desc = "切换 谁调用了它 / 它调用了谁",
        fn = function(p)
          if not call_state.item then return end
          call_state.dir = call_state.dir == "incoming" and "outgoing" or "incoming"
          show_tree(p, call_state, M.build_call_tree)
        end,
      },
    },
  })
end

-- Ctrl+Alt+H：调用层级。dir = "incoming"（默认）/ "outgoing"
function M.call_hierarchy(dir, cb)
  local win = api.nvim_get_current_win()
  prepare("textDocument/prepareCallHierarchy", function(st)
    vim.schedule(function()
      st.dir = dir or "incoming"
      call_state = st
      local p = M.call_panel()
      if api.nvim_win_is_valid(win) then api.nvim_set_current_win(win) end
      p:show(true)
      show_tree(p, st, M.build_call_tree, cb)
    end)
  end)
end

K.map(K.NI, "<C-h>", K.n(function() M.type_hierarchy() end), "类型层级（Alt+S 切换父类型/子类型）")
-- 终端里 Ctrl+Alt+H 到达时是 Alt+Backspace，两种写法都映射
for _, lhs in ipairs({ "<C-M-h>", "<M-BS>" }) do
  K.map(K.NI, lhs, K.n(function() M.call_hierarchy() end), "调用层级（Alt+S 切换调用方/被调用）")
end

return M
