-- 各类文件的语法高亮与语言服务，尽量覆盖 IDEA 里常见的文件
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "java", "kotlin", "groovy", "xml", "yaml", "json", "json5", "toml", "properties", "ini",
        "sql", "bash", "dockerfile", "make", "proto", "nginx", "csv", "diff",
        "html", "css", "scss", "javascript", "typescript", "tsx", "vue",
        "python", "go", "lua", "vim", "vimdoc", "regex",
        "markdown", "markdown_inline", "git_config", "gitcommit", "gitignore", "git_rebase",
      },
    },
  },
  {
    "neovim/nvim-lspconfig",
    opts = {
      -- 方法上方显示 "N references" 等提示，类似 IDEA 的 usages
      codelens = { enabled = true },
      inlay_hints = { enabled = true },
      servers = {
        lemminx = {}, -- XML：pom.xml、MyBatis mapper、Spring 配置
        bashls = {},
      },
    },
  },
}
