-- 书签（IDEA Bookmarks）
--   Alt+F11          当前行加上 / 去掉书签（IDEA 是 F11，F11 在 Windows Terminal 和浏览器里是全屏，不占用）
--   Ctrl+F11         带助记符的书签：弹出 0-9 / A-Z 选择，左侧显示这个字符
--   空格 m 0-9 / A-Z  跳到对应助记符的书签（IDEA 是 Ctrl+数字，终端里大多分不出 Ctrl+数字）
--   Alt+Shift+F11 / 空格 m m   书签列表（Ctrl+D / Delete 删除，Ctrl+R 编辑描述）
--   空格 m t / 空格 m n        同 Alt+F11 / Ctrl+F11（备用）
--
-- 按项目保存到 stdpath("data")/kit-bookmarks/<项目路径哈希>.json，重开 nvim 仍在。
-- 文件打开时书签用 extmark 记录，编辑时跟着行移动，保存文件时写回行号；同时记下该行文字，
-- 文件在外部被改动（git 切分支等）后按文字重新找到那一行。
local K = require("config.idea_keys")
local M = {}

local ns = vim.api.nvim_create_namespace("kit_bookmarks")
M.ns = ns
M.dir = vim.fn.stdpath("data") .. "/kit-bookmarks"
M.icon = ""
M.chars = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ"

vim.api.nvim_set_hl(0, "KitBookmarkSign", { default = true, fg = "#56A8F5", bold = true })
vim.api.nvim_set_hl(0, "KitBookmarkUsed", { default = true, link = "Search" })
vim.api.nvim_set_hl(0, "KitBookmarkCurrent", { default = true, link = "IncSearch" })

-- 项目 = nvim 的工作目录（tmux-nvim-kit 在项目根目录启动 nvim）。不用每个缓冲区各自的 LazyVim.root()：
-- Java 文件在 jdtls 附加前后算出的根目录会不同，书签会被分到两个项目里
function M.project()
  return vim.fs.normalize(vim.fn.getcwd(-1, -1))
end

local stores = {} ---@type table<string, {root:string, path:string, list:table[]}>

local function store_path(root)
  return M.dir .. "/" .. vim.fn.sha256(root):sub(1, 16) .. ".json"
end

function M.store(root)
  root = root or M.project()
  if stores[root] then return stores[root] end
  local s = { root = root, path = store_path(root), list = {} }
  local f = io.open(s.path, "r")
  if f then
    local ok, data = pcall(vim.json.decode, f:read("*a"))
    f:close()
    if ok and type(data) == "table" and type(data.bookmarks) == "table" then
      for _, b in ipairs(data.bookmarks) do
        if type(b.file) == "string" and type(b.line) == "number" then
          s.list[#s.list + 1] = {
            file = b.file, line = b.line, text = b.text or "",
            mnemonic = b.mnemonic ~= vim.NIL and b.mnemonic or nil,
            desc = b.desc ~= vim.NIL and b.desc or nil,
          }
        end
      end
    end
  end
  stores[root] = s
  return s
end

-- 测试用：丢掉内存里的数据（下次从磁盘重新读）
function M._reset()
  for _, s in pairs(stores) do
    for _, b in ipairs(s.list) do
      if b.buf and vim.api.nvim_buf_is_valid(b.buf) and b.id then pcall(vim.api.nvim_buf_del_extmark, b.buf, ns, b.id) end
    end
  end
  stores = {}
end

local function trim(s) return vim.trim(s or "") end

local function line_text(buf, lnum)
  return (vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1]) or ""
end

-- 从 extmark 读回最新行号和该行文字；行被删掉（extmark 失效）的书签返回 false
local function sync_one(b)
  if not (b.buf and b.id and vim.api.nvim_buf_is_valid(b.buf) and vim.api.nvim_buf_is_loaded(b.buf)) then return true end
  local m = vim.api.nvim_buf_get_extmark_by_id(b.buf, ns, b.id, { details = true })
  if not m[1] then return true end
  if m[3] and m[3].invalid then return false end
  b.line = m[1] + 1
  b.text = trim(line_text(b.buf, b.line))
  return true
end

function M.sync(s)
  s = s or M.store()
  local keep = {}
  for _, b in ipairs(s.list) do
    if sync_one(b) then
      keep[#keep + 1] = b
    elseif b.buf and vim.api.nvim_buf_is_valid(b.buf) then
      pcall(vim.api.nvim_buf_del_extmark, b.buf, ns, b.id)
    end
  end
  s.list = keep
  return s
end

function M.save(s)
  s = M.sync(s or M.store())
  vim.fn.mkdir(M.dir, "p")
  local out = {}
  for _, b in ipairs(s.list) do
    out[#out + 1] = { file = b.file, line = b.line, text = b.text, mnemonic = b.mnemonic, desc = b.desc }
  end
  local f = io.open(s.path, "w")
  if not f then
    vim.notify("书签保存失败：" .. s.path, vim.log.levels.WARN)
    return
  end
  f:write(vim.json.encode({ root = s.root, bookmarks = out }))
  f:close()
end

-- 文件在外部被改过时，按保存的文字找回书签所在行：原行号上文字一样就不动，否则找离原行号最近的同样文字的行
function M.relocate(lines, line, text)
  text = trim(text)
  local n = #lines
  line = math.max(1, math.min(line, math.max(n, 1)))
  if text == "" or trim(lines[line]) == text then return line end
  for d = 1, n do
    if line - d >= 1 and trim(lines[line - d]) == text then return line - d end
    if line + d <= n and trim(lines[line + d]) == text then return line + d end
  end
  return line
end

local function place(b, buf)
  local opts = {
    sign_text = b.mnemonic or M.icon,
    sign_hl_group = "KitBookmarkSign",
    priority = 20,
    invalidate = true,
    undo_restore = true,
  }
  if b.id and b.buf == buf then opts.id = b.id end
  b.buf = buf
  b.id = vim.api.nvim_buf_set_extmark(buf, ns, b.line - 1, 0, opts)
end

local function is_file_buf(buf)
  return vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= ""
end

local function fname(buf)
  return vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
end

-- 文件打开时给它的书签放上 extmark（左侧图标）
function M.attach(buf)
  buf = buf or vim.api.nvim_get_current_buf()
  if not (vim.api.nvim_buf_is_loaded(buf) and is_file_buf(buf)) then return end
  local s = M.store()
  local file = fname(buf)
  local lines
  for _, b in ipairs(s.list) do
    if b.file == file then
      local m = (b.buf == buf and b.id) and vim.api.nvim_buf_get_extmark_by_id(buf, ns, b.id, {}) or {}
      if not m[1] then
        lines = lines or vim.api.nvim_buf_get_lines(buf, 0, -1, false)
        b.line = M.relocate(lines, b.line, b.text)
        place(b, buf)
      end
    end
  end
end

function M.find(buf, lnum)
  local s = M.sync(M.store())
  local file = fname(buf)
  for i, b in ipairs(s.list) do
    if b.file == file and b.line == lnum then return b, i end
  end
end

function M.by_mnemonic(ch)
  local s = M.sync(M.store())
  for _, b in ipairs(s.list) do
    if b.mnemonic == ch then return b end
  end
end

function M.add(buf, lnum, mnemonic)
  local s = M.store()
  local b = { file = fname(buf), line = lnum, text = trim(line_text(buf, lnum)), mnemonic = mnemonic }
  s.list[#s.list + 1] = b
  place(b, buf)
  M.save(s)
  return b
end

function M.remove(b)
  local s = M.store()
  for i, x in ipairs(s.list) do
    if x == b then
      table.remove(s.list, i)
      break
    end
  end
  if b.buf and b.id and vim.api.nvim_buf_is_valid(b.buf) then pcall(vim.api.nvim_buf_del_extmark, b.buf, ns, b.id) end
  M.save(s)
end

-- 当前行有书签就去掉，没有就加上
function M.toggle(buf, lnum)
  buf = buf or vim.api.nvim_get_current_buf()
  lnum = lnum or vim.api.nvim_win_get_cursor(0)[1]
  if not is_file_buf(buf) then
    vim.notify("只能给项目里的文件加书签", vim.log.levels.INFO, { title = "书签" })
    return
  end
  local b = M.find(buf, lnum)
  if b then
    M.remove(b)
    return nil
  end
  return M.add(buf, lnum)
end

-- 给当前行的书签设置助记符（没有书签就新建）；这个字符已用在别的书签上时从那里移过来（和 IDEA 一样）
function M.set_mnemonic(buf, lnum, ch)
  ch = ch and ch:upper()
  if ch and not M.chars:find(ch, 1, true) then return end
  local other = ch and M.by_mnemonic(ch)
  local b = M.find(buf, lnum)
  if other and other ~= b then
    other.mnemonic = nil
    if other.buf and vim.api.nvim_buf_is_valid(other.buf) then place(other, other.buf) end
  end
  if not b then return M.add(buf, lnum, ch) end
  b.mnemonic = ch
  if b.buf and vim.api.nvim_buf_is_valid(b.buf) then place(b, b.buf) end
  M.save()
  return b
end

function M.set_desc(b, desc)
  b.desc = (desc and desc ~= "") and desc or nil
  M.save()
end

-- 列表顺序：有助记符的在前（0-9、A-Z），其余按文件、行号
function M.list()
  local s = M.sync(M.store())
  local ret = vim.list_slice(s.list)
  table.sort(ret, function(a, b)
    if (a.mnemonic ~= nil) ~= (b.mnemonic ~= nil) then return a.mnemonic ~= nil end
    if a.mnemonic and b.mnemonic then return a.mnemonic < b.mnemonic end
    if a.file ~= b.file then return a.file < b.file end
    return a.line < b.line
  end)
  return ret
end

local function open_bookmark(b)
  local buf = vim.fn.bufadd(b.file)
  vim.bo[buf].buflisted = true
  vim.cmd("normal! m'")
  vim.api.nvim_win_set_buf(0, buf)
  M.attach(buf)
  sync_one(b)
  local last = vim.api.nvim_buf_line_count(buf)
  vim.api.nvim_win_set_cursor(0, { math.min(b.line, last), 0 })
  vim.cmd("normal! ^zz")
end

function M.jump(ch)
  local b = M.by_mnemonic(ch)
  if not b then
    vim.notify("没有助记符为 " .. ch .. " 的书签（Ctrl+F11 设置）", vim.log.levels.INFO, { title = "书签" })
    return
  end
  if not vim.uv.fs_stat(b.file) then
    vim.notify("书签所在的文件已不存在：" .. b.file, vim.log.levels.WARN, { title = "书签" })
    return
  end
  open_bookmark(b)
end

-- Ctrl+F11：弹出 0-9 / A-Z 网格，已用的字符标出来，按一个字符设置
function M.mnemonic_prompt()
  local buf = vim.api.nvim_get_current_buf()
  local lnum = vim.api.nvim_win_get_cursor(0)[1]
  if not is_file_buf(buf) then
    vim.notify("只能给项目里的文件加书签", vim.log.levels.INFO, { title = "书签" })
    return
  end
  local cur = M.find(buf, lnum)
  local used = {}
  for _, b in ipairs(M.store().list) do
    if b.mnemonic then used[b.mnemonic] = b end
  end
  local rows = { "0123456789", "ABCDEFGHIJKLM", "NOPQRSTUVWXYZ" }
  local lines, hls = {}, {}
  for r, row in ipairs(rows) do
    local l = " "
    for i = 1, #row do
      local ch = row:sub(i, i)
      local col = #l
      l = l .. " " .. ch .. " "
      if cur and cur.mnemonic == ch then
        hls[#hls + 1] = { r - 1, col, col + 3, "KitBookmarkCurrent" }
      elseif used[ch] then
        hls[#hls + 1] = { r - 1, col, col + 3, "KitBookmarkUsed" }
      end
    end
    lines[#lines + 1] = l
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = " 按字符设置（高亮的已被占用，会移到这一行）"
  lines[#lines + 1] = cur and " Delete 删除这个书签   Esc 取消" or " 空格 只加书签不设字符   Esc 取消"
  local width = 0
  for _, l in ipairs(lines) do width = math.max(width, vim.api.nvim_strwidth(l) + 1) end
  local pbuf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(pbuf, 0, -1, false, lines)
  for _, h in ipairs(hls) do
    vim.api.nvim_buf_set_extmark(pbuf, ns, h[1], h[2], { end_col = h[3], hl_group = h[4] })
  end
  local win = vim.api.nvim_open_win(pbuf, false, {
    relative = "editor", style = "minimal", border = "rounded", width = width, height = #lines,
    row = math.floor((vim.o.lines - #lines) / 2) - 1, col = math.floor((vim.o.columns - width) / 2),
    title = " 设置书签助记符 ", title_pos = "center", zindex = 200,
  })
  vim.cmd.redraw()
  local ok, key = pcall(vim.fn.getcharstr)
  pcall(vim.api.nvim_win_close, win, true)
  pcall(vim.api.nvim_buf_delete, pbuf, { force = true })
  if not ok or key == "\27" or key == vim.keycode("<C-c>") then return end
  if key == vim.keycode("<Del>") or key == vim.keycode("<BS>") then
    if cur then M.remove(cur) end
    return
  end
  if key == " " or key == "\r" then
    if not cur then M.add(buf, lnum) end
    return
  end
  if #key == 1 and key:match("%w") then
    return M.set_mnemonic(buf, lnum, key)
  end
end

-- ================= 书签列表 =================
local function items()
  local root = M.project()
  local ret = {}
  for _, b in ipairs(M.list()) do
    local rel = b.file:sub(1, #root + 1) == root .. "/" and b.file:sub(#root + 2) or b.file
    ret[#ret + 1] = {
      file = b.file, pos = { b.line, 0 }, bm = b, rel = rel,
      buf = (b.buf and vim.api.nvim_buf_is_valid(b.buf) and vim.api.nvim_buf_is_loaded(b.buf)) and b.buf or nil,
      text = table.concat({ b.mnemonic or "", rel, tostring(b.line), b.text or "", b.desc or "" }, " "),
    }
  end
  return ret
end
M.items = items

local function format(item)
  local b = item.bm
  local ret = {
    { b.mnemonic and (" " .. b.mnemonic .. " ") or (" " .. M.icon .. " "), "KitBookmarkSign" },
    { " " },
    { vim.fs.basename(b.file), "SnacksPickerFile" },
    { ":" .. b.line, "SnacksPickerRow" },
    { "  " },
    { b.text or "", "Normal" },
  }
  if b.desc then ret[#ret + 1] = { "  — " .. b.desc, "SnacksPickerComment" } end
  ret[#ret + 1] = { "  " .. vim.fs.dirname(item.rel), "SnacksPickerDir" }
  return ret
end

local function selected(picker)
  local sel = picker:selected({ fallback = true })
  return vim.tbl_filter(function(it) return it.bm ~= nil end, sel)
end

function M.picker()
  -- 列表打开前把当前已打开文件里的书签行号同步一下
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M.attach(buf) end
  end
  local both = { "i", "n" }
  return Snacks.picker.pick({
    title = "书签（Ctrl+D 删除  Ctrl+R 编辑描述）",
    finder = function() return items() end,
    format = format,
    preview = "file",
    actions = {
      bookmark_delete = function(picker)
        for _, it in ipairs(selected(picker)) do M.remove(it.bm) end
        picker.list:set_selected()
        picker:find({ refresh = true })
      end,
      bookmark_desc = function(picker, item)
        if not (item and item.bm) then return end
        Snacks.input({ prompt = "书签描述", default = item.bm.desc or "" }, function(v)
          if v ~= nil then M.set_desc(item.bm, vim.trim(v)) end
          picker:find({ refresh = true })
          picker:focus()
        end)
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-d>"] = { "bookmark_delete", mode = both, desc = "删除书签" },
          ["<Del>"] = { "bookmark_delete", mode = both, desc = "删除书签" },
          ["<C-r>"] = { "bookmark_desc", mode = both, desc = "编辑描述" },
        },
      },
      list = {
        keys = {
          ["<C-d>"] = { "bookmark_delete", desc = "删除书签" },
          ["<Del>"] = { "bookmark_delete", desc = "删除书签" },
          ["dd"] = { "bookmark_delete", desc = "删除书签" },
          ["<C-r>"] = { "bookmark_desc", desc = "编辑描述" },
        },
      },
    },
  })
end

-- ================= 自动命令 =================
local group = vim.api.nvim_create_augroup("kit_bookmarks", { clear = true })
vim.api.nvim_create_autocmd({ "BufReadPost", "BufWinEnter" }, {
  group = group,
  callback = function(ev) M.attach(ev.buf) end,
})
-- 重新读入文件（:e、外部改动后自动重读）会把所有行换掉，extmark 随之失效：
-- 读入前先记下最新行号和文字，读入后（BufReadPost）按文字重新定位
vim.api.nvim_create_autocmd("BufReadPre", {
  group = group,
  callback = function(ev)
    if not stores[M.project()] then return end
    for _, b in ipairs(M.store().list) do
      if b.buf == ev.buf and b.id then
        if vim.api.nvim_buf_is_loaded(ev.buf) then sync_one(b) end
        pcall(vim.api.nvim_buf_del_extmark, ev.buf, ns, b.id)
        b.id = nil
      end
    end
  end,
})
vim.api.nvim_create_autocmd("FileChangedShellPost", {
  group = group,
  callback = function(ev)
    for _, b in ipairs(M.store().list) do
      if b.buf == ev.buf and b.id then
        local m = vim.api.nvim_buf_get_extmark_by_id(ev.buf, ns, b.id, { details = true })
        if not m[1] or (m[3] and m[3].invalid) then
          pcall(vim.api.nvim_buf_del_extmark, ev.buf, ns, b.id)
          b.id = nil
        end
      end
    end
    M.attach(ev.buf)
  end,
})
vim.api.nvim_create_autocmd("BufWritePost", {
  group = group,
  callback = function(ev)
    local file = fname(ev.buf)
    for _, b in ipairs(M.store().list) do
      if b.file == file then return M.save() end
    end
  end,
})
vim.api.nvim_create_autocmd({ "BufUnload", "VimLeavePre" }, {
  group = group,
  callback = function(ev)
    if not stores[M.project()] then return end
    if ev.event == "VimLeavePre" then return M.save() end
    local touched = false
    for _, b in ipairs(M.store().list) do
      if b.buf == ev.buf then
        sync_one(b)
        -- :e! 重新读入时也会触发 BufUnload，但缓冲区和 extmark 还在，要删掉，否则会多出一个
        if b.id then pcall(vim.api.nvim_buf_del_extmark, ev.buf, ns, b.id) end
        b.buf, b.id = nil, nil
        touched = true
      end
    end
    if touched then M.save() end
  end,
})
-- 加载本模块时已经打开的文件
vim.schedule(function()
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then M.attach(buf) end
  end
end)

-- ================= 按键 =================
K.map(K.NI, "<M-F11>", K.n(function() M.toggle() end), "切换书签（IDEA: F11）")
K.map(K.NI, "<C-F11>", K.n(M.mnemonic_prompt), "带助记符的书签（IDEA: Ctrl+F11）")
K.map(K.NI, "<M-S-F11>", K.n(M.picker), "书签列表（IDEA: Shift+F11）")
K.map("n", "<leader>mt", function() M.toggle() end, "切换书签（Alt+F11）")
K.map("n", "<leader>mn", M.mnemonic_prompt, "带助记符的书签（Ctrl+F11）")
K.map("n", "<leader>mm", M.picker, "书签列表（Alt+Shift+F11）")
for i = 1, #M.chars do
  local ch = M.chars:sub(i, i)
  K.map("n", "<leader>m" .. ch, function() M.jump(ch) end, "跳到书签 " .. ch)
end
pcall(function() require("which-key").add({ { "<leader>m", group = "书签" } }) end)

return M
