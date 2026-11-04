-- Ctrl+B（跳转到声明）的提供者登记表：和 IDEA 一样，不同场景下 Ctrl+B 有不同含义
--   MyBatis Mapper ↔ XML、配置项 ↔ @Value、在声明处按 Ctrl+B 显示用法……
-- 用法：require("config.kit.goto").register("名字", fn, 优先级)
--   fn() 处理了就返回 true（例如已经跳转或弹出列表），不处理返回 false/nil；优先级数字小的先问，默认 50
local M = { providers = {} }

function M.register(name, fn, priority)
  for i, p in ipairs(M.providers) do
    if p.name == name then table.remove(M.providers, i) break end
  end
  table.insert(M.providers, { name = name, fn = fn, priority = priority or 50 })
  table.sort(M.providers, function(a, b) return a.priority < b.priority end)
end

-- 依次询问各提供者；某个提供者出错时提示并继续问下一个
function M.run()
  for _, p in ipairs(M.providers) do
    local ok, handled = pcall(p.fn)
    if not ok then
      vim.notify("跳转（" .. p.name .. "）出错：" .. tostring(handled), vim.log.levels.WARN)
    elseif handled then
      return true
    end
  end
  return false
end

return M
