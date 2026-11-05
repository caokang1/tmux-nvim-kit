-- 复制引用（IDEA: Copy Reference，Ctrl+Alt+Shift+C；备用 空格 c y）
-- 弹出选择：相对路径:行号 / 绝对路径:行号 / 全限定名#成员（Java）/ 文件名，复制到 + 寄存器。
-- + 寄存器走 OSC 52（见 options.lua），Windows Terminal 和浏览器里都会进入本机剪贴板，
-- 可以直接粘贴给右侧的 Claude Code 或发给同事。
local K = require("config.idea_keys")
local M = {}

-- 能当作"外层类"的声明：内部类的全限定名是 外层.内部（IDEA 的格式）
local TYPE_DECL = {
  class_declaration = true,
  interface_declaration = true,
  enum_declaration = true,
  record_declaration = true,
  annotation_type_declaration = true,
}

local function text(node, buf)
  return node and vim.treesitter.get_node_text(node, buf) or nil
end

-- 字段可能一行声明多个（int a, b;），取光标所在的那个，取不到就取第一个
local function field_name(node, buf, row, col)
  local first
  for child in node:iter_children() do
    if child:type() == "variable_declarator" then
      local name = child:field("name")[1]
      first = first or name
      local sr, sc, er, ec = child:range()
      if (row > sr or (row == sr and col >= sc)) and (row < er or (row == er and col <= ec)) then
        return text(name, buf)
      end
    end
  end
  return text(first, buf)
end

--- Java 光标处的全限定引用：com.x.Outer.Inner#member；只在类上（或类体空白处）时只给类名。
--- 不依赖 jdtls（jdt:// 反编译的文件、jdtls 还没启动时都能用），只用 treesitter 解析当前缓冲区。
---@param buf? integer
---@param row? integer 0 基行号，默认光标行
---@param col? integer 0 基列号，默认光标列（在行首空白里时改用第一个非空字符）
---@return string? fqn, string? class_fqn
function M.java_reference(buf, row, col)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if row == nil then
    local cur = vim.api.nvim_win_get_cursor(0)
    row, col = cur[1] - 1, cur[2]
  end
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local indent = #(line:match("^%s*"))
  col = math.max(col or 0, indent)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "java")
  if not ok or not parser then return nil end
  local tree = parser:parse()[1]
  if not tree then return nil end
  local root = tree:root()

  local pkg
  for child in root:iter_children() do
    if child:type() == "package_declaration" then
      for c in child:iter_children() do
        if c:type() == "scoped_identifier" or c:type() == "identifier" then pkg = text(c, buf) end
      end
    end
  end

  local node = root:named_descendant_for_range(row, col, row, col)
  local member, classes = nil, {}
  while node do
    local t = node:type()
    if not member and not next(classes) then
      if t == "method_declaration" or t == "constructor_declaration" or t == "compact_constructor_declaration" then
        member = text(node:field("name")[1], buf)
      elseif t == "field_declaration" or t == "constant_declaration" then
        member = field_name(node, buf, row, col)
      elseif t == "enum_constant" then
        member = text(node:field("name")[1], buf)
      end
    end
    if TYPE_DECL[t] then
      local name = text(node:field("name")[1], buf)
      if name then table.insert(classes, 1, name) end
    end
    node = node:parent()
  end

  -- 光标在类外（package / import 行）：用文件里第一个顶层类型
  if #classes == 0 then
    for child in root:iter_children() do
      if TYPE_DECL[child:type()] then
        classes[1] = text(child:field("name")[1], buf)
        break
      end
    end
    member = nil
  end
  if #classes == 0 then return nil end
  local cls = (pkg and pkg ~= "" and (pkg .. ".") or "") .. table.concat(classes, ".")
  return member and (cls .. "#" .. member) or cls, cls
end

--- 生成可复制的候选项
---@param opts? {buf?: integer, line1?: integer, line2?: integer, row?: integer, col?: integer}
---@return {label: string, value: string}[]
function M.candidates(opts)
  opts = opts or {}
  local buf = opts.buf or vim.api.nvim_get_current_buf()
  local name = vim.api.nvim_buf_get_name(buf)
  local l1 = opts.line1 or vim.api.nvim_win_get_cursor(0)[1]
  local l2 = opts.line2 or l1
  if l2 < l1 then l1, l2 = l2, l1 end
  local lines = l1 == l2 and tostring(l1) or (l1 .. "-" .. l2)
  local items = {}
  local function add(label, value)
    for _, it in ipairs(items) do
      if it.value == value then return end
    end
    items[#items + 1] = { label = label, value = value }
  end

  local is_java = vim.bo[buf].filetype == "java" or name:match("%.java$") or name:match("^jdt://")
  local fqn, cls
  if is_java then
    fqn, cls = M.java_reference(buf, opts.row or (l1 - 1), opts.col)
  end

  if name:match("^jdt://") then
    -- 依赖库里的类：路径没有意义，只给全限定名
    if fqn then add("全限定名", fqn) end
    if cls then add("类全限定名", cls) end
    return items
  end
  if name == "" then return items end

  local rel = vim.fn.fnamemodify(name, ":.")
  local abs = vim.fn.fnamemodify(name, ":p")
  add("相对路径:行号", rel .. ":" .. lines)
  if fqn then add("全限定名", fqn) end
  add("绝对路径:行号", abs .. ":" .. lines)
  add("文件名", vim.fn.fnamemodify(name, ":t"))
  return items
end

function M.copy(value)
  vim.fn.setreg("+", value)
  vim.fn.setreg('"', value) -- 编辑器里 Ctrl+V 也能粘贴
  vim.notify("已复制：" .. value, vim.log.levels.INFO, { title = "复制引用" })
end

--- 弹出选择并复制；可视模式时行号为 起-止
function M.pick()
  local opts = {}
  local mode = vim.fn.mode()
  if mode:match("[vV\22]") then
    opts.line1, opts.line2 = vim.fn.line("v"), vim.fn.line(".")
    vim.cmd("normal! \27") -- 退出可视模式
  end
  local items = M.candidates(opts)
  if #items == 0 then
    vim.notify("当前缓冲区没有文件，无法复制引用", vim.log.levels.WARN)
    return
  end
  local width = 0
  for _, it in ipairs(items) do width = math.max(width, vim.fn.strdisplaywidth(it.label)) end
  vim.ui.select(items, {
    prompt = "复制引用",
    format_item = function(it)
      return it.label .. string.rep(" ", width - vim.fn.strdisplaywidth(it.label) + 2) .. it.value
    end,
  }, function(choice)
    if choice then M.copy(choice.value) end
  end)
end

-- 普通 / 输入 / 可视模式都可用；可视模式下要在选区还在时读取起止行，所以不用 K.n 包装
local function run()
  if vim.fn.mode() == "i" then
    vim.cmd("stopinsert")
    vim.schedule(M.pick)
  else
    M.pick()
  end
end
for _, lhs in ipairs({ "<C-M-S-c>", "<C-M-C>" }) do
  K.map(K.NIX, lhs, run, "复制引用（路径:行号 / 全限定名）")
end
K.map(K.NX, "<leader>cy", run, "复制引用（路径:行号 / 全限定名）")


return M
