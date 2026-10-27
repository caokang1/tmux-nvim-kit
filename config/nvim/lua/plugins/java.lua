return {
  {
    "mfussenegger/nvim-jdtls",
    opts = function(_, opts)
      -- 大项目给 jdtls 更多内存（本机 19G 内存）
      opts.cmd = opts.cmd or { vim.fn.exepath("jdtls") }
      table.insert(opts.cmd, "--jvm-arg=-Xmx4g")
      -- 元数据（.project/.classpath/.settings）放到 jdtls 工作区，不写进项目目录；
      -- 必须作为 JVM 参数传入（VS Code Java 插件也是这么做的），只放在 settings 里不生效
      table.insert(opts.cmd, "--jvm-arg=-Djava.import.generatesMetadataFilesAtProjectRoot=false")

      -- 像 IDEA 一样：跳进依赖库时下载源码，没有源码就反编译
      opts.settings = vim.tbl_deep_extend("force", opts.settings or {}, {
        java = {
          -- 不在项目根目录生成 .project/.classpath/.settings（Eclipse 元数据），保持项目干净
          import = { generatesMetadataFilesAtProjectRoot = false },
          maven = { downloadSources = true },
          eclipse = { downloadSources = true },
          references = { includeDecompiledSources = true },
          contentProvider = { preferred = "fernflower" },
          implementationsCodeLens = { enabled = true },
          referencesCodeLens = { enabled = true },
        },
      })

      -- 设置同时放进启动参数：导入项目发生在启动阶段，只靠事后下发的 settings 来不及，
      -- 否则 generatesMetadataFilesAtProjectRoot 等导入相关设置不生效
      local user_jdtls = opts.jdtls
      opts.jdtls = function(config)
        if type(user_jdtls) == "function" then
          config = user_jdtls(config) or config
        end
        config.init_options = config.init_options or {}
        config.init_options.settings = config.settings
        return config
      end
    end,
  },
}
