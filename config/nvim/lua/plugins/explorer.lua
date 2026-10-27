-- 文件树：LazyVim 默认的 Snacks explorer，只做外观和操作上的小调整
return {
  {
    "folke/snacks.nvim",
    keys = {
      -- 和 IDEA 一样用 Alt+1 打开/关闭文件树（空格 e 也可以）
      { "<M-1>", function() Snacks.explorer() end, desc = "文件树 (Alt+1)" },
    },
    opts = {
      picker = {
        sources = {
          explorer = {
            hidden = true, -- 显示 .gitignore 等点文件
            ignored = true, -- 显示 target/ 等被 git 忽略的目录（灰黄色）
            exclude = { ".git", ".project", ".classpath", ".settings", ".factorypath" },
            follow_file = true, -- 打开文件时自动定位到它
            layout = { layout = { width = 42, position = "left" } },
            win = {
              list = {
                keys = {
                  -- 和 IDEA 一样：回车打开，左右方向键折叠/展开
                  ["<Right>"] = "confirm",
                  ["<Left>"] = "explorer_close",
                },
              },
            },
          },
        },
      },
    },
  },
}
