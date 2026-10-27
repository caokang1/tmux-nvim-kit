-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local opt = vim.opt

-- 用 "nvim 某目录" 启动时把工作目录切到该目录（否则仍停在启动时的 shell 目录，
-- 最近文件、搜索、文件树都会以那个目录为准）
local arg = vim.fn.argv(0)
if type(arg) == "string" and arg ~= "" and vim.fn.isdirectory(arg) == 1 then
  vim.fn.chdir(arg)
end

-- 看代码习惯：绝对行号、上下多留几行、长行不折
opt.relativenumber = false
opt.scrolloff = 8
opt.wrap = false

-- 拼写检查跳过中日韩文字（否则中文全被标成拼写错误），只检查英文，和 IDEA 的 Typo 检查一样
opt.spelllang = { "en", "cjk" }

-- 不用的插件宿主，关掉以免 checkhealth 报错、加快启动
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_node_provider = 0
vim.g.loaded_python3_provider = 0

-- 复制走 OSC 52：在 Windows Terminal 和浏览器(ttyd)里 y 复制的内容都会进入本机剪贴板
-- 粘贴用 Neovim 自己的寄存器（OSC 52 读取剪贴板大多数终端不支持，会卡住）
local osc52 = require("vim.ui.clipboard.osc52")
local function paste()
  return { vim.fn.split(vim.fn.getreg(""), "\n"), vim.fn.getregtype("") }
end
vim.g.clipboard = {
  name = "OSC 52",
  copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
  paste = { ["+"] = paste, ["*"] = paste },
}

-- 右键不弹 Neovim 自己的菜单（浏览器里会和浏览器右键菜单冲突），右键改为扩展选区
opt.mousemodel = "extend"
