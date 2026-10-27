-- 跳转类弹框（跳转到定义 / 实现 / 类型、查找用法、调用层级）：上面是结果列表，下面是几乎全屏的代码预览，
-- 默认的左右布局里预览只有半屏宽，长代码行看不全
local peek = {
  layout = {
    backdrop = false,
    width = 0.96,
    min_width = 80,
    height = 0.92,
    min_height = 20,
    box = "vertical",
    border = "rounded",
    title = "{title} {live} {flags}",
    title_pos = "center",
    { win = "input", height = 1, border = "bottom" },
    { win = "list", height = 7, border = "bottom" },
    { win = "preview", title = "{preview}", border = "none" },
  },
}

local titles = {
  lsp_definitions = "跳转到定义",
  lsp_declarations = "跳转到声明",
  lsp_implementations = "跳转到实现",
  lsp_type_definitions = "跳转到类型声明",
  lsp_references = "查找用法",
  lsp_incoming_calls = "调用层级：谁调用了它",
  lsp_outgoing_calls = "调用层级：它调用了谁",
}

local sources = {}
for name, title in pairs(titles) do
  sources[name] = {
    title = title,
    layout = peek,
    -- 预览里显示行号，超长的行折到下一行显示（保持缩进），目标行上下至少保留 8 行代码
    win = {
      preview = {
        wo = { number = true, relativenumber = false, scrolloff = 8, wrap = true, breakindent = true, linebreak = true },
      },
    },
  }
end

return {
  {
    "folke/snacks.nvim",
    opts = { picker = { sources = sources } },
  },
}
