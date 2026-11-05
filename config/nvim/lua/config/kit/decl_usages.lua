-- IDEA：光标已经在方法 / 类 / 字段 / 变量的声明名字上时，Ctrl+B 弹出用法列表（而不是"跳到自己"）
-- 用 treesitter 判断"是不是声明的名字"：同步、本地、不用等语言服务，比"问 LSP 定义位置是否等于光标"快且不会超时
local M = {}

-- 这些节点的 name 字段就是声明的名字
local decl_parents = {
  class_declaration = true,
  interface_declaration = true,
  enum_declaration = true,
  record_declaration = true,
  annotation_type_declaration = true,
  method_declaration = true,
  constructor_declaration = true,
  compact_constructor_declaration = true,
  variable_declarator = true, -- 字段、局部变量
  formal_parameter = true,
  spread_parameter = true,
  catch_formal_parameter = true,
  enum_constant = true,
  annotation_type_element_declaration = true,
}

-- buf 中 (row 0 基, col 0 基) 处是否是 Java 声明的名字
function M.is_declaration(buf, row, col)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  if vim.bo[buf].filetype ~= "java" then return false end
  local ok, node = pcall(vim.treesitter.get_node, { bufnr = buf, pos = { row, col }, ignore_injections = true })
  if not ok or not node then return false end
  local t = node:type()
  if t ~= "identifier" and t ~= "type_identifier" then return false end
  local parent = node:parent()
  if not parent or not decl_parents[parent:type()] then return false end
  -- spread_parameter（String... args）的名字在 variable_declarator 里，上面已覆盖
  local names = parent:field("name")
  return names[1] ~= nil and names[1]:id() == node:id()
end

-- 当前光标是否在声明名字上
function M.at_cursor()
  local pos = vim.api.nvim_win_get_cursor(0)
  return M.is_declaration(0, pos[1] - 1, pos[2])
end

-- 显示用法：优先用"查找用法"模块的弹框（另一个模块提供），没有时用 LSP 引用列表
function M.show_usages()
  local u = package.loaded["config.kit.usages"]
  if type(u) == "table" and type(u.show_popup) == "function" then
    u.show_popup()
  else
    Snacks.picker.lsp_references()
  end
end

-- 优先级 80：MyBatis、配置项等更具体的提供者先处理
require("config.kit.goto").register("在声明处显示用法", function()
  if not M.at_cursor() then return false end
  M.show_usages()
  return true
end, 80)

return M
