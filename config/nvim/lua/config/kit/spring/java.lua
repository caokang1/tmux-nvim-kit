-- 用 treesitter 解析 Java 源码文本（不需要 jdtls）：注解参数、字符串常量（含跨文件的常量拼接）
local U = require("config.kit.spring.util")
local M = {}

local ts = vim.treesitter

-- 解析结果按文件修改时间缓存：{ mtime, src, root, package, imports, static_imports, consts, classes }
local cache = {}

local function text(node, src) return ts.get_node_text(node, src) end

-- 去掉字符串字面量的引号，处理常见转义
local function unquote(s)
  s = s:gsub('^"""%s*\n?', ""):gsub('"""$', "")
  s = s:gsub('^"', ""):gsub('"$', "")
  return (s:gsub("\\(.)", { n = "\n", t = "\t", ['"'] = '"', ["\\"] = "\\" }))
end
M.unquote = unquote

-- 注解：返回 名字（不含 @ 和包名）, 参数表 { value = node, path = node, ... }（只写一个值时记为 value）
function M.annotation(node, src)
  local name_node = node:field("name")[1]
  if not name_node then return nil end
  local name = text(name_node, src):match("([%w_]+)$")
  local args = {}
  local list = node:field("arguments")[1]
  if list then
    for child in list:iter_children() do
      if child:named() then
        if child:type() == "element_value_pair" then
          local k, v = child:field("key")[1], child:field("value")[1]
          if k and v then args[text(k, src)] = v end
        elseif child:type() ~= "comment" then
          args.value = child
        end
      end
    end
  end
  return name, args
end

-- 声明（类 / 方法 / 字段）上的所有注解：{ 名字 = 参数表 }
function M.annotations(decl, src)
  local res = {}
  for child in decl:iter_children() do
    if child:type() == "modifiers" then
      for m in child:iter_children() do
        if m:type() == "annotation" or m:type() == "marker_annotation" then
          local name, args = M.annotation(m, src)
          if name then res[name] = args end
        end
      end
    end
  end
  return res
end

-- 声明是否带某个修饰符（static / final）
function M.has_modifier(decl, word, src)
  for child in decl:iter_children() do
    if child:type() == "modifiers" then
      for m in child:iter_children() do
        if text(m, src) == word then return true end
      end
    end
  end
  return false
end

-- 解析整个文件：包名、import、类、字符串常量（static final String，接口里的字段默认就是常量）
local function analyze(src)
  local ok, parser = pcall(ts.get_string_parser, src, "java")
  if not ok then return nil end
  local tree = parser:parse()[1]
  local root = tree:root()
  local info = { src = src, root = root, tree = tree, parser = parser, imports = {}, static_imports = {}, consts = {}, classes = {} }
  local function walk_class(node, in_interface)
    local body = node:field("body")[1]
    if not body then return end
    local cname = node:field("name")[1]
    info.classes[#info.classes + 1] = { node = node, name = cname and text(cname, src) }
    for member in body:iter_children() do
      local t = member:type()
      if t == "field_declaration" or t == "constant_declaration" then
        local typ = member:field("type")[1]
        local is_const = in_interface or t == "constant_declaration"
          or (M.has_modifier(member, "static", src) and M.has_modifier(member, "final", src))
        if typ and text(typ, src):match("String$") and is_const then
          for d in member:iter_children() do
            if d:type() == "variable_declarator" then
              local n, v = d:field("name")[1], d:field("value")[1]
              if n and v then info.consts[text(n, src)] = v end
            end
          end
        end
      elseif t == "class_declaration" or t == "interface_declaration" then
        walk_class(member, t == "interface_declaration")
      end
    end
  end
  for child in root:iter_children() do
    local t = child:type()
    if t == "package_declaration" then
      for c in child:iter_children() do
        if c:named() and c:type() ~= "annotation" then info.package = text(c, src) end
      end
    elseif t == "import_declaration" then
      local s = text(child, src)
      local static, path = s:match("^import%s+(static%s+)(.-)%s*;"), nil
      path = s:match("^import%s+static%s+(.-)%s*;") or s:match("^import%s+(.-)%s*;")
      if path and not path:match("%*$") then
        local last = path:match("([%w_]+)$")
        if static then info.static_imports[last] = path:gsub("%.[%w_]+$", "") else info.imports[last] = path end
      end
    elseif t == "class_declaration" or t == "interface_declaration" then
      walk_class(child, t == "interface_declaration")
    end
  end
  return info
end

-- 按文件取解析结果（带缓存）
function M.file(path)
  local mt = U.mtime(path)
  local c = cache[path]
  local b = vim.fn.bufnr(path)
  local modified = b ~= -1 and vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified
  if c and c.mtime == mt and not modified then return c end
  local src = U.read(path)
  if not src then return nil end
  local info = analyze(src)
  if not info then return nil end
  info.mtime, info.path = mt, path
  if not modified then cache[path] = info end
  return info
end

-- 解析字符串表达式的值：字面量、常量（本类 / 其他类 / 静态导入，跨文件跨模块）、+ 拼接
-- ctx = { info = 当前文件, root = 项目根, deps = { 路径 = mtime }（记录用到的文件，用于判断缓存是否失效） }
-- 返回 字符串, 是否完全解析；解析不了的部分显示为 ${表达式}
local eval
local function const_in_file(path, name, ctx, depth)
  local info = M.file(path)
  if not info then return nil end
  local node = info.consts[name]
  if not node then return nil end
  if ctx.deps then ctx.deps[path] = info.mtime end
  return eval(node, vim.tbl_extend("force", ctx, { info = info }), depth + 1)
end

-- 在类里找常量：cls 是代码里写的类名（ApiConst、com.x.ApiConst、ApiConst.Inner）
local function class_const(cls, name, ctx, depth)
  local info = ctx.info
  local first = cls:match("^([%w_]+)")
  local candidates = {}
  for _, c in ipairs(info.classes) do
    if c.name == first or c.name == cls:match("([%w_]+)$") then
      local v, ok = const_in_file(info.path, name, ctx, depth)
      if v then return v, ok end
    end
  end
  if info.imports[first] then
    candidates = U.find_class(info.imports[first], ctx.root)
  elseif cls:match("^%l") and cls:find("%.") then
    -- 写的是全限定名 com.x.ApiConst
    candidates = U.find_class(cls, ctx.root)
  else
    if info.package then candidates = U.find_class(info.package .. "." .. first, ctx.root) end
  end
  -- 目录结构和包名对不上时，按类名找
  if #candidates == 0 then
    candidates = U.rg({ "--files", "-g", "**/" .. cls:match("^.-([%w_]+)$") .. ".java" }, ctx.root)
    if #candidates == 0 and first ~= cls then candidates = U.rg({ "--files", "-g", "**/" .. first .. ".java" }, ctx.root) end
  end
  for _, p in ipairs(candidates) do
    local v, ok = const_in_file(p, name, ctx, depth)
    if v then return v, ok end
  end
end

eval = function(node, ctx, depth)
  depth = depth or 0
  local src = ctx.info.src
  local raw = text(node, src)
  if depth > 20 then return "${" .. raw .. "}", false end
  local t = node:type()
  if t == "string_literal" then
    return unquote(raw), true
  elseif t == "parenthesized_expression" then
    for c in node:iter_children() do
      if c:named() then return eval(c, ctx, depth) end
    end
  elseif t == "binary_expression" then
    local l, r = node:field("left")[1], node:field("right")[1]
    local op = node:field("operator")[1]
    if l and r and (not op or text(op, src) == "+") then
      local a, oka = eval(l, ctx, depth)
      local b, okb = eval(r, ctx, depth)
      return a .. b, oka and okb
    end
  elseif t == "identifier" then
    local v, ok = const_in_file(ctx.info.path, raw, ctx, depth)
    if v then return v, ok end
    local cls = ctx.info.static_imports[raw]
    if cls then
      v, ok = class_const(cls, raw, ctx, depth)
      if v then return v, ok end
    end
    -- 父类 / 接口里继承来的常量、通配符静态导入：在项目里搜 String NAME = 的定义，唯一时采用
    local files = U.rg({ "-l", "-g", "*.java", "-e", "\\bString\\s+" .. raw .. "\\s*=", "." }, ctx.root)
    if #files == 1 then
      v, ok = const_in_file(files[1], raw, ctx, depth)
      if v then return v, ok end
    end
  elseif t == "field_access" then
    local obj, field = node:field("object")[1], node:field("field")[1]
    if obj and field then
      local v, ok = class_const(text(obj, src), text(field, src), ctx, depth)
      if v then return v, ok end
    end
  end
  return "${" .. raw .. "}", false
end
M.eval = eval

-- 数组 {"/a", "/b"} 返回多个值，单个值返回一个
function M.eval_list(node, ctx)
  if not node then return {} end
  if node:type() == "element_value_array_initializer" or node:type() == "array_initializer" then
    local res = {}
    for c in node:iter_children() do
      if c:named() and c:type() ~= "comment" then res[#res + 1] = (eval(c, ctx)) end
    end
    return res
  end
  return { (eval(node, ctx)) }
end

-- 字段访问 / 标识符的最后一段（RequestMethod.GET → GET）
function M.last_name(node, src)
  return text(node, src):match("([%w_]+)$")
end

M.text = text
return M
