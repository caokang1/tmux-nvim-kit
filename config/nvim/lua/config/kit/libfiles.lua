-- 依赖库 / 反编译文件（IDEA：External Libraries 里的 .class 文件）
-- 在 jar 里的类上 Ctrl+B 会打开 jdt://contents/... 缓冲区，名字是一长串 URI。这里让它像 IDEA 一样：
--   * 标签栏显示 ArrayList.class（有源码时 ArrayList.java），状态栏 / 窗口顶部显示所属 jar 和包名
--   * Alt+F1（在文件树中定位）提示"依赖库文件，不在项目文件中"，而不是报错
--   * Ctrl+E 最近的文件里也列出看过的依赖库类，显示类名而不是 URI
local K = require("config.idea_keys")
local M = {}

local function decode(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

function M.is_lib(name)
  return type(name) == "string" and name:find("^jdt://") ~= nil
end

-- 解析 jdt:// URI，返回 { kind = "class"|"entry", jar, jdk, pkg, class, inner, name } 或 nil。见过的形式：
--   jdt://contents/spring-beans-5.3.13.jar/org.springframework.beans.factory.annotation/Autowired.java?=demo-app/...
--   jdt://contents/java.base/java.util/ArrayList.java?=...jrt-fs.jar`java.base=...%3Cjava.util%28ArrayList.class   （JDK 模块）
--   jdt://contents/rt.jar/java.util/ArrayList.class?=...      （旧版 jdtls / JDK 8）
--   jdt://contents/foo.jar/(default package)/Foo.class?=...   （默认包）
--   jdt://jarentry/META-INF/spring.factories?=...spring-boot-2.4.13.jar...   （jar 里的非 class 文件）
local cache = {}
function M.parse(uri)
  if not M.is_lib(uri) then return nil end
  if cache[uri] then return cache[uri] end
  local path, query = uri:match("^jdt://([^?]*)%??(.*)$")
  path, query = decode(path or ""), decode(query or "")
  local kind, rest = path:match("^([^/]+)/(.*)$")
  local info
  if kind == "contents" then
    local jar, pkg, file = rest:match("^([^/]+)/(.*)/([^/]+)$")
    if not jar then
      jar, file = rest:match("^([^/]+)/([^/]+)$")
      pkg = ""
    end
    if not jar then return nil end
    if pkg:find("default package", 1, true) then pkg = "" end
    local class = file:gsub("%.%w+$", "")
    -- 句柄末尾 "(类名.class"：内部类是 "Outer$Inner.class"
    local inner = query:match("%(([^(]+)%.class$")
    info = { kind = "class", jar = jar, pkg = pkg:gsub("/", "."), class = class, inner = inner }
  elseif kind == "jarentry" then
    info = { kind = "entry", pkg = "", class = vim.fs.basename(rest), path = rest }
    -- jar 名在句柄里：...\/spring-boot-2.4.13.jar...
    for j in query:gmatch("([^/\\=`<]+%.jar)") do info.jar = j end
  else
    return nil
  end
  -- JDK 类的"jar"是模块名（java.base），句柄里带 jrt-fs.jar
  info.jdk = info.jar and not info.jar:find("%.jar$") and query:find("jrt%-fs%.jar") ~= nil or false
  if info.jar == nil then info.jar = "?" end
  cache[uri] = info
  return info
end

-- "spring-beans-5.3.13.jar" / "JDK java.base"
function M.jar_label(info)
  return info.jdk and ("JDK " .. info.jar) or info.jar
end

-- 反编译出来的（没有源码）还是附带了源码：看缓冲区开头 jdtls 写的提示
local function decompiled(buf)
  if not (buf and vim.api.nvim_buf_is_loaded(buf)) then return nil end
  if vim.b[buf].kit_lib_decompiled ~= nil then return vim.b[buf].kit_lib_decompiled end
  if vim.api.nvim_buf_line_count(buf) < 2 then return nil end -- 内容还没加载出来，先不缓存
  local head = table.concat(vim.api.nvim_buf_get_lines(buf, 0, 5, false), "\n"):lower()
  local v = head:find("decompiled") ~= nil or head:find("disassembler") ~= nil or head:find("failed to get sources") ~= nil
  vim.b[buf].kit_lib_decompiled = v
  return v
end

-- 标签名：ArrayList.class / Autowired.java / spring.factories
function M.display_name(uri, buf)
  local info = M.parse(uri)
  if not info then return nil end
  if info.kind == "entry" then return info.class end
  local d = decompiled(buf)
  return info.class .. ((d == false) and ".java" or ".class")
end

local function buf_name(buf)
  buf = (buf == nil or buf == 0) and vim.api.nvim_get_current_buf() or buf
  return vim.api.nvim_buf_get_name(buf), buf
end

-- 状态栏：spring-beans-5.3.13.jar › Autowired.java
function M.statusline(buf)
  local name, b = buf_name(buf)
  local info = M.parse(name)
  if not info then return nil end
  return M.jar_label(info) .. " › " .. M.display_name(name, b)
end

-- 窗口顶部：󰏗 spring-beans-5.3.13.jar › org.springframework.beans.factory.annotation › Autowired.java  依赖库（只读）
function M.winbar(buf)
  local name, b = buf_name(buf)
  local info = M.parse(name)
  if not info then return nil end
  local parts = { M.jar_label(info) }
  if info.pkg ~= "" then parts[#parts + 1] = info.pkg end
  parts[#parts + 1] = M.display_name(name, b)
  local esc = function(s) return (s:gsub("%%", "%%%%")) end
  return "%#Directory# 󰏗 " .. esc(table.concat(parts, " › ")) .. "%#Comment#  " .. (info.jdk and "JDK" or "依赖库") .. "（只读）"
end

-- 只给显示依赖库文件的窗口设置 winbar；窗口换成普通文件时还原
local function update_winbar(win)
  if not vim.api.nvim_win_is_valid(win) then return end
  local buf = vim.api.nvim_win_get_buf(win)
  if M.is_lib(vim.api.nvim_buf_get_name(buf)) then
    vim.wo[win].winbar = "%{%v:lua.require'config.kit.libfiles'.winbar(" .. buf .. ")%}"
    vim.w[win].kit_lib_winbar = true
  elseif vim.w[win].kit_lib_winbar then
    vim.wo[win].winbar = ""
    vim.w[win].kit_lib_winbar = nil
  end
end

local group = vim.api.nvim_create_augroup("kit_libfiles", { clear = true })
vim.api.nvim_create_autocmd({ "BufWinEnter", "BufEnter" }, {
  group = group,
  callback = function() update_winbar(vim.api.nvim_get_current_win()) end,
})
-- jdtls 把内容写进缓冲区之后再判断一次是不是反编译的，让标签名刷新
vim.api.nvim_create_autocmd({ "BufReadCmd" }, {
  group = group,
  pattern = "jdt://*",
  callback = function(ev)
    vim.defer_fn(function()
      if vim.api.nvim_buf_is_valid(ev.buf) then
        vim.b[ev.buf].kit_lib_decompiled = nil
        decompiled(ev.buf)
        pcall(vim.cmd.redrawtabline)
      end
    end, 200)
  end,
})

-- Alt+F1：依赖库文件不在文件树里，给出说明
function M.reveal()
  local name = vim.api.nvim_buf_get_name(0)
  local info = M.parse(name)
  if info then
    vim.notify(("%s文件（%s），不在项目文件中"):format(info.jdk and "JDK " or "依赖库", info.jar), vim.log.levels.INFO,
      { title = "在文件树中定位" })
    return
  end
  if name == "" or vim.bo.buftype ~= "" then
    vim.notify("当前窗口不是项目里的文件", vim.log.levels.INFO, { title = "在文件树中定位" })
    return
  end
  Snacks.explorer.reveal()
end
K.map(K.NI, "<M-F1>", K.n(M.reveal), "在文件树中定位当前文件")

-- ================= Ctrl+E 最近的文件 =================
-- 和原来一样只列当前项目（cwd）里的文件，另外加上看过的依赖库类（jdtls 在运行时才列，否则打不开）
function M.recent_items(opts)
  opts = opts or {}
  local cwd = vim.fs.normalize(opts.cwd or vim.fn.getcwd())
  local current = vim.api.nvim_buf_get_name(0)
  local has_jdtls = #vim.lsp.get_clients({ name = "jdtls" }) > 0
  local skip = {}
  for _, d in ipairs({ "data", "cache", "state" }) do skip[#skip + 1] = vim.fs.normalize(vim.fn.stdpath(d)) .. "/" end
  local names = {}
  -- 先是已打开的缓冲区（按最近使用排序），再是历史记录
  local bufs = vim.tbl_filter(function(b)
    local n = vim.api.nvim_buf_get_name(b)
    return n ~= "" and vim.bo[b].buflisted and (vim.bo[b].buftype == "" or M.is_lib(n))
  end, vim.api.nvim_list_bufs())
  table.sort(bufs, function(a, b) return vim.fn.getbufinfo(a)[1].lastused > vim.fn.getbufinfo(b)[1].lastused end)
  for _, b in ipairs(bufs) do names[#names + 1] = vim.api.nvim_buf_get_name(b) end
  vim.list_extend(names, vim.v.oldfiles)

  local items, done = {}, {}
  for _, f in ipairs(names) do
    if f:find("^file://") then f = vim.uri_to_fname(f) end
    if not done[f] and f ~= current then
      done[f] = true
      local info = M.parse(f)
      if info then
        if has_jdtls and info.kind == "class" then
          local b = vim.fn.bufnr(f)
          local display = M.display_name(f, b > 0 and b or nil)
          items[#items + 1] = {
            file = f, lib = info, display = display,
            buf = b > 0 and b or nil,
            text = display .. " " .. info.pkg .. " " .. info.jar,
            preview_title = display .. " — " .. M.jar_label(info),
          }
        end
      elseif not f:find("^%a[%w+.-]*://") then
        local p = vim.fs.normalize(f)
        local ok = p:sub(1, #cwd + 1) == cwd .. "/"
        for _, s in ipairs(skip) do
          if p:sub(1, #s) == s then ok = false end
        end
        if ok and vim.uv.fs_stat(p) then items[#items + 1] = { file = p, text = p } end
      end
    end
    if opts.limit and #items >= opts.limit then break end
  end
  return items
end

-- 依赖库条目：类名 + jar + 包名；普通文件沿用 snacks 的文件格式
function M.format_item(item, picker)
  if item.lib then
    local ret = {
      { LazyVim.config.icons.kinds.Class or "󰠱 ", "SnacksPickerIcon" },
      { item.display, "SnacksPickerFile" },
      { "  " },
      { M.jar_label(item.lib), "SnacksPickerComment" },
    }
    if item.lib.pkg ~= "" then ret[#ret + 1] = { "  " .. item.lib.pkg, "SnacksPickerDir" } end
    return ret
  end
  return require("snacks.picker.format").file(item, picker)
end

-- 打开依赖库条目：缓冲区没加载时用 bufadd 打开（snacks 会把 jdt:// 当成相对路径处理）
local function lib_buf(item)
  if item.lib and not (item.buf and vim.api.nvim_buf_is_valid(item.buf)) then item.buf = vim.fn.bufadd(item.file) end
  return item
end

function M.recent()
  Snacks.picker.pick({
    title = "最近的文件（当前项目）",
    finder = function()
      return vim.tbl_map(lib_buf, M.recent_items())
    end,
    format = M.format_item,
    preview = "file",
  })
end
K.map(K.NI, "<C-e>", K.n(M.recent), "最近的文件（当前项目，含看过的依赖库类）")

return M
