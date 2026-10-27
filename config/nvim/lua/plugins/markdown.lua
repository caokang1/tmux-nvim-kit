return {
  -- 在编辑器里直接渲染 Markdown（标题、表格、代码块、列表、勾选框等），不显示源码标记
  {
    "MeanderingProgrammer/render-markdown.nvim",
    ft = { "markdown" },
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-mini/mini.icons" },
    opts = {
      -- 普通、命令行、终端模式下都保持渲染；只有进入插入模式编辑时才显示源码
      render_modes = { "n", "c", "t" },
      -- 光标所在行也不还原成源码
      anti_conceal = { enabled = false },
      heading = { sign = false, width = "block", left_pad = 1, right_pad = 2 },
      code = { sign = false, width = "block", left_pad = 2, right_pad = 4, border = "thick" },
      pipe_table = { preset = "round" },
      checkbox = { enabled = true },
    },
    keys = {
      { "<leader>um", "<cmd>RenderMarkdown toggle<cr>", desc = "切换 Markdown 渲染/源码", ft = "markdown" },
    },
  },
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "markdown", "markdown_inline", "html", "latex", "yaml" } },
  },
}
