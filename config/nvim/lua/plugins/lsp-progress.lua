-- jdtls 导入项目时的进度（Refreshing Maven model、Initialize Workspace 等）
-- 不再在右下角弹出多行提示，改为状态栏一个简短的 "项目导入中 49%"，导入完成后自动消失
-- 导入期间跳转定义、查找引用可能还不完整，看到这个提示时稍等即可
local busy = {} ---@type table<string, integer>

vim.api.nvim_create_autocmd("LspProgress", {
  callback = function(ev)
    local params = ev.data and ev.data.params
    local value = params and params.value
    if type(value) ~= "table" then
      return
    end
    local id = ev.data.client_id .. ":" .. tostring(params.token)
    if value.kind == "end" then
      busy[id] = nil
    else
      busy[id] = value.percentage or busy[id] or 0
    end
    vim.cmd.redrawstatus()
  end,
})

local function progress()
  local n, pct = 0, 0
  for _, p in pairs(busy) do
    n = n + 1
    pct = math.max(pct, p)
  end
  if n == 0 then
    return ""
  end
  return "󰔟 项目导入中 " .. pct .. "%"
end

return {
  {
    "folke/noice.nvim",
    opts = {
      lsp = { progress = { enabled = false } },
    },
  },
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      table.insert(opts.sections.lualine_x, 1, {
        progress,
        cond = function() return next(busy) ~= nil end,
        color = { fg = "#E0AF68" },
      })
    end,
  },
}
