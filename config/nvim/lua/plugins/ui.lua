return {
  {
    "folke/snacks.nvim",
    opts = {
      -- 终端里不显示图片，关掉以免 checkhealth 报一堆缺工具的错误
      image = { enabled = false },
    },
  },

  -- 状态栏显示文件相对项目根目录的路径，多项目分屏时一眼能看出是哪个文件
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      opts.options.component_separators = { left = "│", right = "│" }
      opts.options.section_separators = { left = "", right = "" }
    end,
  },
}
