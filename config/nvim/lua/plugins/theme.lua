-- IDEA Islands Dark / Dark 配色：在 tokyonight 基础上替换调色板和语法高亮，
-- 这样文件树、搜索框、标签栏、状态栏等插件界面会跟着一起换色

-- IntelliJ IDEA Dark 编辑器配色
local idea = {
  bg = "#1E1F22", -- 编辑器背景
  panel = "#2B2D30", -- 工具窗口、弹窗背景
  panel_dark = "#191A1C",
  line = "#26282E", -- 当前行
  border = "#393B40",
  selection = "#214283",
  search = "#2D543F",
  fg = "#BCBEC4", -- 默认文字
  fg_dim = "#868A91",
  gutter = "#4B5059", -- 行号
  gutter_active = "#A1A3AB",
  comment = "#7A7E85",
  doc = "#5F826B", -- 文档注释
  doc_tag = "#67A37C",
  keyword = "#CF8E6D", -- 关键字（橙）
  string = "#6AAB73", -- 字符串（绿）
  number = "#2AACB8", -- 数字（青）
  func = "#56A8F5", -- 方法声明（蓝）
  field = "#C77DBB", -- 字段/常量（紫）
  annotation = "#B3AE60", -- 注解（土黄）
  type_param = "#16BAAC",
  tag = "#D5B778", -- XML/HTML 标签
  accent = "#3574F0", -- IDEA 强调蓝
  error = "#F75464",
  warning = "#F2C55C",
  info = "#3592C4",
  git_add = "#549159",
  git_change = "#375FAD",
  git_delete = "#868A91",
}

return {
  {
    "folke/tokyonight.nvim",
    opts = {
      style = "night",
      styles = { comments = { italic = false }, keywords = { italic = false } },
      on_colors = function(c)
        c.bg = idea.bg
        c.bg_dark = idea.panel_dark
        c.bg_dark1 = idea.panel_dark
        c.bg_float = idea.panel
        c.bg_popup = idea.panel
        c.bg_sidebar = idea.bg
        c.bg_statusline = idea.panel
        c.bg_highlight = idea.line
        c.bg_visual = idea.selection
        c.bg_search = idea.search
        c.border = idea.border
        c.border_highlight = idea.accent
        c.fg = idea.fg
        c.fg_dark = idea.fg_dim
        c.fg_float = idea.fg
        c.fg_sidebar = idea.fg
        c.fg_gutter = idea.gutter
        c.comment = idea.comment
        c.dark3 = idea.gutter
        c.dark5 = idea.fg_dim
        c.blue = idea.func
        c.blue1 = idea.accent
        c.cyan = idea.number
        c.green = idea.string
        c.green1 = idea.type_param
        c.orange = idea.keyword
        c.yellow = idea.annotation
        c.purple = idea.field
        c.magenta = idea.field
        c.red = idea.error
        c.red1 = idea.error
        c.error = idea.error
        c.warning = idea.warning
        c.info = idea.info
        c.hint = idea.doc
        c.git = { add = idea.git_add, change = idea.git_change, delete = idea.git_delete, ignore = idea.gutter }
        c.diff = { add = "#294436", change = "#25324D", delete = "#484A4A", text = "#385570" }
      end,
      on_highlights = function(hl)
        local i = idea
        local function set(groups, spec)
          for _, g in ipairs(groups) do hl[g] = spec end
        end

        -- 编辑器界面
        hl.Normal = { fg = i.fg, bg = i.bg }
        hl.CursorLine = { bg = i.line }
        hl.LineNr = { fg = i.gutter }
        hl.CursorLineNr = { fg = i.gutter_active }
        hl.MatchParen = { bg = "#43454A", bold = true }
        hl.Visual = { bg = i.selection }
        hl.Search = { bg = i.search }
        hl.IncSearch = { bg = "#3D7A50", fg = "#FFFFFF" }
        hl.CurSearch = hl.IncSearch
        hl.WinSeparator = { fg = i.border }
        hl.FloatBorder = { fg = i.border, bg = i.panel }
        hl.Pmenu = { fg = i.fg, bg = i.panel }
        hl.PmenuSel = { bg = "#2E436E" }
        set({ "LspReferenceText", "LspReferenceRead" }, { bg = "#373B39" })
        hl.LspReferenceWrite = { bg = "#40332B" }
        hl.LspInlayHint = { fg = "#8C8C8C", bg = "#2B2D30" }
        hl.LspCodeLens = { fg = "#868A91", italic = true }
        hl.NonText = { fg = "#313438" }
        hl.SnacksIndent = { fg = "#313438" }
        hl.SnacksIndentScope = { fg = "#4B5059" }
        hl.TreesitterContext = { bg = i.panel }
        hl.TreesitterContextBottom = { underline = true, sp = i.border }
        hl.BufferLineIndicatorSelected = { fg = i.accent }
        hl.RenderMarkdownTableHead = { fg = i.gutter }
        hl.RenderMarkdownTableRow = { fg = i.gutter }
        hl.RenderMarkdownCode = { bg = i.panel }

        -- 通用语法
        set({ "Comment", "@comment" }, { fg = i.comment })
        set({ "@comment.documentation", "@string.documentation" }, { fg = i.doc, italic = true })
        set({ "Keyword", "Statement", "Conditional", "Repeat", "Exception", "Include", "StorageClass",
          "Structure", "PreProc", "Define", "@keyword", "@keyword.return", "@keyword.function",
          "@keyword.import", "@keyword.modifier", "@keyword.type", "@keyword.operator",
          "@keyword.conditional", "@keyword.repeat", "@keyword.exception", "@keyword.coroutine",
          "@keyword.directive", "@variable.builtin", "@constant.builtin", "@boolean", "Boolean",
          "@type.builtin" }, { fg = i.keyword })
        set({ "String", "Character", "@string", "@character" }, { fg = i.string })
        set({ "@string.escape", "SpecialChar", "@string.special" }, { fg = i.keyword })
        set({ "@string.regexp" }, { fg = i.string })
        set({ "Number", "Float", "@number", "@number.float" }, { fg = i.number })
        set({ "Function", "@function", "@function.method", "@constructor" }, { fg = i.func })
        set({ "@function.call", "@function.method.call", "@function.builtin" }, { fg = i.fg })
        set({ "Identifier", "@variable", "@variable.parameter", "@module", "@label", "Type", "Typedef",
          "@type", "@type.definition", "Operator", "@operator", "Delimiter", "@punctuation",
          "@punctuation.bracket", "@punctuation.delimiter", "@punctuation.special" }, { fg = i.fg })
        set({ "@variable.member", "@property", "@field" }, { fg = i.field })
        set({ "Constant", "@constant" }, { fg = i.field, italic = true })
        set({ "@attribute", "@attribute.builtin" }, { fg = i.annotation })
        set({ "Todo", "@comment.todo" }, { fg = "#8BB33D", bold = true, italic = true })

        -- XML / HTML（pom.xml、mybatis mapper 等）
        set({ "Tag", "@tag", "@tag.builtin", "@tag.delimiter" }, { fg = i.tag })
        hl["@tag.attribute"] = { fg = i.fg }
        set({ "@string.xml", "@string.html" }, { fg = i.string })

        -- YAML / properties / TOML 的键用橙色，JSON 的键用紫色（与 IDEA 一致）
        set({ "@property.yaml", "@property.properties", "@property.toml", "@variable.member.yaml",
          "@property.ini" }, { fg = i.keyword })
        set({ "@property.json", "@property.jsonc", "@property.json5" }, { fg = i.field })

        -- Java 语义高亮（由 jdtls 提供，优先级高于语法树）
        set({ "@lsp.type.class", "@lsp.type.interface", "@lsp.type.enum", "@lsp.type.record",
          "@lsp.type.namespace", "@lsp.type.parameter", "@lsp.type.variable", "@lsp.type.method",
          "@lsp.type.type" }, { fg = i.fg })
        hl["@lsp.typemod.method.declaration"] = { fg = i.func }
        hl["@lsp.typemod.method.static"] = { fg = i.fg, italic = true }
        hl["@lsp.typemod.method.static.declaration"] = { fg = i.func, italic = true }
        hl["@lsp.type.property"] = { fg = i.field }
        hl["@lsp.typemod.property.static"] = { fg = i.field, italic = true }
        hl["@lsp.type.enumMember"] = { fg = i.field, italic = true }
        hl["@lsp.type.annotation"] = { fg = i.annotation }
        hl["@lsp.type.annotationMember"] = { fg = i.fg }
        hl["@lsp.type.typeParameter"] = { fg = i.type_param }
        hl["@lsp.type.keyword"] = { fg = i.keyword }
        hl["@lsp.type.modifier"] = { fg = i.keyword }
        hl["@lsp.mod.deprecated"] = { strikethrough = true }

        -- 文件树（Snacks explorer）：底色与编辑器一致，选中行用 IDEA 的蓝，git 状态颜色与 IDEA 一致
        hl.SnacksPickerTree = { fg = "#313438" } -- 缩进竖线，淡一些
        hl.SnacksPickerInputBorder = { fg = i.border }
        hl.SnacksPickerInputTitle = { fg = i.fg, bold = true }
        hl.SnacksPickerTitle = { fg = i.fg, bold = true }
        hl.SnacksPickerPrompt = { fg = i.accent }
        hl.SnacksPickerDirectory = { fg = i.fg }
        hl.SnacksPickerPathHidden = { fg = i.fg_dim }
        hl.SnacksPickerPathIgnored = { fg = "#848504" }
        hl.SnacksPickerListCursorLine = { bg = "#2E436E" }
        hl.SnacksPickerGitStatusModified = { fg = "#6897BB" }
        hl.SnacksPickerGitStatusRenamed = { fg = "#6897BB" }
        hl.SnacksPickerGitStatusAdded = { fg = "#629755" }
        hl.SnacksPickerGitStatusStaged = { fg = "#629755" }
        hl.SnacksPickerGitStatusUntracked = { fg = "#D1675A" }
        hl.SnacksPickerGitStatusIgnored = { fg = "#848504" }
        hl.SnacksPickerGitStatusDeleted = { fg = "#6C6C6C" }
        hl.SnacksPickerGitStatusUnmerged = { fg = "#D5756C" }

        -- 诊断（报错、警告下划线）
        hl.DiagnosticUnderlineError = { undercurl = true, sp = i.error }
        hl.DiagnosticUnderlineWarn = { undercurl = true, sp = i.warning }
        hl.DiagnosticUnnecessary = { fg = i.fg_dim }
        -- 拼写错误：IDEA 的 Typo 是淡绿色波浪线
        hl.SpellBad = { undercurl = true, sp = i.doc }
        hl.SpellCap = { undercurl = true, sp = i.doc }
        hl.SpellLocal = {}
        hl.SpellRare = {}
      end,
    },
  },
  { "LazyVim/LazyVim", opts = { colorscheme = "tokyonight-night" } },
}
