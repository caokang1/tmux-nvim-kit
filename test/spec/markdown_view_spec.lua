-- Markdown 阅读：链接解析与跳转、锚点、标题大纲
local md = function() return require("config.kit.markdown_view") end

return {
  ["1 锚点按 GitHub 规则计算"] = function(t)
    local slug = md().slug
    t.eq(slug("安装"), "安装")
    t.eq(slug("Hello World"), "hello-world")
    t.eq(slug("Spring Boot 2.4 配置！"), "spring-boot-24-配置")
    t.eq(slug("API: getUser(id)"), "api-getuserid")
    t.eq(slug("中文（括号）、标点。"), "中文括号标点")
    t.eq(slug("snake_case and-dash"), "snake_case-and-dash")
    t.eq(slug("[链接](http://x) 标题"), "链接-标题")
  end,

  ["2 光标下的链接解析"] = function(t)
    local m = md()
    local line = "- [安装说明](docs/guide.md#安装) 和 <https://a.com> 以及 https://b.com/x."
    t.eq(m.link_at(line, 4), "docs/guide.md#安装")
    t.eq(m.link_at(line, 1), nil, "列表符号不是链接")
    local c = line:find("<https") -- 1 基
    t.eq(m.link_at(line, c), "https://a.com")
    c = line:find("https://b")
    t.eq(m.link_at(line, c + 3), "https://b.com/x")
    t.eq(m.link_at("![图](img/a.png \"标题\")", 0), "img/a.png")
    t.eq(m.resolve("https://spring.io", "/x").kind, "url")
    t.eq(m.resolve("#接口", "/x"), { kind = "anchor", anchor = "接口" })
    t.eq(m.resolve("docs/guide.md#安装", "/p"), { kind = "file", path = "/p/docs/guide.md", anchor = "安装" })
    t.eq(m.resolve("../README.md", "/p/docs"), { kind = "file", path = "/p/README.md" })
    t.eq(m.resolve("a%20b.md", "/p").path, "/p/a b.md")
  end,

  ["3 引用式链接"] = function(t)
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "看 [指南][g] 和 [Guide][]", "", "[g]: docs/guide.md", "[guide]: <docs/x.md>" })
    local m = md()
    t.eq(m.link_at("看 [指南][g] 和 [Guide][]", 6, buf), "docs/guide.md")
    local l = "看 [指南][g] 和 [Guide][]"
    t.eq(m.link_at(l, l:find("Guide"), buf), "docs/x.md")
    t.eq(m.link_at("[g]: docs/guide.md", 8, buf), "docs/guide.md")
    vim.api.nvim_buf_delete(buf, { force = true })
  end,

  ["4 README 里打开 文件#锚点、#锚点、网址"] = function(t)
    local readme = t.open("README.md")
    t.eq(vim.bo.filetype, "markdown")
    -- 文件.md#锚点：跳到 guide.md 的 "## 安装" 行
    t.cursor_at("%[安装说明%]")
    t.ok(require("config.kit.goto").run(), "Ctrl+B 没有处理 markdown 链接")
    t.ok(vim.api.nvim_buf_get_name(0):match("docs/guide%.md$"), "没有打开 guide.md：" .. vim.api.nvim_buf_get_name(0))
    t.eq(vim.api.nvim_get_current_line(), "## 安装")
    -- Ctrl+Alt+← 能回到 README
    vim.cmd([[execute "normal! \<C-o>"]])
    t.eq(vim.api.nvim_get_current_buf(), readme)
    -- 回到首页（相对路径 ../README.md）
    -- #锚点：本文件的 "## 接口"
    t.cursor_at("本页的接口一节")
    t.ok(md().follow(), "#接口 没有处理")
    t.eq(vim.api.nvim_get_current_line(), "## 接口")
    vim.cmd([[execute "normal! \<C-o>"]])
    t.ok(vim.api.nvim_get_current_line():find("本页的接口一节"), "跳转前的位置没有记录")
    -- 网址交给 vim.ui.open
    local opened
    local orig = vim.ui.open
    vim.ui.open = function(u) opened = u end
    t.cursor_at("Spring 官网")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "mx", false)
    vim.ui.open = orig
    t.eq(opened, "https://spring.io")
    -- 不在链接上：goto 不处理，回车移到下一行
    t.cursor_at("示例项目")
    t.eq(md().follow(), false)
    t.eq(require("config.kit.goto").run(), false)
    local row = vim.api.nvim_win_get_cursor(0)[1]
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "mx", false)
    t.eq(vim.api.nvim_win_get_cursor(0)[1], row + 1)
  end,

  ["5 guide.md 里的 ../README.md 链接"] = function(t)
    t.open("docs/guide.md")
    t.cursor_at("%[首页%]")
    t.ok(md().follow())
    t.ok(vim.api.nvim_buf_get_name(0):match("demo/README%.md$"), "没有打开 README.md")
  end,

  ["6 标题和大纲弹框"] = function(t)
    local buf = t.open("docs/guide.md")
    local hs = md().headings(buf)
    t.eq(vim.tbl_map(function(h) return { h.level, h.text, h.lnum, h.anchor } end, hs), {
      { 1, "指南", 1, "指南" }, { 2, "安装", 3, "安装" }, { 2, "运行", 7, "运行" },
    })
    t.ok(vim.fn.maparg("<C-F12>", "n", false, true).buffer == 1, "Ctrl+F12 不是 markdown 专用映射")
    t.ok(vim.fn.maparg("<M-7>", "n", false, true).buffer == 1, "Alt+7 不是 markdown 专用映射")
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    local picker = md().outline()
    t.ok(picker, "大纲没有打开")
    t.wait(3000, function() return #picker:items() == 3 end, "大纲条目")
    t.eq(picker:items()[2].text, "安装")
    t.eq(picker:current().text, "安装", "默认没有选中光标所在的一节")
    picker:action("confirm")
    t.wait(2000, function() return vim.bo.filetype == "markdown" and vim.api.nvim_win_get_cursor(0)[1] == 3 end, "跳到标题")
  end,
}
