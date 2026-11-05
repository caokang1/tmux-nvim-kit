-- Markdown 阅读（IDEA 打开 .md 时的预览体验）：
--   * Ctrl+B / Ctrl+点击 / 回车：打开光标下的链接——相对路径文件、#锚点、文件.md#锚点、http(s) 网址（用 Windows 浏览器）、
--     引用式链接 [文本][ref]、<网址>
--   * Ctrl+F12 / Alt+7：标题大纲，可输入过滤、回车跳转
-- 链接解析和锚点计算都是纯文本处理，不依赖语言服务，打开文件不会变慢
local K = require("config.idea_keys")
local M = {}

-- ================= 锚点（GitHub 规则） =================
-- GitHub 生成锚点：转小写、去掉标点符号（保留字母/数字/下划线/连字符，中文等文字保留）、空格变成 -
-- Lua 没有 Unicode 字符类，非 ASCII 字符里只去掉常见的标点 / 符号区段（中文标点、全角标点、表情等）
local function is_unicode_punct(cp)
  return (cp >= 0x00A0 and cp <= 0x00BF) or cp == 0x00D7 or cp == 0x00F7
    or (cp >= 0x2000 and cp <= 0x206F) -- 通用标点：— “ ” … 等
    or (cp >= 0x20A0 and cp <= 0x2BFF) -- 货币、箭头、数学符号、制表符、几何图形、杂项符号
    or (cp >= 0x3000 and cp <= 0x303F) -- 中文标点：、。「」【】等
    or (cp >= 0xFE10 and cp <= 0xFE6F) -- 竖排 / 小写标点
    or (cp >= 0xFF00 and cp <= 0xFF0F) or (cp >= 0xFF1A and cp <= 0xFF20) -- 全角标点：！（），：？等
    or (cp >= 0xFF3B and cp <= 0xFF40) or (cp >= 0xFF5B and cp <= 0xFF65)
    or cp >= 0x1F000 -- 表情符号
end

-- Neovim 的 LuaJIT 没有 utf8 库，自己按字节拆字符

-- 逐个字符：返回 (码点, 字符)
local function utf8_chars(s)
  return s:gmatch("()([%z\1-\127\194-\244][\128-\191]*)")
end
local function codepoint(ch)
  local b = { ch:byte(1, -1) }
  if #b == 1 then return b[1] end
  local cp = b[1] % (2 ^ (7 - #b))
  for i = 2, #b do cp = cp * 64 + b[i] % 64 end
  return cp
end

-- 标题里的行内标记先按渲染后的文字处理：[文字](链接) 只取文字，图片去掉
local function heading_plain(text)
  text = text:gsub("!%[[^%]]*%]%b()", "")
  text = text:gsub("%[([^%]]*)%]%b()", "%1")
  text = text:gsub("%[([^%]]*)%]%[[^%]]*%]", "%1")
  text = text:gsub("<[^>]+>", "") -- 行内 HTML 标签
  return vim.trim(text)
end

---标题文字 → 锚点（不含 #，不处理重名后缀）
function M.slug(text)
  text = heading_plain(text):lower()
  local out = {}
  for _, ch in utf8_chars(text) do
    local cp = codepoint(ch)
    if cp < 128 then
      if ch:match("[%w_%-]") then
        out[#out + 1] = ch
      elseif ch == " " then
        out[#out + 1] = "-"
      end
    elseif not is_unicode_punct(cp) then
      out[#out + 1] = ch
    end
  end
  return table.concat(out)
end

-- ================= 标题 =================
---取文档里的所有标题：{ level, text, lnum（1 基）, anchor }；重名标题按 GitHub 规则加 -1、-2 后缀
---@param buf integer
function M.headings(buf)
  local ok, parser = pcall(vim.treesitter.get_parser, buf, "markdown")
  local list = {}
  if ok and parser then
    local tree = parser:parse()[1]
    local query = vim.treesitter.query.parse("markdown", "[(atx_heading) (setext_heading)] @h")
    for _, node in query:iter_captures(tree:root(), buf, 0, -1) do
      local level, text
      for child in node:iter_children() do
        local t = child:type()
        local l = t:match("^atx_h(%d)_marker$")
        if l then level = tonumber(l) end
        if t == "setext_h1_underline" then level = 1 elseif t == "setext_h2_underline" then level = 2 end
        if t == "inline" or t == "paragraph" then text = vim.treesitter.get_node_text(child, buf) end
      end
      local srow = node:range()
      list[#list + 1] = { level = level or 1, text = vim.trim((text or ""):gsub("%s*#+%s*$", "")), lnum = srow + 1 }
    end
  else
    -- 没有 markdown 解析器时退回按行匹配 # 标题（跳过 ``` 代码块）
    local in_code = false
    for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
      if l:match("^%s*```") or l:match("^%s*~~~") then in_code = not in_code end
      local hashes, text = l:match("^ ? ? ?(#+)%s+(.-)%s*#*%s*$")
      if not in_code and hashes and #hashes <= 6 then
        list[#list + 1] = { level = #hashes, text = text, lnum = i }
      end
    end
  end
  table.sort(list, function(a, b) return a.lnum < b.lnum end)
  local seen = {}
  for _, h in ipairs(list) do
    local s = M.slug(h.text)
    local n = seen[s]
    h.anchor = n and (s .. "-" .. n) or s
    seen[s] = (n or 0) + 1
  end
  return list
end

---在 buf 里找锚点对应的行号（找不到返回 nil）；也支持 #L10 这种行号锚点
function M.find_anchor(buf, anchor)
  anchor = M.url_decode(anchor)
  local line = anchor:match("^L(%d+)")
  if line then return tonumber(line) end
  local want = anchor:lower()
  for _, h in ipairs(M.headings(buf)) do
    if h.anchor == want then return h.lnum end
  end
  -- 写链接的人可能没去标点、带了大写，再按同样规则算一遍比较
  local s = M.slug(anchor)
  for _, h in ipairs(M.headings(buf)) do
    if h.anchor == s then return h.lnum end
  end
end

-- ================= 链接解析 =================
function M.url_decode(s)
  return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- 引用式链接的定义：[ref]: 地址 "标题"（引用名不区分大小写）
local function ref_target(buf, ref)
  ref = vim.trim(ref):lower()
  for _, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    local name, target = l:match("^%s*%[([^%]]+)%]:%s*(%S+)")
    if name and vim.trim(name):lower() == ref then
      return (target:gsub("^<(.*)>$", "%1"))
    end
  end
end

---找出 line 第 col 个字节（0 基）所在的链接，返回链接地址（未解析）；不在链接上返回 nil
---@param line string
---@param col integer
---@param buf? integer 引用式链接需要在这个缓冲区里找定义
function M.link_at(line, col, buf)
  local c = col + 1 -- 转成 Lua 的 1 基下标
  local found
  local function hit(s, e, target)
    if not found and target and c >= s and c <= e then found = target end
  end
  -- [文字](地址 "标题") 和 ![图](地址)：括号内取第一个空白前的部分，<地址> 形式去掉尖括号
  local init = 1
  while true do
    local s, e1 = line:find("%b[]", init)
    if not s then break end
    local rest = line:sub(e1 + 1)
    local paren = rest:match("^%b()")
    local bracket = rest:match("^%b[]")
    if paren then
      local inner = vim.trim(paren:sub(2, -2))
      local target = inner:match("^<(.-)>") or inner:match("^(%S+)")
      if s > 1 and line:sub(s - 1, s - 1) == "!" then s = s - 1 end
      hit(s, e1 + #paren, target)
      init = e1 + #paren + 1
    elseif bracket and buf then
      -- [文字][ref]，[文字][] 用文字本身作引用名
      local ref = bracket:sub(2, -2)
      if ref == "" then ref = line:sub(s + 1, e1 - 1) end
      hit(s, e1 + #bracket, ref_target(buf, ref))
      init = e1 + #bracket + 1
    else
      -- [ref] 单独出现：有定义才算链接（避免把普通方括号当链接），定义行本身也算
      local def = buf and line:match("^%s*%[[^%]]+%]:%s*(%S+)")
      if def and line:sub(e1 + 1, e1 + 1) == ":" then
        hit(s, #line, (def:gsub("^<(.*)>$", "%1")))
      elseif buf then
        hit(s, e1, ref_target(buf, line:sub(s + 1, e1 - 1)))
      end
      init = e1 + 1
    end
  end
  if found then return found end
  -- <https://...> 自动链接
  init = 1
  while true do
    local s, e, url = line:find("<(%a[%w+.-]*://[^>%s]+)>", init)
    if not s then break end
    hit(s, e, url)
    init = e + 1
  end
  if found then return found end
  -- 正文里裸写的网址
  init = 1
  while true do
    local s, e, url = line:find("(https?://[%w%-%._~:/%?#%[%]@!%$&'%*%+,;=%%]+)", init)
    if not s then break end
    url = url:gsub("[.,;:!?'%)]+$", "")
    hit(s, s + #url - 1, url)
    init = e + 1
  end
  return found
end

---把链接地址解析成要做的事：{ kind = "url"|"anchor"|"file", url?, path?, anchor? }
---@param target string
---@param base_dir string 当前文件所在目录
function M.resolve(target, base_dir)
  if target:match("^%a[%w+.-]*://") or target:match("^mailto:") then
    return { kind = "url", url = target }
  end
  if target:sub(1, 1) == "#" then
    return { kind = "anchor", anchor = target:sub(2) }
  end
  local path, anchor = target:match("^([^#]*)#(.*)$")
  path = M.url_decode(path or target):gsub("%?.*$", "")
  if path:sub(1, 1) == "/" and not vim.uv.fs_stat(path) then
    -- GitHub 上 /开头 表示仓库根目录
    local root = vim.fs.root(base_dir, ".git") or vim.fn.getcwd()
    path = root .. path
  elseif path:sub(1, 1) == "~" then
    path = vim.fn.expand(path)
  elseif path:sub(1, 1) ~= "/" then
    path = base_dir .. "/" .. path
  end
  return { kind = "file", path = vim.fs.normalize(path), anchor = anchor ~= "" and anchor or nil }
end

local function goto_line(lnum)
  local last = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(lnum, last)), 0 })
  vim.cmd("normal! zvzt")
end

---打开光标下的链接；不在链接上返回 false
function M.follow()
  local buf = vim.api.nvim_get_current_buf()
  local cur = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_get_current_line()
  local target = M.link_at(line, cur[2], buf)
  if not target or target == "" then return false end
  local base = vim.fs.dirname(vim.api.nvim_buf_get_name(buf))
  local r = M.resolve(target, base ~= "" and base or vim.fn.getcwd())
  if r.kind == "url" then
    vim.ui.open(r.url)
    return true
  end
  -- 记录跳转位置，Ctrl+Alt+← 可以回来
  vim.cmd("normal! m'")
  if r.kind == "anchor" then
    local lnum = M.find_anchor(buf, r.anchor)
    if not lnum then
      vim.notify("找不到标题：#" .. r.anchor, vim.log.levels.WARN)
      return true
    end
    goto_line(lnum)
    return true
  end
  if not vim.uv.fs_stat(r.path) then
    vim.notify("文件不存在：" .. vim.fn.fnamemodify(r.path, ":~:."), vim.log.levels.WARN)
    return true
  end
  vim.cmd("edit " .. vim.fn.fnameescape(r.path))
  if r.anchor then
    local lnum = M.find_anchor(0, r.anchor)
    if lnum then
      goto_line(lnum)
    else
      vim.notify("找不到标题：#" .. r.anchor, vim.log.levels.WARN)
    end
  end
  return true
end

-- ================= 大纲 =================
---大纲弹框：按层级缩进显示标题，可输入过滤，回车跳转；默认选中光标所在的那一节
function M.outline()
  local buf = vim.api.nvim_get_current_buf()
  local file = vim.api.nvim_buf_get_name(buf)
  local cur = vim.api.nvim_win_get_cursor(0)[1]
  local items, current = {}, nil
  for i, h in ipairs(M.headings(buf)) do
    items[#items + 1] = {
      text = h.text, level = h.level, buf = buf, file = file ~= "" and file or nil,
      pos = { h.lnum, 0 }, idx = i,
    }
    if h.lnum <= cur then current = i end
  end
  if #items == 0 then
    vim.notify("这个文件没有标题", vim.log.levels.INFO)
    return
  end
  return Snacks.picker.pick({
    title = "大纲",
    items = items,
    layout = { preset = "select", preview = false },
    sort = { fields = { "score:desc", "idx" } },
    format = function(item)
      local hl = "markdownH" .. math.min(item.level, 6)
      if vim.fn.hlexists("RenderMarkdownH" .. item.level) == 1 then hl = "RenderMarkdownH" .. item.level end
      return {
        { ("  "):rep(item.level - 1) },
        { ("H%d "):format(item.level), "Comment" },
        { item.text, hl },
      }
    end,
    on_show = function(picker)
      if current then picker.list:view(current) end
    end,
  })
end

-- ================= 按键 =================
require("config.kit.goto").register("markdown 链接", function()
  if vim.bo.filetype ~= "markdown" then return false end
  return M.follow()
end, 10)

local function setup_buf(buf)
  local o = { buffer = buf }
  K.map("n", "<CR>", function()
    if not M.follow() then vim.cmd("normal! " .. vim.v.count1 .. "+") end
  end, "打开链接（不在链接上时移到下一行）", o)
  K.map(K.NI, "<C-F12>", K.n(M.outline), "标题大纲", o)
  K.map(K.NI, "<M-7>", K.n(M.outline), "标题大纲", o)
end

local group = vim.api.nvim_create_augroup("kit_markdown_view", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "markdown",
  callback = function(ev) setup_buf(ev.buf) end,
})
-- 本模块加载前已经打开的 markdown 文件
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].filetype == "markdown" then setup_buf(b) end
end

return M
