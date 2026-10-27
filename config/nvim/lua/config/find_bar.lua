-- IDEA 风格的查找栏（Ctrl+F）：编辑区右上角的输入框，边输入边高亮全部匹配并显示 "3/12"
-- 回车 / F3 / ↓ 下一个，Shift+回车 / Shift+F3 / ↑ 上一个，Esc 关闭（光标停在当前匹配处）
-- Alt+C 区分大小写，Alt+W 整词匹配，Alt+X 正则，Ctrl+R 转到替换；找不到时显示"0 个结果"，不报错
local M = {}

local ns = vim.api.nvim_create_namespace("find_bar")
local state = { case = false, words = false, regex = false, last = "" }

local function pattern(text)
  if text == "" then
    return nil
  end
  local p
  if state.regex then
    p = "\\v" .. text
    if state.words then p = "\\v<(" .. text .. ")>" end
  else
    p = "\\V" .. vim.fn.escape(text, "\\")
    if state.words then p = "\\V\\<" .. vim.fn.escape(text, "\\") .. "\\>" end
  end
  return (state.case and "\\C" or "\\c") .. p
end

-- 当前打开的查找栏
local bar

local function clear_matches()
  if not bar or not vim.api.nvim_win_is_valid(bar.src) then return end
  for _, id in ipairs(bar.matches) do
    pcall(vim.fn.matchdelete, id, bar.src)
  end
  bar.matches = {}
end

local function show_status(text, hl)
  if not bar or not vim.api.nvim_buf_is_valid(bar.buf) then return end
  vim.api.nvim_buf_clear_namespace(bar.buf, ns, 0, -1)
  local flags = {
    { state.case and " Aa " or " aa ", state.case and "Special" or "Comment" },
    { state.words and " W " or " w ", state.words and "Special" or "Comment" },
    { state.regex and " .* " or " .* ", state.regex and "Special" or "Comment" },
  }
  local vt = { { text .. " ", hl } }
  vim.list_extend(vt, flags)
  vim.api.nvim_buf_set_extmark(bar.buf, ns, 0, 0, { virt_text = vt, virt_text_pos = "right_align" })
end

-- 高亮所有匹配和当前匹配，显示计数
local function render(pat)
  clear_matches()
  if not pat then
    show_status("", "Comment")
    return
  end
  local ok = pcall(function()
    vim.api.nvim_win_call(bar.src, function()
      table.insert(bar.matches, vim.fn.matchadd("Search", pat, 10))
      local s = vim.fn.searchpos(pat, "cnW")
      local cur = vim.api.nvim_win_get_cursor(0)
      if s[1] == cur[1] and s[2] == cur[2] + 1 then
        local e = vim.fn.searchpos(pat, "cneW")
        if e[1] == s[1] then
          table.insert(bar.matches, vim.fn.matchaddpos("CurSearch", { { s[1], s[2], e[2] - s[2] + 1 } }, 11))
        end
      end
      local c = vim.fn.searchcount({ pattern = pat, recompute = true, maxcount = 0, timeout = 300 })
      if (c.total or 0) == 0 then
        show_status("0 个结果", "ErrorMsg")
      else
        show_status(("%d/%d"):format(c.current, c.total), "Normal")
      end
    end)
  end)
  if not ok then
    clear_matches()
    show_status("正则有误", "ErrorMsg")
  end
end

local function text()
  if not vim.api.nvim_buf_is_valid(bar.buf) then return "" end
  return vim.api.nvim_buf_get_lines(bar.buf, 0, 1, false)[1] or ""
end

-- 输入变化：从打开查找栏时的位置开始找第一个匹配
local function on_change()
  if not bar then return end
  local pat = pattern(text())
  vim.api.nvim_win_set_cursor(bar.src, bar.start)
  if pat then
    local found = 0
    pcall(function()
      vim.api.nvim_win_call(bar.src, function()
        found = vim.fn.search(pat, "cw")
        vim.cmd("normal! zv")
      end)
    end)
    if found == 0 then
      vim.api.nvim_win_set_cursor(bar.src, bar.start)
    end
  end
  render(pat)
end

local function jump(dir)
  if not bar then return end
  local pat = pattern(text())
  if not pat then return end
  pcall(function()
    vim.api.nvim_win_call(bar.src, function()
      vim.fn.search(pat, dir > 0 and "w" or "bw")
      vim.cmd("normal! zv")
    end)
  end)
  render(pat)
end

local function close(keep_pattern)
  if not bar then return end
  local b = bar
  b.closing = true
  local t = text()
  clear_matches()
  if keep_pattern and t ~= "" then
    state.last = t
    vim.fn.setreg("/", pattern(t))
    vim.fn.histadd("/", pattern(t))
  end
  bar = nil
  if vim.api.nvim_win_is_valid(b.win) then vim.api.nvim_win_close(b.win, true) end
  if vim.api.nvim_win_is_valid(b.src) then vim.api.nvim_set_current_win(b.src) end
  vim.cmd("stopinsert")
end

local function toggle(opt)
  return function()
    state[opt] = not state[opt]
    on_change()
  end
end

function M.open(prefill)
  if bar then
    vim.api.nvim_set_current_win(bar.win)
    return
  end
  vim.cmd("stopinsert")
  local src = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "find_bar"
  vim.b[buf].completion = false -- 不弹补全菜单，否则回车会被补全吃掉
  local init = prefill or state.last
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { init })

  local width = math.min(64, vim.api.nvim_win_get_width(src) - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "win",
    win = src,
    anchor = "NE",
    row = 0,
    col = vim.api.nvim_win_get_width(src) - 1,
    width = width,
    height = 1,
    style = "minimal",
    border = "rounded",
    title = " 查找 ",
    footer = " ↵ 下一个 · ↑ 上一个 · Alt+C/W/X 大小写/整词/正则 · Ctrl+R 替换 · Esc 关闭 ",
    footer_pos = "right",
  })
  bar = { buf = buf, win = win, src = src, start = vim.api.nvim_win_get_cursor(src), matches = {} }

  local o = { buffer = buf, silent = true, nowait = true }
  local function both(lhs, fn)
    vim.keymap.set({ "i", "n", "s" }, lhs, fn, o)
  end
  both("<CR>", function() jump(1) end)
  both("<Down>", function() jump(1) end)
  both("<F3>", function() jump(1) end)
  both("<S-CR>", function() jump(-1) end)
  both("<Up>", function() jump(-1) end)
  both("<S-F3>", function() jump(-1) end)
  both("<Esc>", function() close(true) end)
  both("<C-f>", function() end)
  both("<M-c>", toggle("case"))
  both("<M-w>", toggle("words"))
  both("<M-x>", toggle("regex"))
  both("<C-r>", function()
    local t = text()
    close(true)
    require("grug-far").open({ prefills = { search = t, paths = vim.fn.expand("%") } })
  end)
  -- 选中状态下：Backspace 删除并继续输入，← / → 取消选中并移动光标
  vim.keymap.set("s", "<BS>", "<C-g>c", o)
  vim.keymap.set("s", "<Left>", "<C-g><Esc>`<i", o)
  vim.keymap.set("s", "<Right>", "<C-g><Esc>`>a", o)
  vim.keymap.set("s", "<Home>", "<C-g><Esc>I", o)
  vim.keymap.set("s", "<End>", "<C-g><Esc>A", o)

  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, { buffer = buf, callback = on_change })
  -- 意外回到普通模式时（如选中状态下按了某些键）自动回到输入
  vim.api.nvim_create_autocmd("ModeChanged", {
    buffer = buf,
    callback = function()
      vim.schedule(function()
        if bar and not bar.closing and vim.api.nvim_get_current_win() == bar.win and vim.fn.mode() == "n" then
          vim.cmd("startinsert!")
        end
      end)
    end,
  })
  -- 查找栏里的内容被别的操作换掉（如关闭文件）时，连同浮窗一起关闭，避免浮窗里出现 [No Name]
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        if bar and bar.buf == buf then close(false) end
      end)
    end,
  })
  -- 鼠标点到别处时关闭
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        if bar and bar.buf == buf then close(true) end
      end)
    end,
  })

  if init ~= "" then
    -- 和 IDEA 一样：预填的文字处于选中状态，直接输入会替换它
    vim.api.nvim_win_set_cursor(win, { 1, 0 })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("v$<C-g>", true, false, true), "n", false)
    on_change()
  else
    vim.cmd("startinsert!")
    render(nil)
  end
end

-- F3 / Shift+F3：查找栏关闭后继续找上一次的内容，找不到时只提示不报错
function M.next(dir)
  local pat = vim.fn.getreg("/")
  if pat == "" then
    M.open()
    return
  end
  local found = 0
  pcall(function() found = vim.fn.search(pat, dir > 0 and "w" or "bw") end)
  if found == 0 then
    vim.notify("找不到：" .. (state.last ~= "" and state.last or pat), vim.log.levels.WARN)
  else
    vim.cmd("normal! zv")
  end
end

-- 选中的文字（单行）
function M.selection()
  local lines = vim.fn.getregion(vim.fn.getpos("v"), vim.fn.getpos("."), { type = vim.fn.mode() })
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
  return lines[1] or ""
end

return M
