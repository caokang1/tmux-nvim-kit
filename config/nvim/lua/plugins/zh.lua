-- 中文化：which-key 弹出菜单里的快捷键说明显示为中文，并提供 空格 h / F1 中文帮助面板
return {
  {
    "folke/which-key.nvim",
    opts = function(_, opts)
      opts.replace = opts.replace or {}
      -- 保留 which-key 默认的清理规则，最后再做中文替换
      opts.replace.desc = opts.replace.desc
        or {
          { "<Plug>%(?(.*)%)?", "%1" },
          { "^%+", "" },
          { "<[cC]md>", "" },
          { "<[cC][rR]>", "" },
          { "<[sS]ilent>", "" },
          { "^lua%s+", "" },
          { "^call%s+", "" },
          { "^:%s*", "" },
        }
      table.insert(opts.replace.desc, function(desc)
        return require("config.zh").translate(desc)
      end)
      -- 底部英文提示（close / back / scroll）换成边框上的中文提示
      opts.show_help = false
      opts.win = opts.win or {}
      opts.win.footer = " Esc 关闭 · Backspace 返回上一级 · Ctrl+d/u 翻页 "
      opts.win.footer_pos = "center"
    end,
  },
  {
    "folke/snacks.nvim",
    keys = {
      { "<leader>h", function() require("config.zh_help").open() end, desc = "中文帮助（当前窗口常用操作）" },
      { "<F1>", function() vim.cmd("stopinsert") require("config.zh_help").open() end, mode = { "n", "i" }, desc = "中文帮助（当前窗口常用操作）" },
    },
  },
}
