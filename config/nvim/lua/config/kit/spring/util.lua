-- spring / mybatis / config_keys 共用的小工具：项目根目录、ripgrep、读文件、跳转、结果列表
-- 这几个功能都只做文本解析（ripgrep + treesitter），不依赖 jdtls：大项目还没导入完也能用
local M = {}

-- 构建产物、依赖目录里的文件不是源码，搜出来只会干扰
M.excludes = { "-g", "!**/target/**", "-g", "!**/build/**", "-g", "!**/node_modules/**", "-g", "!**/.git/**" }

-- 项目根目录：当前文件在工作目录下时用工作目录（用户一般在项目根目录打开 nvim，多模块项目要搜全部模块）；
-- 否则用 LazyVim 判断的根目录
function M.root(buf)
  local cwd = vim.fn.getcwd()
  local name = vim.api.nvim_buf_get_name(buf or 0)
  if name == "" or vim.startswith(name, cwd .. "/") then return cwd end
  local ok, r = pcall(function() return LazyVim.root({ buf = buf }) end)
  return ok and r or cwd
end

-- 同步执行 ripgrep，返回输出行（rg 很快，几千个文件的项目也只要几十毫秒）
function M.rg(args, cwd)
  local cmd = { "rg", "--no-messages", "--color=never" }
  vim.list_extend(cmd, M.excludes)
  vim.list_extend(cmd, args)
  local ok, res = pcall(function() return vim.system(cmd, { cwd = cwd, text = true }):wait(10000) end)
  if not ok or not res or not res.stdout then return {} end
  local lines = vim.split(res.stdout, "\n", { trimempty = true })
  for i, l in ipairs(lines) do
    if not l:match("^/") then lines[i] = (cwd or vim.fn.getcwd()) .. "/" .. l:gsub("^%./", "") end
  end
  return lines
end

-- 带行号的搜索：返回 { { file, lnum, col, text } }
function M.rg_lines(pattern, globs, cwd, extra)
  local args = { "--line-number", "--column", "--no-heading", "--with-filename" }
  for _, g in ipairs(globs or {}) do vim.list_extend(args, { "-g", g }) end
  vim.list_extend(args, extra or {})
  vim.list_extend(args, { "-e", pattern, "." })
  local res = {}
  for _, l in ipairs(M.rg(args, cwd)) do
    local f, ln, col, text = l:match("^(.-):(%d+):(%d+):(.*)$")
    if f then res[#res + 1] = { file = f, lnum = tonumber(ln), col = tonumber(col), text = text } end
  end
  return res
end

-- 读文件内容：已在编辑器里打开的用缓冲区内容（含未保存的修改），否则读磁盘
function M.read(path)
  local b = vim.fn.bufnr(path)
  if b ~= -1 and vim.api.nvim_buf_is_loaded(b) then
    return table.concat(vim.api.nvim_buf_get_lines(b, 0, -1, false), "\n")
  end
  local f = io.open(path, "r")
  if not f then return nil end
  local s = f:read("*a")
  f:close()
  return s
end

function M.lines(path)
  local s = M.read(path)
  return s and vim.split(s, "\n", { plain = true }) or {}
end

function M.mtime(path)
  local st = vim.uv.fs_stat(path)
  return st and (st.mtime.sec * 1e9 + st.mtime.nsec) or 0
end

-- 所属模块：离文件最近的 pom.xml / build.gradle 所在目录名
local module_cache = {}
function M.module_of(path)
  local dir = vim.fs.dirname(path)
  if module_cache[dir] ~= nil then return module_cache[dir] end
  local found = vim.fs.find({ "pom.xml", "build.gradle", "build.gradle.kts" }, { upward = true, path = dir, limit = 1 })[1]
  local name = found and vim.fs.basename(vim.fs.dirname(found)) or ""
  module_cache[dir] = name
  return name
end

-- 按全限定类名找源码文件（多模块项目里可能在任何模块）
function M.find_class(fqn, root)
  local rel = fqn:gsub("%$.*$", ""):gsub("%.", "/") .. ".java"
  return M.rg({ "--files", "-g", "**/" .. rel }, root)
end

-- 跳转到文件的某行某列（1 基行号、0 基列），记录到跳转历史，Ctrl+Alt+← 可以回来
function M.jump(path, lnum, col)
  vim.cmd("normal! m'")
  if vim.fs.normalize(vim.api.nvim_buf_get_name(0)) ~= vim.fs.normalize(path) then
    vim.cmd("edit " .. vim.fn.fnameescape(path))
  end
  local last = vim.api.nvim_buf_line_count(0)
  pcall(vim.api.nvim_win_set_cursor, 0, { math.min(lnum, last), col or 0 })
  vim.cmd("normal! zz")
end

-- 一个结果直接跳，多个弹出列表（带代码预览）
-- items: { { file, lnum, col, label(显示的文字), detail(右侧灰色说明) } }
function M.pick(title, items)
  if #items == 0 then return false end
  if #items == 1 then
    M.jump(items[1].file, items[1].lnum, items[1].col or 0)
    return true
  end
  local list = {}
  for i, it in ipairs(items) do
    list[i] = {
      idx = i,
      file = it.file,
      pos = { it.lnum, it.col or 0 },
      text = (it.label or "") .. " " .. (it.detail or "") .. " " .. vim.fn.fnamemodify(it.file, ":t"),
      label = it.label,
      detail = it.detail,
    }
  end
  Snacks.picker.pick({
    title = title,
    items = list,
    format = function(item)
      local rel = vim.fn.fnamemodify(item.file, ":~:.")
      return {
        { item.label or "", "SnacksPickerLabel" },
        { "  " },
        { item.detail or "", "Comment" },
        { "  " },
        { rel .. ":" .. item.pos[1], "SnacksPickerDir" },
      }
    end,
    preview = "file",
    confirm = function(picker, item)
      picker:close()
      if item then M.jump(item.file, item.pos[1], item.pos[2]) end
    end,
  })
  return true
end

-- 光标所在单词的属性：line 中包含 col（0 基）的 name="value"，返回 name, value, value 起始列（0 基）
function M.attr_at(line, col)
  local init = 1
  while true do
    local s, e, name, q, value = line:find("([%w_:%-]+)%s*=%s*([\"'])(.-)%2", init)
    if not s then return nil end
    if col + 1 >= s and col + 1 <= e then
      local vstart = e - #value - 1 -- 引号前一个位置（1 基）= 值的起点 - 1
      return name, value, vstart, q
    end
    init = e + 1
  end
end

return M
