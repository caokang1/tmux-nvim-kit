-- 在文件中查找 / 替换的范围（IDEA: Find in Files 的 Scope）
-- Ctrl+Shift+F 弹框（复制自 idea_keys.lua 的 find_in_files 并扩展，这里重新映射同样的键覆盖原映射）：
--   Alt+S 循环切换范围：整个项目 → 当前模块（离当前文件最近的 pom.xml / build.gradle 所在目录）
--         → 当前目录 → 自选目录（弹出目录列表）
--   Alt+T 排除 / 包含测试代码（src/test/**）
--   Alt+C 区分大小写、Alt+W 整词、Alt+X 正则；输入框里写 "关键字 -- -g *.java" 限定文件类型（同原来）
-- 始终排除 target/、build/、node_modules/、.git/（编译输出和依赖，搜代码时只会制造重复结果）。
-- 当前范围显示在标题里，如：在文件中查找 [模块 demo-app] [排除测试]
-- 上一次选的范围会被记住（IDEA 也是），Ctrl+Shift+R（全局替换）打开时也按这个范围预填 grug-far 的路径。
local K = require("config.idea_keys")
local M = {}

M.ORDER = { "project", "module", "dir", "custom" }
M.LABEL = { project = "整个项目", module = "模块", dir = "目录", custom = "目录" }
M.EXCLUDE = { "target/", "build/", "node_modules/", ".git/", "*.min.js", "*.min.css", "*.map" }
M.TEST_GLOB = "**/src/test/**"
M.MODULE_MARKERS = { "pom.xml", "build.gradle", "build.gradle.kts" }

-- 记住上次的选择（同一个 Neovim 里）
M.state = { scope = "project", exclude_tests = false, custom = nil }

--- 当前模块：从文件所在目录往上找最近的 pom.xml（多模块项目里就是子模块），找不到返回 nil
---@param file string
---@param root? string 不超出项目根目录
function M.module_root(file, root)
  if not file or file == "" then return nil end
  local dir = vim.fn.isdirectory(file) == 1 and file or vim.fs.dirname(file)
  local found = vim.fs.root(dir, M.MODULE_MARKERS)
  if not found then return nil end
  found = vim.fs.normalize(found)
  if root and root ~= "" then
    root = vim.fs.normalize(root)
    if found ~= root and found:find(root .. "/", 1, true) ~= 1 then return nil end
  end
  return found
end

--- 各范围对应的目录
---@param file string 当前文件（可为空）
---@param root string 项目根目录
---@return table<string, string?>
function M.scope_dirs(file, root, custom)
  root = vim.fs.normalize(root)
  local real = file and file ~= "" and vim.uv.fs_stat(file) and file or nil
  local dir = real and vim.fs.normalize(vim.fs.dirname(real)) or nil
  return {
    project = root,
    module = real and M.module_root(real, root) or nil,
    dir = dir,
    custom = custom,
  }
end

local function rel(path, root)
  if path == root then return "." end
  if path:find(root .. "/", 1, true) == 1 then return path:sub(#root + 2) end
  return vim.fn.fnamemodify(path, ":~")
end

--- 根据状态算出 grep 参数：cwd（搜索的目录）、exclude（rg 的 -g !xxx）、标题
---@param st {scope: string, exclude_tests?: boolean, custom?: string}
---@param dirs table<string, string?> M.scope_dirs 的结果
---@return {cwd: string, exclude: string[], title: string, scope: string}
function M.resolve(st, dirs)
  local scope = st.scope
  if not dirs[scope] then scope = "project" end -- 没有模块 / 没有当前文件时退回整个项目
  local cwd = dirs[scope]
  local exclude = vim.deepcopy(M.EXCLUDE)
  if st.exclude_tests then exclude[#exclude + 1] = M.TEST_GLOB end
  local title = "在文件中查找"
  if scope == "module" then
    title = title .. " [模块 " .. vim.fs.basename(cwd) .. "]"
  elseif scope ~= "project" then
    title = title .. " [目录 " .. rel(cwd, dirs.project) .. "]"
  end
  if st.exclude_tests then title = title .. " [排除测试]" end
  return { cwd = cwd, exclude = exclude, title = title, scope = scope }
end

-- 范围是否可用：没有模块 / 没有当前文件时不可用；和更大的范围是同一个目录时（单模块项目、
-- 文件就在模块根目录）也跳过，免得按了 Alt+S 没有变化
local function available(s, dirs)
  if s == "project" or s == "custom" then return true end
  local d = dirs[s]
  if not d or d == dirs.project then return false end
  return not (s == "dir" and d == dirs.module)
end

--- 下一个范围
function M.next_scope(scope, dirs)
  local idx = 1
  for i, s in ipairs(M.ORDER) do
    if s == scope then idx = i end
  end
  for step = 1, #M.ORDER do
    local s = M.ORDER[(idx - 1 + step) % #M.ORDER + 1]
    if available(s, dirs) then return s end
  end
  return "project"
end

local function rg_args(o)
  local a = { o.case and "--case-sensitive" or "--ignore-case" }
  if o.word then a[#a + 1] = "--word-regexp" end
  return a
end

-- 弹出目录列表让用户选（fd 列目录，已排除编译输出等），选中后 cb(绝对路径)，取消 cb(nil)
function M.pick_dir(root, cb)
  local fd = require("snacks.picker.source.files").get_fd() or "fd"
  local chosen = false
  Snacks.picker.pick({
    title = "选择查找范围（目录）",
    cwd = root,
    layout = { preset = "select" },
    format = "file",
    finder = function(opts, ctx)
      return require("snacks.picker.source.proc").proc(ctx:opts({
        cmd = fd,
        args = { "--type", "d", "--color", "never", "--hidden", "-E", ".git", "-E", "target", "-E", "node_modules", "-E", "build" },
        cwd = root,
        transform = function(item)
          item.file = item.text:gsub("^%./", ""):gsub("/$", "")
          item.text = item.file
          item.dir = true
          item.cwd = root
        end,
      }), ctx)
    end,
    confirm = function(picker, item)
      chosen = true
      picker:close()
      if item then
        vim.schedule(function() cb(vim.fs.normalize(root .. "/" .. item.file)) end)
      else
        vim.schedule(function() cb(nil) end)
      end
    end,
    on_close = function()
      if not chosen then vim.schedule(function() cb(nil) end) end
    end,
  })
end

--- 打开查找弹框
---@param search? string 预填的文字（选中内容）
---@param ctx? {file?: string, root?: string}
function M.find_in_files(search, ctx)
  ctx = ctx or {}
  local file = ctx.file or vim.api.nvim_buf_get_name(0)
  local root = ctx.root or LazyVim.root()
  local st = M.state
  local dirs = M.scope_dirs(file, root, st.custom)
  local r = M.resolve(st, dirs)

  local function reconfigure(picker)
    r = M.resolve(st, dirs)
    picker:set_cwd(r.cwd)
    picker.opts.exclude = r.exclude
    picker.title = r.title
    picker:update_titles()
    picker.list:set_target()
    picker:find()
  end
  local function flip(name)
    return function(picker)
      picker.opts[name] = not picker.opts[name]
      picker.opts.args = rg_args(picker.opts)
      picker.list:set_target()
      picker:find()
    end
  end
  local both = { "i", "n" }
  return Snacks.picker.grep({
    title = r.title,
    cwd = r.cwd,
    search = search,
    regex = false,
    case = false,
    word = false,
    args = rg_args({}),
    layout = { preset = "vertical" },
    -- 边输入边搜时最多取 1000 条（IDEA 的弹框也只显示前 100 多条），输入第一个字时不必处理几十万条结果；
    -- 压缩过的 js/css 一行几十万字符，搜代码时用不到
    limit_live = 1000,
    exclude = r.exclude,
    toggles = {
      case = { icon = "Aa", value = true },
      word = { icon = "W", value = true },
      regex = { icon = ".*", value = true },
    },
    actions = {
      idea_case = flip("case"),
      idea_word = flip("word"),
      idea_scope = function(picker)
        local nxt = M.next_scope(r.scope, dirs)
        if nxt ~= "custom" then
          st.scope = nxt
          return reconfigure(picker)
        end
        -- 自选目录：先关掉查找框选目录，选好后带着原来的输入重新打开；取消则回到整个项目
        local text = picker.input:get()
        picker:close()
        M.pick_dir(dirs.project, function(dir)
          if dir then
            st.scope, st.custom = "custom", dir
          else
            st.scope = "project"
          end
          M.find_in_files(text, { file = file, root = root })
        end)
      end,
      idea_tests = function(picker)
        st.exclude_tests = not st.exclude_tests
        reconfigure(picker)
      end,
    },
    win = {
      input = {
        keys = {
          ["<a-c>"] = { "idea_case", mode = both, desc = "区分大小写" },
          ["<a-w>"] = { "idea_word", mode = both, desc = "整词匹配" },
          ["<a-x>"] = { "toggle_regex", mode = both, desc = "正则" },
          ["<a-s>"] = { "idea_scope", mode = both, desc = "切换范围：项目 / 模块 / 目录 / 自选目录" },
          ["<a-t>"] = { "idea_tests", mode = both, desc = "排除 / 包含测试代码" },
        },
      },
    },
  })
end

--- 全局替换（grug-far）按当前范围预填路径和排除测试
function M.replace_prefills(file, root)
  local dirs = M.scope_dirs(file, root, M.state.custom)
  local r = M.resolve(M.state, dirs)
  local p = {}
  if r.scope ~= "project" then p.paths = r.cwd end
  if M.state.exclude_tests then p.filesFilter = "!" .. M.TEST_GLOB end
  return p
end

local function replace_all()
  local prefills = M.replace_prefills(vim.api.nvim_buf_get_name(0), LazyVim.root())
  if vim.fn.mode():match("[vV\22]") then
    require("grug-far").with_visual_selection({ prefills = prefills })
  else
    vim.cmd("stopinsert")
    prefills.search = vim.fn.expand("<cword>")
    require("grug-far").open({ prefills = prefills })
  end
end

for _, lhs in ipairs({ "<M-F>", "<C-S-F>" }) do
  K.map(K.NI, lhs, K.n(function() M.find_in_files() end), "在所有文件中查找（Alt+S 范围，Alt+T 排除测试）")
  K.map("x", lhs, function()
    local t = require("config.find_bar").selection()
    vim.schedule(function() M.find_in_files(t) end)
  end, "在所有文件中查找选中内容")
end
for _, lhs in ipairs({ "<M-R>", "<C-S-R>" }) do
  K.map(K.NIX, lhs, replace_all, "在所有文件中替换（按查找的范围预填路径）")
end

return M
