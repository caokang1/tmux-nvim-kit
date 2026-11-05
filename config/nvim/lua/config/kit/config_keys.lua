-- 配置项 ↔ 代码（IDEA Spring 插件的配置文件导航）
--   * application.yml / .properties 中光标在配置键上，Ctrl+B 或 Alt+F7：列出 Java 里的使用处
--     @Value("${demo.name}")、@Value("${demo.name:默认值}")、@ConfigurationProperties(prefix = "demo.feature") 类的对应字段
--     （松散绑定：max-size ↔ maxSize）；一处直接跳，多处弹出列表
--   * Java 中光标在 @Value("${...}") 里、或 @ConfigurationProperties 类的字段上，Ctrl+B：跳到配置文件里的定义；
--     多个 profile（application-dev.yml ...）都有时弹出列表并显示 profile 名
-- 只做文本解析（ripgrep + treesitter），不依赖 jdtls
local K = require("config.idea_keys")
local U = require("config.kit.spring.util")
local J = require("config.kit.spring.java")

local M = {}

-- ================= 解析（可单独测试） =================

-- 松散绑定：比较时忽略大小写、- 和 _（max-size、maxSize、max_size、MAX_SIZE 都算同一个）
function M.canon(key)
  return (key:lower():gsub("[-_]", ""))
end

local function strip_quotes(s)
  return (s:gsub("^%s*[\"'](.*)[\"']%s*$", "%1"))
end

-- 解析 yml：返回按行的键 { [行号] = { key = "demo.feature.max-size", col = 键所在列(0 基), doc = 第几个文档 } }
-- 和 profiles（{ [doc] = profile 名 }，来自 spring.profiles / spring.config.activate.on-profile）
function M.parse_yaml(lines)
  local keys, profiles = {}, {}
  local stack = {} -- { indent, key }
  local doc = 1
  local block_indent -- 多行文本（| 或 >）的键缩进，里面的行不是键
  for i, l in ipairs(lines) do
    if l:match("^%-%-%-") then
      stack, doc, block_indent = {}, doc + 1, nil
    elseif l:match("^%s*$") or l:match("^%s*#") then
      -- 空行 / 注释
    else
      local indent = #l:match("^(%s*)")
      if block_indent and indent > block_indent then
        -- 多行文本内容
      else
        block_indent = nil
        -- 列表项 "- key: v"：把 "- " 当作缩进
        local dash = l:match("^%s*(%-%s+)")
        local rest_start = indent + (dash and #dash or 0)
        local rest = l:sub(rest_start + 1)
        local k, after = rest:match("^([^#:%s][^:]-)%s*:(.*)$")
        if not k then
          k, after = rest:match("^([\"'].-[\"'])%s*:(.*)$")
        end
        if k and (after == "" or after:match("^%s")) then
          local kind = rest_start
          while #stack > 0 and stack[#stack].indent >= kind do table.remove(stack) end
          local name = strip_quotes(k)
          local parts = {}
          for _, s in ipairs(stack) do parts[#parts + 1] = s.key end
          parts[#parts + 1] = name
          local full = table.concat(parts, ".")
          keys[i] = { key = full, col = rest_start, doc = doc }
          table.insert(stack, { indent = kind, key = name })
          local value = vim.trim((after:gsub("%s+#.*$", "")))
          if value:match("^[|>][+-]?%d*$") then block_indent = indent end
          if full == "spring.profiles" or full == "spring.config.activate.on-profile" then
            if value ~= "" then profiles[doc] = strip_quotes(value) end
          end
        end
      end
    end
  end
  return keys, profiles
end

-- 解析 .properties：{ [行号] = { key, col } }
function M.parse_properties(lines)
  local keys = {}
  local cont = false
  for i, l in ipairs(lines) do
    if not cont and not l:match("^%s*[#!]") and not l:match("^%s*$") then
      local ws, k = l:match("^(%s*)([^=:%s]+)")
      if k then keys[i] = { key = k, col = #ws, doc = 1 } end
    end
    -- 行尾反斜杠表示值续到下一行
    cont = l:match("\\$") ~= nil and not l:match("\\\\$")
  end
  return keys
end

-- profile 名：application-dev.yml → dev；application.yml → 默认
function M.profile_of(path, doc_profile)
  if doc_profile then return doc_profile end
  local base = vim.fn.fnamemodify(path, ":t:r")
  return base:match("^[%w]+%-(.+)$") or "默认"
end

local cfg_cache = {}
-- 解析一个配置文件（带缓存）：{ keys = { [行号] = {...} }, profiles = {...} }
function M.config_file(path)
  local mt = U.mtime(path)
  local b = vim.fn.bufnr(path)
  local modified = b ~= -1 and vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified
  local c = cfg_cache[path]
  if c and c.mtime == mt and not modified then return c end
  local lines = U.lines(path)
  if path:match("%.properties$") then
    c = { keys = M.parse_properties(lines), profiles = {} }
  else
    c = {}
    c.keys, c.profiles = M.parse_yaml(lines)
  end
  c.mtime = mt
  if not modified then cfg_cache[path] = c end
  return c
end

-- 光标所在行的配置键
function M.key_at(buf, lnum)
  local path = vim.api.nvim_buf_get_name(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local keys = path:match("%.properties$") and M.parse_properties(lines) or (M.parse_yaml(lines))
  local k = keys[lnum]
  return k and k.key
end

-- ================= 配置键 → Java 使用处 =================

-- @ConfigurationProperties 类：{ prefix, class = 类节点, info }，按文件缓存在 J.file 里
local function props_classes(root)
  local res = {}
  for _, f in ipairs(U.rg({ "-l", "-g", "*.java", "-e", "@ConfigurationProperties\\b", "." }, root)) do
    local info = J.file(f)
    if info then
      for _, c in ipairs(info.classes) do
        local args = J.annotations(c.node, info.src).ConfigurationProperties
        local pnode = args and (args.prefix or args.value)
        if pnode then
          local prefix = J.eval(pnode, { info = info, root = root })
          res[#res + 1] = { prefix = prefix, node = c.node, info = info, file = f, name = c.name }
        end
      end
    end
  end
  return res
end

-- 类里的字段：{ 规范名 = { name, lnum, col, type } }
local function fields_of(class_node, src)
  local res = {}
  local body = class_node:field("body")[1]
  if not body then return res end
  for m in body:iter_children() do
    if m:type() == "field_declaration" and not J.has_modifier(m, "static", src) then
      local typ = m:field("type")[1]
      for d in m:iter_children() do
        if d:type() == "variable_declarator" then
          local n = d:field("name")[1]
          local r, c = n:range()
          local name = J.text(n, src)
          res[M.canon(name)] = { name = name, lnum = r + 1, col = c, type = typ and J.text(typ, src) }
        end
      end
    end
  end
  return res
end

local function nested_class(info, name)
  for _, c in ipairs(info.classes) do
    if c.name == name then return c.node end
  end
end

local function line_text(path, lnum)
  return vim.trim(U.lines(path)[lnum] or "")
end

-- 列出配置键在 Java 里的使用处：{ { file, lnum, col, label, detail } }
function M.usages(key, root)
  root = root or U.root()
  local res = {}
  local ckey = M.canon(key)
  -- @Value("${key}") / ${key:默认值} / 父键 ${key.xxx}
  local esc = vim.fn.escape(key, "\\.^$*+?()[]{}|")
  for _, m in ipairs(U.rg_lines("\\$\\{" .. esc .. "[}:.]", { "*.java", "*.kt" }, root)) do
    res[#res + 1] = { file = m.file, lnum = m.lnum, col = m.col - 1, label = vim.trim(m.text), detail = vim.fn.fnamemodify(m.file, ":t:r") }
  end
  -- @ConfigurationProperties 前缀 + 字段（松散绑定）
  for _, pc in ipairs(props_classes(root)) do
    local cprefix = M.canon(pc.prefix)
    if ckey == cprefix or vim.startswith(cprefix, ckey .. ".") then
      -- 光标在前缀（或更上层的键）上：跳到类
      local r, c = pc.node:field("name")[1]:range()
      res[#res + 1] = { file = pc.file, lnum = r + 1, col = c, label = line_text(pc.file, r + 1), detail = "@ConfigurationProperties " .. pc.name }
    elseif vim.startswith(ckey, cprefix .. ".") then
      local rest = vim.split(ckey:sub(#cprefix + 2), ".", { plain = true })
      local node, hit = pc.node, nil
      for i, seg in ipairs(rest) do
        local f = fields_of(node, pc.info.src)[seg:gsub("%[%d+%]$", "")]
        if not f then break end
        hit = f
        if i < #rest then
          -- 嵌套属性：字段类型是同一文件里的内部类时继续往下找
          local inner = f.type and nested_class(pc.info, f.type:match("([%w_]+)>?$"))
          if not inner then break end
          node = inner
        end
      end
      if hit then
        res[#res + 1] = { file = pc.file, lnum = hit.lnum, col = hit.col, label = line_text(pc.file, hit.lnum), detail = pc.name .. "." .. hit.name }
      end
    end
  end
  return res
end

-- ================= Java → 配置文件定义 =================

-- 光标处 @Value("${...}") 里的键（cursor col 0 基）
function M.value_key_at(line, col)
  local init = 1
  while true do
    local s, e, inner = line:find("%${([^}]*)}", init)
    if not s then return nil end
    if col + 1 >= s and col + 1 <= e then
      return (inner:gsub(":.*$", ""))
    end
    init = e + 1
  end
end

-- 在所有配置文件里找键的定义：{ { file, lnum, col, label = profile, detail } }
function M.definitions(key, root)
  root = root or U.root()
  local ckey = M.canon(key)
  local files = U.rg({ "--files",
    "-g", "**/application*.{yml,yaml,properties}",
    "-g", "**/bootstrap*.{yml,yaml,properties}",
  }, root)
  table.sort(files)
  local res = {}
  for _, f in ipairs(files) do
    local c = M.config_file(f)
    local lnums = vim.tbl_keys(c.keys)
    table.sort(lnums)
    for _, l in ipairs(lnums) do
      local k = c.keys[l]
      if M.canon(k.key) == ckey then
        res[#res + 1] = {
          file = f,
          lnum = l,
          col = k.col,
          label = M.profile_of(f, c.profiles[k.doc]),
          detail = line_text(f, l),
        }
      end
    end
  end
  return res
end

-- Java 光标处对应的配置键：@Value 字符串里，或 @ConfigurationProperties 类的字段 / 注解前缀上
function M.java_key_at()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local k = M.value_key_at(line, col)
  if k then return k, "value" end
  -- 没有 @ConfigurationProperties 的文件不用解析语法树
  if vim.fn.search("@ConfigurationProperties", "nw") == 0 then return nil end
  local info = J.file(vim.api.nvim_buf_get_name(0))
  if not info then return nil end
  local node = info.root:named_descendant_for_range(row - 1, col, row - 1, col)
  -- 字段名：identifier ← variable_declarator ← field_declaration ← class_body ← class_declaration
  if node and node:type() == "identifier" and node:parent() and node:parent():type() == "variable_declarator" then
    local field = node:parent():parent()
    local cls = field and field:parent() and field:parent():parent()
    if field and field:type() == "field_declaration" and cls and cls:type() == "class_declaration" then
      local args = J.annotations(cls, info.src).ConfigurationProperties
      local pnode = args and (args.prefix or args.value)
      if pnode then
        return J.eval(pnode, { info = info, root = U.root() }) .. "." .. J.text(node, info.src), "field"
      end
    end
  end
  return nil
end

-- ================= 跳转入口 =================

local function is_config_ft(ft) return ft == "yaml" or ft == "jproperties" or ft == "properties" end

-- 配置文件里：列出使用处（Ctrl+B / Alt+F7）
function M.show_usages()
  local key = M.key_at(0, vim.api.nvim_win_get_cursor(0)[1])
  if not key then return false end
  local items = M.usages(key)
  if #items == 0 then
    vim.notify("代码里没有找到配置项 " .. key .. " 的使用处", vim.log.levels.INFO)
    return true
  end
  return U.pick("配置项 " .. key .. " 的使用处", items)
end

function M.navigate()
  local ft = vim.bo.filetype
  if is_config_ft(ft) then return M.show_usages() end
  if ft ~= "java" then return false end
  local key, kind = M.java_key_at()
  if not key then return false end
  local defs = M.definitions(key)
  if #defs == 0 then
    if kind == "value" then
      vim.notify("配置文件里没有找到 " .. key, vim.log.levels.INFO)
      return true
    end
    return false -- 字段没有对应配置：交给语言服务（在声明处显示用法）
  end
  return U.pick("配置项 " .. key .. " 的定义", defs)
end

require("config.kit.goto").register("config_keys", M.navigate, 20)

-- yml / properties 文件里 Alt+F7 = 列出使用处（只对这些文件生效，其他文件仍是查找用法）
local function buf_keys(buf)
  K.map(K.NI, "<M-F7>", K.n(function() M.show_usages() end), "列出配置项的使用处", { buffer = buf })
end
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("kit_config_keys", { clear = true }),
  pattern = { "yaml", "jproperties", "properties" },
  callback = function(ev) buf_keys(ev.buf) end,
})
-- 本模块在启动后才加载：启动时就打开的配置文件补上按键
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(b) and is_config_ft(vim.bo[b].filetype) then buf_keys(b) end
end

return M
