-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- 打开 Windows 盘（/mnt/c、/mnt/d…）上的文件时提醒：WSL 读写这些位置很慢，
-- Java 文件还会让 jdtls 去分析整个 Windows 盘上的项目，容易卡住
local warned = {}
local function warn_windows_drive(buf)
  local name = vim.api.nvim_buf_get_name(buf)
  local root = name:match("^(/mnt/%a/[^/]+)")
  if not root or warned[root] or vim.fn.getcwd():find("^/mnt/%a/") then
    return
  end
  warned[root] = true
  vim.notify(
    ("打开的是 Windows 盘上的文件：\n%s\n读写会很慢；项目已在 WSL 里的话，请改为打开那边的文件"):format(name),
    vim.log.levels.WARN,
    { title = "Windows 盘上的文件" }
  )
end
vim.api.nvim_create_autocmd("BufReadPost", {
  callback = function(ev) warn_windows_drive(ev.buf) end,
})
for _, b in ipairs(vim.api.nvim_list_bufs()) do
  if vim.api.nvim_buf_is_loaded(b) then warn_windows_drive(b) end
end
