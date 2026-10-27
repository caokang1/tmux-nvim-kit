-- 减少干扰：jdtls 导入时的进度刷屏不再弹出、通知改到右下角（右上角是 Ctrl+F 查找栏的位置）
return {
  {
    "folke/noice.nvim",
    opts = function(_, opts)
      opts.routes = opts.routes or {}
      -- jdtls 导入项目时每个模块都会输出一条 "xx% Starting Java Language Server - ..."，一次上百条；
      -- 状态栏已有"项目导入中 xx%"，这些直接丢弃
      table.insert(opts.routes, 1, {
        filter = {
          event = "msg_show",
          any = {
            { find = "Starting Java Language Server" },
            { find = "^Init%.%.%.$" },
            { find = "ServiceReady" },
          },
        },
        opts = { skip = true },
      })
    end,
  },
  {
    "folke/snacks.nvim",
    opts = {
      -- 通知从右下角往上堆叠，不挡住右上角的查找栏
      notifier = { top_down = false },
    },
  },
}
