-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- 选中后按 Ctrl+C 复制到系统剪贴板（和 tmux、Windows 习惯一致）
vim.keymap.set("v", "<C-c>", '"+y', { desc = "复制到系统剪贴板" })

-- 录宏改用 Q（按 Q 开始，再按 Q 停止），单按 q 不再误进入 recording 状态
-- 帮助、Lazy、资源管理器等窗口里按 q 关闭的功能不受影响（它们自带缓冲区内的 q 映射）
vim.keymap.set("n", "Q", "q", { desc = "录制宏（Q+寄存器开始，Q停止）" })
vim.keymap.set("n", "q", "<Nop>", { desc = "已禁用：录宏请用 Q" })

-- IDEA 快捷键（Ctrl+D 复制行、Alt+Enter、Shift+F6 等）
require("config.idea_keys")

-- 和 IDEA 一样：Shift+滚轮横向滚动（触控板左右滑动也会转成这个），滚动的是鼠标所在的窗口，
-- 所以编辑区和弹框（预览等）都能横向看长代码
local function hscroll(dir)
  return function()
    local win = vim.fn.getmousepos().winid
    if win == 0 then win = vim.api.nvim_get_current_win() end
    if vim.wo[win].wrap then return end -- 已折行显示的窗口不需要横向滚动
    vim.fn.win_execute(win, "normal! 6z" .. (dir > 0 and "l" or "h"))
  end
end
for _, mode in ipairs({ "n", "i", "v" }) do
  vim.keymap.set(mode, "<S-ScrollWheelDown>", hscroll(1), { desc = "向右滚动" })
  vim.keymap.set(mode, "<S-ScrollWheelUp>", hscroll(-1), { desc = "向左滚动" })
  vim.keymap.set(mode, "<ScrollWheelRight>", hscroll(1), { desc = "向右滚动" })
  vim.keymap.set(mode, "<ScrollWheelLeft>", hscroll(-1), { desc = "向左滚动" })
end

-- 和 IDEA 一样：按住 Ctrl 或 Alt 鼠标左键点击变量 / 方法 / 类，跳转到定义（Ctrl+o 跳回）
-- 先把光标移到点击处，再执行 gd（有语言服务时是跳转到定义，否则跳到当前文件里的声明）
for _, lhs in ipairs({ "<C-LeftMouse>", "<M-LeftMouse>" }) do
  vim.keymap.set("n", lhs, "<LeftMouse>gd", { remap = true, desc = "跳转到定义（Ctrl/Alt+点击）" })
end
