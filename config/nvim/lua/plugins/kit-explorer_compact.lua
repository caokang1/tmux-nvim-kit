-- 文件树压缩空包（config/kit/explorer_compact.lua）：替换 explorer 的 finder / 显示 / 折叠动作为包装后的版本，
-- 关闭开关（空格 u P）时这些包装直接调用 snacks 原来的实现
return {
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          explorer = {
            finder = function(opts, ctx)
              return require("config.kit.explorer_compact").finder(opts, ctx)
            end,
            format = function(item, picker)
              return require("config.kit.explorer_compact").format(item, picker)
            end,
            actions = {
              explorer_close = function(picker, item)
                return require("config.kit.explorer_compact").explorer_close(picker, item)
              end,
            },
          },
        },
      },
    },
  },
}
