-- 让出被 IDEA 快捷键占用的插件按键（实际映射在 config/idea_keys.lua）
return {
  -- noice 用 Ctrl+F / Ctrl+B 滚动文档弹窗，和 IDEA 的查找 / 跳转到声明冲突
  {
    "folke/noice.nvim",
    keys = {
      { "<c-f>", false, mode = { "i", "n", "s" } },
      { "<c-b>", false, mode = { "i", "n", "s" } },
    },
  },
  -- LSP 自带的 Alt+N / Alt+P（下一个 / 上一个引用）和 输入模式 Ctrl+K（参数提示）
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        ["*"] = {
          keys = {
            { "<a-n>", false },
            { "<a-p>", false },
            { "<c-k>", false, mode = "i" },
          },
        },
      },
    },
  },
  -- 搜索框（文件树过滤、查找文件、全局搜索等）里输入时 Ctrl+V 粘贴，和 IDEA 一样；
  -- 原来的"在左右分屏中打开"仍可在结果列表里按 Ctrl+V 使用。
  -- 粘贴的是在编辑器里复制的内容；Windows Terminal 和浏览器里 Ctrl+V 由终端直接粘贴系统剪贴板，不经过这里
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        win = {
          input = {
            keys = {
              ["<c-v>"] = {
                function()
                  local text = vim.fn.getreg('"'):gsub("\r?\n", " ")
                  vim.api.nvim_paste(vim.trim(text), true, -1)
                end,
                mode = "i",
                desc = "粘贴",
              },
            },
          },
        },
      },
    },
  },
}
