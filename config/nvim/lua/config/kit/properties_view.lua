-- *.properties 里的 \uXXXX 显示为对应的文字（IDEA 的 Transparent native-to-ascii conversion）
-- 做法：用 extmark 把转义序列隐藏（conceal）并在原位置插入虚拟文字，文件内容不改写；
--   * 插入模式下光标所在行显示原文，方便编辑
--   * 改动后只重新计算改动过的行（nvim_buf_attach 的 on_lines），大文件也不卡
local M = {}
local ns = vim.api.nvim_create_namespace("kit_properties_view")
M.ns = ns

-- Neovim 的 LuaJIT 没有 utf8 库：码点 → UTF-8
local function utf8_char(cp)
  if cp < 0x80 then return string.char(cp) end
  if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40) end
  if cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(0xF0 + math.floor(cp / 0x40000), 0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
end

-- 两个代理项（😀 这种）合成一个字符
local function decode_units(units)
  local out, i = {}, 1
  while i <= #units do
    local u = units[i]
    local lo = units[i + 1]
    if u >= 0xD800 and u <= 0xDBFF and lo and lo >= 0xDC00 and lo <= 0xDFFF then
      out[#out + 1] = utf8_char(0x10000 + (u - 0xD800) * 0x400 + (lo - 0xDC00))
      i = i + 2
    else
      -- 落单的代理项不是合法字符，显示替换符
      out[#out + 1] = (u >= 0xD800 and u <= 0xDFFF) and utf8_char(0xFFFD) or utf8_char(u)
      i = i + 1
    end
  end
  return table.concat(out)
end

---找出一行里连续的 \uXXXX 转义：返回 { { s = 起始列(0 基), e = 结束列(不含), text = 解码后的文字 }, ... }
---前面有奇数个反斜杠的（如 \\u0041，表示字面上的 A）不算转义
function M.escapes(line)
  local runs = {}
  local init = 1
  while true do
    local s = line:find("\\u%x%x%x%x", init)
    if not s then break end
    local bs, j = 0, s - 1
    while j >= 1 and line:sub(j, j) == "\\" do bs = bs + 1 j = j - 1 end
    if bs % 2 == 1 then
      init = s + 2
    else
      local units, e = {}, s
      while line:sub(e, e + 1) == "\\u" and line:sub(e + 2, e + 5):match("^%x%x%x%x$") do
        units[#units + 1] = tonumber(line:sub(e + 2, e + 5), 16)
        e = e + 6
      end
      runs[#runs + 1] = { s = s - 1, e = e - 1, text = decode_units(units) }
      init = e
    end
  end
  return runs
end

-- 插入模式下光标所在的行（这一行显示原文）
local function editing_row(buf)
  if not vim.fn.mode():match("^i") and not vim.fn.mode():match("^R") then return nil end
  if vim.api.nvim_get_current_buf() ~= buf then return nil end
  return vim.api.nvim_win_get_cursor(0)[1] - 1
end

---重新计算 [first, last) 行的显示（0 基）
function M.refresh(buf, first, last)
  if not vim.api.nvim_buf_is_valid(buf) then return end
  last = math.min(last or vim.api.nvim_buf_line_count(buf), vim.api.nvim_buf_line_count(buf))
  first = math.max(first or 0, 0)
  vim.api.nvim_buf_clear_namespace(buf, ns, first, last)
  if first >= last then return end
  local skip = editing_row(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, first, last, false)
  for i, l in ipairs(lines) do
    local row = first + i - 1
    if row ~= skip and l:find("\\u", 1, true) then
      for _, r in ipairs(M.escapes(l)) do
        vim.api.nvim_buf_set_extmark(buf, ns, row, r.s, {
          end_col = r.e,
          conceal = "",
          virt_text = { { r.text, "@string" } },
          virt_text_pos = "inline",
          invalidate = true,
        })
      end
    end
  end
end

---某一行实际显示的内容（测试用）：隐藏的转义换成虚拟文字
function M.display_line(buf, row)
  local l = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1] or ""
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { row, 0 }, { row, -1 }, { details = true })
  table.sort(marks, function(a, b) return a[3] > b[3] end)
  for _, m in ipairs(marks) do
    local d = m[4]
    local text = d.virt_text and d.virt_text[1][1] or ""
    l = l:sub(1, m[3]) .. text .. l:sub((d.end_col or m[3]) + 1)
  end
  return l
end

local attached = {}

local function set_win(win)
  -- 隐藏转义需要 conceallevel ≥ 2；普通模式下光标行也显示文字（concealcursor 含 n），插入模式显示原文
  vim.wo[win][0].conceallevel = 2
  vim.wo[win][0].concealcursor = "nc"
end

function M.attach(buf)
  for _, win in ipairs(vim.fn.win_findbuf(buf)) do set_win(win) end
  if attached[buf] then return end
  attached[buf] = true
  M.refresh(buf)
  vim.api.nvim_buf_attach(buf, false, {
    on_lines = function(_, b, _, first, _, new_last)
      vim.schedule(function() M.refresh(b, first, new_last) end)
    end,
    on_reload = function(_, b) vim.schedule(function() M.refresh(b) end) end,
    on_detach = function(_, b) attached[b] = nil end,
  })
  local group = vim.api.nvim_create_augroup("kit_properties_view_" .. buf, { clear = true })
  local last_row
  vim.api.nvim_create_autocmd({ "InsertEnter", "CursorMovedI" }, {
    group = group,
    buffer = buf,
    callback = function(ev)
      -- InsertEnter 时 mode() 还不是 i，直接清掉当前行；光标换行后把上一行恢复成文字
      local row = vim.api.nvim_win_get_cursor(0)[1] - 1
      if last_row and last_row ~= row then M.refresh(buf, last_row, last_row + 1) end
      vim.api.nvim_buf_clear_namespace(buf, ns, row, row + 1)
      last_row = row
    end,
  })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = group,
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if last_row then M.refresh(buf, last_row, last_row + 1) end
        last_row = nil
      end)
    end,
  })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    buffer = buf,
    callback = function() set_win(0) end,
  })
end

local group = vim.api.nvim_create_augroup("kit_properties_view", { clear = true })
vim.api.nvim_create_autocmd("FileType", {
  group = group,
  pattern = "jproperties",
  callback = function(ev)
    if vim.api.nvim_buf_get_name(ev.buf):match("%.properties$") then M.attach(ev.buf) end
  end,
})
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b):match("%.properties$") then M.attach(b) end
end

return M
