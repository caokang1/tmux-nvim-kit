-- 加载 config/kit/ 下的所有功能模块（按文件名排序）。每个模块自己注册按键、自动命令；
-- 某个模块出错只提示，不影响其他模块和编辑器启动
local dir = vim.fn.stdpath("config") .. "/lua/config/kit"
local skip = { init = true, ["goto"] = true }
local names = {}
for name, type in vim.fs.dir(dir) do
  local mod = name:match("^(.+)%.lua$")
  if type == "file" and mod and not skip[mod] then names[#names + 1] = mod end
end
table.sort(names)
for _, mod in ipairs(names) do
  local ok, err = pcall(require, "config.kit." .. mod)
  if not ok then
    vim.notify("加载 config/kit/" .. mod .. ".lua 出错：\n" .. tostring(err), vim.log.levels.ERROR)
  end
end
