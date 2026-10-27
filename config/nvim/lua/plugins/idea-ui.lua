-- 让界面行为接近 IDEA
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        -- 不在行尾显示提示文字，只保留波浪线和行号旁的图标；光标停留或按 <leader>cd 查看详情（IDEA 是悬停显示）
        virtual_text = false,
        float = { border = "rounded" },
      },
    },
  },
  -- 顶部一直显示文件标签栏，和 IDEA 的编辑器标签页一样
  {
    "akinsho/bufferline.nvim",
    opts = { options = { always_show_bufferline = true } },
  },
}
