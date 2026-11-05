-- 到处搜索（config/kit/everywhere.lua）的"符号"分类要能按名字搜到项目里的方法：
-- jdtls 默认的工作区符号搜索只返回类型，打开这个设置后也返回项目源码里的方法声明（不含依赖库，不影响速度）
return {
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      opts.settings = vim.tbl_deep_extend("force", opts.settings or {}, {
        java = { symbols = { includeSourceMethodDeclarations = true } },
      })
    end,
  },
}
