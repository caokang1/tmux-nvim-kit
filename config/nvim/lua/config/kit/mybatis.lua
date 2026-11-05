-- MyBatis Mapper 接口 ↔ XML 互跳（IDEA MyBatisX 插件）
--   * Mapper 接口方法名上 Ctrl+B → XML 里 id="方法名" 的语句；接口名上 → <mapper namespace=...>
--   * XML 里语句的 id、namespace 上 Ctrl+B → 接口方法 / 接口
--   * XML 里 resultMap="X"、<include refid="X"/>、extends="X" → 定义处（支持 namespace.X 跨文件）；
--     type= / resultType= / parameterType= 等全限定类名 → 类文件
--   * 左侧显示 MyBatis 图标（接口方法行、XML 语句行），点击图标跳到另一边
-- 匹配规则和 MyBatis 一样：XML 的 namespace = 接口全限定名。只做文本解析，不依赖 jdtls
local U = require("config.kit.spring.util")
local J = require("config.kit.spring.java")

local M = {}
local STMT = { select = true, insert = true, update = true, delete = true }
M.icon = "󰆼"

-- ================= 文本解析（可单独测试） =================

-- 解析 Mapper XML：namespace（及所在行）、所有带 id 的元素 { id = { tag, lnum, col } }
-- 属性可能和标签不在同一行，按"最近出现的 <标签"判断所属元素
function M.parse_xml_lines(lines)
  local res = { ids = {} }
  local tag
  for i, l in ipairs(lines) do
    local pos = 1
    while true do
      local ts, te, t = l:find("<([%w_:%-]+)", pos)
      local as, ae, name, value = l:find("([%w_:%-]+)%s*=%s*\"([^\"]*)\"", pos)
      if not ts and not as then break end
      if ts and (not as or ts < as) then
        tag = t
        pos = te + 1
      else
        if name == "namespace" and tag == "mapper" then
          res.namespace, res.ns_lnum, res.ns_col = value, i, ae - #value - 1
        elseif name == "id" and tag and not res.ids[value] then
          res.ids[value] = { tag = tag, lnum = i, col = ae - #value - 1 }
        end
        pos = ae + 1
      end
    end
  end
  return res
end

-- 带缓存的 XML 解析
local xml_cache = {}
function M.xml(path)
  local mt = U.mtime(path)
  local b = vim.fn.bufnr(path)
  local modified = b ~= -1 and vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified
  local c = xml_cache[path]
  if c and c.mtime == mt and not modified then return c end
  c = M.parse_xml_lines(U.lines(path))
  c.mtime, c.path = mt, path
  if not modified then xml_cache[path] = c end
  return c
end

-- 找 namespace 等于 fqn 的 XML 文件
function M.find_xml(ns, root)
  local files = U.rg({ "-l", "-F", "-g", "*.xml", "-e", 'namespace="' .. ns .. '"', "." }, root)
  local res = {}
  for _, f in ipairs(files) do
    if M.xml(f).namespace == ns then res[#res + 1] = f end
  end
  return res
end

-- Java 文件的包名 + 顶层接口：{ fqn, name, lnum, col, is_mapper(@Mapper), methods = { 名字 = { lnum, col } } }
function M.java_mapper(path)
  local info = J.file(path)
  if not info then return nil end
  for _, c in ipairs(info.classes) do
    local node = c.node
    if node:type() == "interface_declaration" and node:parent():type() == "program" then
      local name_node = node:field("name")[1]
      local row, col = name_node:range()
      local res = {
        name = c.name,
        fqn = (info.package and info.package .. "." or "") .. c.name,
        lnum = row + 1,
        col = col,
        is_mapper = J.annotations(node, info.src).Mapper ~= nil,
        methods = {},
      }
      local body = node:field("body")[1]
      for m in body:iter_children() do
        if m:type() == "method_declaration" then
          local n = m:field("name")[1]
          local r, cc = n:range()
          local mname = J.text(n, info.src)
          res.methods[mname] = res.methods[mname] or { lnum = r + 1, col = cc }
        end
      end
      return res
    end
  end
end

-- ================= 跳转 =================

-- Java：光标在 Mapper 接口的方法名 / 接口名上 → XML
local function from_java()
  local buf = vim.api.nvim_get_current_buf()
  local path = vim.api.nvim_buf_get_name(buf)
  -- 不是接口的文件不用解析语法树
  if vim.fn.search("\\<interface\\>", "nw") == 0 then return false end
  local mp = M.java_mapper(path)
  if not mp then return false end
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local word = vim.fn.expand("<cword>")
  local target
  local m = mp.methods[word]
  if m and m.lnum == row then
    target = word
  elseif not (word == mp.name and mp.lnum == row) then
    return false
  end
  local xmls = M.find_xml(mp.fqn, U.root(buf))
  if #xmls == 0 then
    if mp.is_mapper and target then
      vim.notify("没有找到 namespace=\"" .. mp.fqn .. "\" 的 Mapper XML", vim.log.levels.INFO)
    end
    return false
  end
  local items = {}
  for _, f in ipairs(xmls) do
    local x = M.xml(f)
    if target then
      local d = x.ids[target]
      if d and STMT[d.tag] then
        items[#items + 1] = { file = f, lnum = d.lnum, col = d.col, label = "<" .. d.tag .. " id=\"" .. target .. "\">", detail = U.module_of(f) }
      end
    else
      items[#items + 1] = { file = f, lnum = x.ns_lnum, col = x.ns_col, label = "<mapper namespace>", detail = U.module_of(f) }
    end
  end
  if #items == 0 then
    -- 接口方法用注解写 SQL（@Select）时 XML 里没有，交给语言服务
    return false
  end
  return U.pick("跳转到 Mapper XML", items)
end

-- 找接口文件
local function interface_file(fqn, root)
  local files = U.find_class(fqn, root)
  return files[1]
end

-- XML 内（或跨文件 namespace.id）找某个 id 的定义
local function xml_id(cur_path, ref, tags)
  local x = M.xml(cur_path)
  local ns, id = ref:match("^(.+)%.([^.]+)$")
  local files = { cur_path }
  if ns and ns ~= x.namespace then
    files = M.find_xml(ns, U.root())
  elseif ns then
    -- 同一个文件里写成 namespace.id
  else
    id = ref
  end
  for _, f in ipairs(files) do
    local d = M.xml(f).ids[id]
    if d and (not tags or tags[d.tag]) then
      U.jump(f, d.lnum, d.col)
      return true
    end
  end
  return false
end

-- XML：光标在属性值上
local function from_xml()
  local path = vim.api.nvim_buf_get_name(0)
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local name, value = U.attr_at(line, col)
  if not name or value == "" then return false end
  local x = M.xml(path)
  if not x.namespace then return false end
  local root = U.root()
  if name == "namespace" then
    local f = interface_file(value, root)
    if not f then
      vim.notify("没有找到接口 " .. value, vim.log.levels.INFO)
      return true
    end
    local mp = M.java_mapper(f)
    U.jump(f, mp and mp.lnum or 1, mp and mp.col or 0)
    return true
  elseif name == "id" then
    -- 属性所属的标签：本行光标前最近的 <标签，没有就往上找
    local tag
    for t in line:sub(1, col + 1):gmatch("<([%w_:%-]+)") do tag = t end
    local r = row - 1
    while not tag and r >= 1 do
      local l = vim.api.nvim_buf_get_lines(0, r - 1, r, false)[1]
      for t in l:gmatch("<([%w_:%-]+)") do tag = t end
      r = r - 1
    end
    if not STMT[tag] then return false end
    local f = interface_file(x.namespace, root)
    if not f then
      vim.notify("没有找到接口 " .. x.namespace, vim.log.levels.INFO)
      return true
    end
    local mp = M.java_mapper(f)
    local m = mp and mp.methods[value]
    if not m then
      vim.notify(x.namespace .. " 里没有方法 " .. value, vim.log.levels.INFO)
      U.jump(f, mp and mp.lnum or 1, mp and mp.col or 0)
      return true
    end
    U.jump(f, m.lnum, m.col)
    return true
  elseif name == "resultMap" or name == "extends" then
    return xml_id(path, value, { resultMap = true })
  elseif name == "refid" then
    return xml_id(path, value, { sql = true })
  elseif name == "type" or name == "resultType" or name == "parameterType" or name == "ofType" or name == "javaType" then
    if not value:find("%.") then return false end -- 别名（如 int、User）无法确定
    local f = interface_file(value, root)
    if not f then return false end
    local info = J.file(f)
    local lnum, c = 1, 0
    for _, cl in ipairs(info and info.classes or {}) do
      if cl.name == value:match("([%w_]+)$") then
        local r, cc = cl.node:field("name")[1]:range()
        lnum, c = r + 1, cc
        break
      end
    end
    U.jump(f, lnum, c)
    return true
  end
  return false
end

function M.navigate()
  local ft = vim.bo.filetype
  if ft == "java" then return from_java() end
  if ft == "xml" then return from_xml() end
  return false
end

require("config.kit.goto").register("mybatis", M.navigate, 20)

-- ================= 左侧图标 =================
local ns = vim.api.nvim_create_namespace("kit_mybatis")
local SC = require("config.kit.signclick")
vim.api.nvim_set_hl(0, "KitMyBatisSign", { default = true, fg = "#e5534b" })

-- 在某行放图标，点击时把光标放到 col 后执行 Ctrl+B 的 MyBatis 跳转
local function place(buf, marks)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local handlers = {}
  for _, mk in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, mk.lnum - 1, 0, {
      sign_text = M.icon,
      sign_hl_group = "KitMyBatisSign",
      priority = 15,
    })
    handlers[mk.lnum] = {
      label = mk.label,
      fn = function()
        pcall(vim.api.nvim_win_set_cursor, 0, { mk.lnum, mk.col })
        M.navigate()
      end,
    }
  end
  SC.set(buf, "mybatis", handlers)
end

-- 计算某个缓冲区需要的图标（返回 marks，供测试）
function M.marks(buf)
  local path = vim.api.nvim_buf_get_name(buf)
  local ft = vim.bo[buf].filetype
  local root = U.root(buf)
  local marks = {}
  if ft == "java" then
    local mp = M.java_mapper(path)
    if not mp then return marks end
    for _, f in ipairs(M.find_xml(mp.fqn, root)) do
      local x = M.xml(f)
      for name, m in pairs(mp.methods) do
        local d = x.ids[name]
        if d and STMT[d.tag] then marks[#marks + 1] = { lnum = m.lnum, col = m.col, label = "跳到 XML：" .. name } end
      end
    end
  elseif ft == "xml" then
    local x = M.xml(path)
    if not x.namespace then return marks end
    local f = interface_file(x.namespace, root)
    local mp = f and M.java_mapper(f)
    if not mp then return marks end
    marks[#marks + 1] = { lnum = x.ns_lnum, col = x.ns_col, label = "跳到接口" }
    for id, d in pairs(x.ids) do
      if STMT[d.tag] and mp.methods[id] then marks[#marks + 1] = { lnum = d.lnum, col = d.col, label = "跳到接口方法：" .. id } end
    end
  end
  table.sort(marks, function(a, b) return a.lnum < b.lnum end)
  return marks
end

-- 只处理可能是 Mapper 的文件：Java 接口（@Mapper 或名字像 Mapper/Dao）、含 <mapper namespace 的 XML；
-- rg 在后台定时器里跑，不拖慢打开文件
local function maybe_refresh(buf)
  if not vim.api.nvim_buf_is_valid(buf) or vim.bo[buf].buftype ~= "" then return end
  local ft = vim.bo[buf].filetype
  local head = table.concat(vim.api.nvim_buf_get_lines(buf, 0, math.min(200, vim.api.nvim_buf_line_count(buf)), false), "\n")
  if ft == "java" then
    if not head:find("interface%s") then return end
  elseif ft == "xml" then
    if not head:find("<mapper[%s>]") then return end
  else
    return
  end
  vim.defer_fn(function()
    if not vim.api.nvim_buf_is_valid(buf) then return end
    local ok, marks = pcall(M.marks, buf)
    if ok then place(buf, marks) end
  end, 50)
end
M.refresh = maybe_refresh

local group = vim.api.nvim_create_augroup("kit_mybatis", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = { "java", "xml" },
  callback = function(ev) maybe_refresh(ev.buf) end,
})
vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  pattern = { "*.java", "*.xml" },
  callback = function(ev) maybe_refresh(ev.buf) end,
})
-- 本模块在启动后才加载：启动时就打开的文件补上图标
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(b) then maybe_refresh(b) end
end

return M
