-- 文件树压缩空包（IDEA: Compact Middle Packages）：只有一个子目录、没有文件的目录链合并成一个节点，
-- 如 java/com/example/demo。展开 / 折叠作用于整条链；空格 u P 开关（默认开）。
--
-- 实现方式（snacks explorer 没有提供这个扩展点，所以包装它的 finder，见 plugins/kit-explorer_compact.lua）：
--   1. 生成列表前先走一遍可见的目录：某目录只有一个（过滤后可见的）子项且它是目录 → 记为"中间目录"，
--      并把它标记为展开（这样 snacks 的遍历会继续进入链的下一层）
--   2. snacks 逐个产出列表项时，跳过中间目录，把链头的列表项改成代表整条链：路径取链尾
--      （回车/右键展开、新建文件、定位当前文件都作用在链尾），显示名为 a/b/c
--   3. 链尾的子项改挂到链头的列表项下，树形缩进线正确
-- 风险：依赖 snacks 内部的 snacks.explorer.tree 和 explorer finder 的产出顺序，snacks 升级后若显示异常，
-- 按 空格 u P 关掉即恢复原样（关掉后不再介入任何逻辑）。
local M = {}

M.enabled = true

--- 纯计算：给一个目录结构，返回压缩后的节点（测试用，也说明规则）
--- tree 形如 { src = { main = { java = { com = { ["A.java"] = true } } } }, ["pom.xml"] = true }，目录是表、文件是 true
---@return string[] 按显示顺序（目录在前、同级按名字）的节点名，子节点前加两个空格缩进
function M.compress(tree)
  local out = {}
  local function sorted(t)
    local names = vim.tbl_keys(t)
    table.sort(names, function(a, b)
      local da, db = type(t[a]) == "table", type(t[b]) == "table"
      if da ~= db then return da end
      return a < b
    end)
    return names
  end
  local function walk(t, indent)
    for _, name in ipairs(sorted(t)) do
      local node, label = t[name], name
      if type(node) == "table" then
        -- 只有一个子项且是目录：并入当前节点
        while true do
          local kids = vim.tbl_keys(node)
          if #kids ~= 1 or type(node[kids[1]]) ~= "table" then break end
          label = label .. "/" .. kids[1]
          node = node[kids[1]]
        end
        out[#out + 1] = indent .. label
        walk(node, indent .. "  ")
      else
        out[#out + 1] = indent .. label
      end
    end
  end
  walk(tree, "")
  return out
end

--- 生成列表前：找出可见范围内的中间目录（只有一个可见子项且它是目录），并让它们保持展开
---@param cwd string
---@param opts table explorer 的选项（hidden / ignored / exclude / include 过滤）
---@return table<string, true> 中间目录的路径
function M.prepare(cwd, opts)
  local Tree = require("snacks.explorer.tree")
  local filter = Tree:filter(opts)
  local inter = {}
  local function kids(node)
    if not node.expanded then Tree:expand(node) end -- 只读目录项（fs_scandir），结果缓存在树里
    local ret = {}
    for _, c in pairs(node.children) do
      if filter(c) then ret[#ret + 1] = c end
    end
    return ret
  end
  local function visit(node, depth)
    if depth > 100 then return end -- 防止符号链接成环
    local ok, k = pcall(kids, node)
    if not ok then return end
    if #k == 1 and k[1].dir then
      inter[node.path] = true
      node.open = true
      return visit(k[1], depth + 1)
    end
    if node.open then
      for _, c in ipairs(k) do
        if c.dir then visit(c, depth + 1) end
      end
    end
  end
  local top = Tree:find(cwd)
  top.open = true
  local ok, k = pcall(kids, top)
  if ok then
    for _, c in ipairs(k) do
      if c.dir then visit(c, 1) end
    end
  end
  return inter
end

local COPY = { "file", "text", "dir", "open", "status", "dir_status", "type", "severity" }

--- 包装 snacks explorer 的 finder
function M.finder(opts, ctx)
  local Explorer = require("snacks.picker.source.explorer")
  local inner = Explorer.explorer(opts, ctx)
  -- 搜索模式（文件树里输入过滤文字）用的是另一套平铺结果，不压缩
  if not M.enabled or not ctx.filter:is_empty() or ctx.picker.input.filter.meta.searching then
    return inner
  end
  return function(cb)
    local inter = M.prepare(ctx.filter.cwd, opts)
    local alias = {} ---@type table<table, table> 链尾的原列表项 -> 代表整条链的列表项
    local chain ---@type {head: table, names: string[], items: table[], last: string}?
    local function flush()
      -- 链没有接上（目录在两步之间变了）：原样产出，宁可不压缩也不丢节点
      if chain then
        for _, it in ipairs(chain.items) do cb(it) end
        chain = nil
      end
    end
    inner(function(item)
      if item.parent and alias[item.parent] then item.parent = alias[item.parent] end
      local name = vim.fs.basename(item.file)
      local parent_file = item.parent and item.parent.file
      if chain and parent_file ~= chain.last then flush() end
      if inter[item.file] then
        if chain then
          chain.names[#chain.names + 1] = name
          chain.items[#chain.items + 1] = item
          chain.last = item.file
        else
          chain = { head = item, names = { name }, items = { item }, last = item.file }
        end
        return
      end
      if chain then
        -- 链尾：链头的列表项（保留它在同级中的位置、"是否最后一个"等）改为代表链尾
        local head = chain.head
        head.compact_head = head.file
        for _, k in ipairs(COPY) do head[k] = item[k] end
        head.ignored = head.ignored or item.ignored
        head.compact = table.concat(chain.names, "/") .. "/" .. name
        alias[item] = head
        chain = nil
        return cb(head)
      end
      cb(item)
    end)
    flush()
  end
end

--- 显示：压缩节点的名字显示为 a/b/c
function M.format(item, picker)
  local ret = Snacks.picker.format.file(item, picker)
  if item.compact then
    for _, seg in ipairs(ret) do
      if seg.field == "file" and type(seg[1]) == "string" then
        seg[1] = item.compact
        break
      end
    end
  end
  return ret
end

--- ← / h：在折叠的压缩节点上按，跳到整条链的上一级（原逻辑会跳到链中间被隐藏的目录）
function M.explorer_close(picker, item)
  local Actions = require("snacks.explorer.actions")
  if M.enabled and item and item.compact_head and item.dir and not item.open then
    local dir = vim.fs.dirname(item.compact_head)
    require("snacks.explorer.tree"):close(dir)
    return Actions.update(picker, { target = dir, refresh = true })
  end
  return Actions.actions.explorer_close(picker, item)
end

function M.refresh()
  for _, p in ipairs(Snacks.picker.get({ source = "explorer" })) do
    p.list:set_target()
    p:find()
  end
end

Snacks.toggle({
  name = "文件树压缩空包",
  get = function() return M.enabled end,
  set = function(v)
    M.enabled = v
    M.refresh()
  end,
}):map("<leader>uP")

return M
