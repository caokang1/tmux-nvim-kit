-- 左侧图标（sign 列 / 行号栏）点击的共享登记表：IDEA 里点左侧图标会跳到实现 / 父类 / XML 等。
-- 多个模块（gutter 的"实现/重写"图标、MyBatis 图标……）都要处理同一个鼠标左键，各自映射 <LeftMouse> 会互相覆盖，
-- 所以统一在这里映射一次，各模块只登记"某个缓冲区的某一行点了做什么"。
--
-- 用法：
--   local sc = require("config.kit.signclick")
--   sc.set(buf, "mybatis", { [行号] = { fn = function() ... end, label = "跳到 XML" }, ... })  -- 整体替换该模块在此缓冲区的登记
--   sc.clear(buf, "mybatis")
--   （handlers 的值也可以直接写函数；label 用于同一行有多个模块的图标时弹出选择）
-- 点击左侧栏（行号、图标所在区域）且该行有登记时执行处理函数；否则执行原本的点击（移动光标等）
local M = { registry = {} } -- registry[buf][owner] = { [lnum] = handler }

function M.set(buf, owner, handlers)
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  M.registry[buf] = M.registry[buf] or {}
  M.registry[buf][owner] = handlers
end

function M.clear(buf, owner)
  if buf == 0 then buf = vim.api.nvim_get_current_buf() end
  if M.registry[buf] then M.registry[buf][owner] = nil end
end

-- 返回某行登记的处理函数列表 { { owner, fn, label } ... }
function M.get(buf, lnum)
  local res = {}
  local owners = vim.tbl_keys(M.registry[buf] or {})
  table.sort(owners)
  for _, owner in ipairs(owners) do
    local h = M.registry[buf][owner][lnum]
    if h then
      if type(h) == "function" then h = { fn = h } end
      res[#res + 1] = { owner = owner, fn = h.fn, label = h.label or owner }
    end
  end
  return res
end

-- 执行某行的处理函数：只有一个直接执行，多个时让用户选
function M.run(buf, lnum)
  local hs = M.get(buf, lnum)
  if #hs == 0 then return false end
  if #hs == 1 then
    hs[1].fn()
  else
    vim.ui.select(hs, {
      prompt = "选择要执行的操作",
      format_item = function(h) return h.label end,
    }, function(h) if h then h.fn() end end)
  end
  return true
end

-- 鼠标位置（getmousepos() 的结果）是否在左侧栏（行号 / 图标 / 折叠栏，即文字区左边的部分）且该行有登记
function M.hit(pos)
  if not pos or pos.winid == 0 or pos.line == 0 or not vim.api.nvim_win_is_valid(pos.winid) then return end
  local info = vim.fn.getwininfo(pos.winid)[1]
  if not info or pos.wincol < 1 or pos.wincol > info.textoff then return end
  local buf = vim.api.nvim_win_get_buf(pos.winid)
  if #M.get(buf, pos.line) == 0 then return end
  return buf
end

-- 处理一次点击：命中返回 true（处理函数在下一轮事件循环执行），否则返回 false
function M.click(pos)
  local buf = M.hit(pos)
  if not buf then return false end
  -- 映射表达式里不能切换窗口 / 移动光标，放到下一轮事件循环执行
  vim.schedule(function()
    if not vim.api.nvim_win_is_valid(pos.winid) then return end
    vim.cmd("stopinsert")
    vim.api.nvim_set_current_win(pos.winid)
    pcall(vim.api.nvim_win_set_cursor, pos.winid, { pos.line, 0 })
    M.run(buf, pos.line)
  end)
  return true
end

local function on_click()
  if M.click(vim.fn.getmousepos()) then return "" end
  return "<LeftMouse>"
end

for _, mode in ipairs({ "n", "i" }) do
  vim.keymap.set(mode, "<LeftMouse>", on_click, { expr = true, replace_keycodes = true, silent = true, desc = "点击左侧图标跳转" })
end

-- 缓冲区删除时清掉登记
vim.api.nvim_create_autocmd("BufWipeout", {
  group = vim.api.nvim_create_augroup("kit_signclick", { clear = true }),
  callback = function(ev) M.registry[ev.buf] = nil end,
})

return M
