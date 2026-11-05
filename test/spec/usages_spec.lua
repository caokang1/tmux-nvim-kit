-- 查找用法面板 / 类型层级 / 调用层级
local function U() return require("config.kit.usages") end
local function H() return require("config.kit.hierarchy") end
local Tree = function() return require("config.kit.tree") end

local function labels(nodes)
  local r = {}
  for _, n in ipairs(nodes or {}) do r[#r + 1] = n.label or (n.item and n.item.name) end
  return r
end

local function find_line(buf, pat)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if l:find(pat, 1, true) then return i, l end
  end
end

-- 调用异步函数 f(cb) 并等待 cb 被调用
local function await(t, f, msg)
  local res
  f(function(p) res = p end)
  t.wait(60000, function() return res ~= nil end, msg)
  return res
end

local function code_win_of(p)
  return p:code_win()
end

return {
  ["1 读写判断"] = function(t)
    local a = U().access_kind
    local function k(line, word)
      local s = line:find(word, 1, true) - 1
      return a(line, s, s + #word)
    end
    t.eq(k("    counter++;", "counter"), "write")
    t.eq(k("    ++counter;", "counter"), "write")
    t.eq(k("    this.counter = 1;", "counter"), "write")
    t.eq(k("    counter += 2;", "counter"), "write")
    t.eq(k("    counter >>>= 2;", "counter"), "write")
    t.eq(k("    if (counter == 1) {", "counter"), "read")
    t.eq(k("    if (counter <= 1) {", "counter"), "read")
    t.eq(k("    if (counter != 1) {", "counter"), "read")
    t.eq(k('    audit("list " + counter);', "counter"), "read")
  end,

  ["2 调用层级节点文字"] = function(t)
    local l, pkg = H().call_label({ name = "detail(Long) : User", detail = "com.example.demo.controller.UserController" })
    t.eq(l, "UserController.detail(Long)")
    t.eq(pkg, "com.example.demo.controller")
    t.eq(U().parse_jdt("jdt://contents/rt.jar/java.util/ArrayList.class?=x"), { jar = "rt.jar", package = "java.util", class = "ArrayList.class" })
    t.eq(U().module_of(t.fixture .. "/demo-app/src/main/java/com/example/demo/DemoApplication.java"), "demo-app")
    t.eq(U().module_of(t.fixture .. "/demo-common/src/main/java/com/example/common/ApiConst.java"), "demo-common")
  end,

  ["3 按键已映射"] = function(t)
    t.ok(vim.fn.maparg("<M-F7>", "n", false, true).desc:find("面板"), "Alt+F7")
    t.ok(vim.fn.maparg("<C-M-F7>", "n", false, true).desc:find("弹框"), "Ctrl+Alt+F7")
    t.ok(vim.fn.maparg("<C-M-Down>", "n") ~= "", "Ctrl+Alt+↓")
    t.ok(vim.fn.maparg("<C-M-Up>", "n") ~= "", "Ctrl+Alt+↑")
    t.ok(vim.fn.maparg("<C-h>", "n", false, true).desc:find("类型层级"), "Ctrl+H")
    t.ok(vim.fn.maparg("<C-M-h>", "n", false, true).desc:find("调用层级"), "Ctrl+Alt+H")
    t.ok(vim.fn.maparg("<M-BS>", "n", false, true).desc:find("调用层级"), "Alt+BS")
    t.eq(type(U().show_popup), "function")
  end,

  ["4 查找用法：getUser 分组树、面板内容、Enter 跳转"] = function(t)
    vim.cmd("only")
    t.open("demo-app/src/main/java/com/example/demo/service/UserService.java")
    t.wait_jdtls()
    t.cursor_at("getUser")
    local codewin = vim.api.nvim_get_current_win()
    local p = await(t, function(cb) U().find_usages(cb) end, "查找用法")
    local roots = p.roots
    t.eq(labels(roots), { "生产代码", "测试代码" })
    t.eq(labels(roots[1].children), { "demo-app" })
    t.eq(labels(roots[1].children[1].children), { "com.example.demo.controller" })
    local file = roots[1].children[1].children[1].children[1]
    t.eq(file.label, "UserController.java")
    t.eq(#file.children, 1)
    t.eq(file.children[1].item.lnum, 29)
    t.eq(labels(roots[2].children[1].children), { "com.example.demo.service.impl" })
    t.eq(roots[2].children[1].children[1].children[1].label, "UserServiceImplTest.java")
    t.eq(U().state.total, 2)
    -- 面板缓冲区内容
    t.eq(vim.bo[p.buf].filetype, "kit_tree")
    t.ok(vim.api.nvim_win_get_height(p.win) <= 13, "面板高度")
    t.ok(find_line(p.buf, "生产代码  1 处用法"), "生产代码分组行")
    t.ok(find_line(p.buf, "UserController.java"), "文件行")
    local l = find_line(p.buf, "return userService.getUser(id);")
    t.ok(l, "用法行")
    t.ok(vim.wo[p.win].winbar:find("查找用法：getUser"), "标题行：" .. vim.wo[p.win].winbar)
    t.ok(vim.wo[p.win].winbar:find("共 2 处"), "标题行显示总数")
    -- 光标初始在第一个用法上；Enter 跳转，面板保留，焦点在代码窗口
    t.eq(vim.api.nvim_win_get_cursor(p.win)[1], l)
    vim.api.nvim_set_current_win(p.win)
    vim.api.nvim_win_set_cursor(p.win, { l, 0 })
    vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)
    t.eq(vim.api.nvim_get_current_win(), codewin)
    t.ok(vim.api.nvim_buf_get_name(0):find("UserController.java$"), "跳到 UserController")
    t.eq(vim.api.nvim_win_get_cursor(0), { 29, 27 })
    t.ok(p:is_visible(), "面板保留")
  end,

  ["5 下一个/上一个用法（面板未聚焦）"] = function(t)
    local p = Tree().get("usages")
    -- 焦点在代码窗口：上一次 Enter 停在 UserController 的用法上
    vim.api.nvim_set_current_win(code_win_of(p))
    U().next(1)
    t.ok(vim.api.nvim_buf_get_name(0):find("UserServiceImplTest.java$"), "下一个是测试类")
    t.eq(vim.api.nvim_win_get_cursor(0), { 5, 30 })
    t.ok(p:cursor_node().item.file == "UserServiceImplTest.java", "面板光标跟随")
    t.ok(vim.api.nvim_get_current_win() ~= p.win, "焦点仍在代码窗口")
    U().next(-1)
    t.ok(vim.api.nvim_buf_get_name(0):find("UserController.java$"), "上一个是 Controller")
    -- 折叠分组后照样能跳，并自动展开
    local test_group = p.roots[2]
    p:collapse(test_group)
    vim.api.nvim_set_current_win(code_win_of(p))
    U().next(1)
    t.ok(test_group.expanded, "自动展开所在分组")
    t.ok(vim.api.nvim_buf_get_name(0):find("UserServiceImplTest.java$"), "跳到测试类")
    -- 预览（焦点留在面板）：代码窗口显示该处，之后进入代码窗口光标仍在该处
    vim.api.nvim_set_current_win(p.win)
    p:preview_node(p:occurrences()[1])
    t.eq(vim.api.nvim_get_current_win(), p.win)
    local cw = code_win_of(p)
    t.ok(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(cw)):find("UserController.java$"), "预览 Controller")
    vim.api.nvim_set_current_win(cw)
    t.eq(vim.api.nvim_win_get_cursor(0), { 29, 27 })
  end,

  ["6 字段读写：UserServiceImpl.counter"] = function(t)
    vim.cmd("only")
    t.open("demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java")
    t.cursor_at("counter;")
    local p = await(t, function(cb) U().find_usages(cb) end, "查找用法")
    local usages = p:occurrences()
    t.eq(#usages, 2)
    t.eq({ usages[1].item.lnum, usages[1].access }, { 26, "write" })
    t.eq({ usages[2].item.lnum, usages[2].access }, { 34, "read" })
    t.eq({ U().state.reads, U().state.writes }, { 1, 1 })
    t.ok(vim.wo[p.win].winbar:find("读 1，写 1"), "标题显示读写数")
    local _, line = find_line(p.buf, "counter++;")
    t.ok(line and line:find("写$"), "写标记：" .. tostring(line))
    -- 方法不区分读写
    t.ok(not U().is_variable_at(0, 24, 18), "getUser 不是变量")
  end,

  ["7 类型层级：子类型 / 父类型 / 完整层级"] = function(t)
    vim.cmd("only")
    t.open("demo-app/src/main/java/com/example/demo/service/UserService.java")
    t.cursor_at("UserService")
    local p = await(t, function(cb) H().type_hierarchy("sub", cb) end, "子类型")
    t.eq(labels(p.roots), { "UserService" })
    t.eq(labels(p.roots[1].children), { "AdminUserServiceImpl", "UserServiceImpl" })
    t.ok(find_line(p.buf, "AdminUserServiceImpl  com.example.demo.service.impl"), "面板行")
    t.ok(vim.wo[p.win].winbar:find("子类型"), "标题显示模式")

    t.open("demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java")
    t.cursor_at("UserServiceImpl")
    p = await(t, function(cb) H().type_hierarchy("super", cb) end, "父类型")
    t.eq(labels(p.roots[1].children), { "AbstractService", "UserService" })
    -- 父类型继续展开（懒加载）：AbstractService 的父类是 Object
    local abs = p.roots[1].children[1]
    local done
    p:expand(abs, function() done = true end)
    t.wait(30000, function() return done end, "展开 AbstractService")
    t.eq(labels(abs.children), { "Object" })

    -- 从代码窗口按 Ctrl+H
    vim.api.nvim_set_current_win(p:code_win())
    p = await(t, function(cb) H().type_hierarchy("full", cb) end, "完整层级")
    -- Object → AbstractService → UserServiceImpl
    t.eq(labels(p.roots), { "Object" })
    t.eq(labels(p.roots[1].children), { "AbstractService" })
    t.eq(labels(p.roots[1].children[1].children), { "UserServiceImpl" })
    t.eq(p:cursor_node().item.name, "UserServiceImpl")
    -- Enter 跳到 AbstractService
    vim.api.nvim_set_current_win(p.win)
    p:set_cursor(p.roots[1].children[1])
    p:activate()
    t.ok(vim.api.nvim_buf_get_name(0):find("AbstractService.java$"), "跳到 AbstractService")
    t.eq(vim.api.nvim_win_get_cursor(0), { 3, 22 })
  end,

  ["8 调用层级：getUser 谁调用了它 / 它调用了谁"] = function(t)
    vim.cmd("only")
    t.open("demo-app/src/main/java/com/example/demo/service/UserService.java")
    t.cursor_at("getUser")
    local p = await(t, function(cb) H().call_hierarchy("incoming", cb) end, "调用层级")
    local root = p.roots[1]
    t.eq(H().call_label(root.item), "UserService.getUser(Long)")
    local kids = {}
    for _, c in ipairs(root.children) do kids[#kids + 1] = (H().call_label(c.item)) end
    t.eq(kids, { "UserController.detail(Long)", "UserServiceImplTest.testGetUser()" })
    t.ok(find_line(p.buf, "UserController.detail(Long)  com.example.demo.controller"), "面板行")
    -- 下一层懒加载：detail 没有调用方 → 展开后没有子节点
    local done
    p:expand(root.children[1], function() done = true end)
    t.wait(30000, function() return done end, "展开 detail")
    t.eq(#root.children[1].children, 0)
    -- Enter 跳到调用处
    vim.api.nvim_set_current_win(p.win)
    p:set_cursor(root.children[1])
    vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)
    t.ok(vim.api.nvim_buf_get_name(0):find("UserController.java$"), "跳到调用处")
    t.eq(vim.api.nvim_win_get_cursor(0), { 29, 27 })

    -- 它调用了谁：UserServiceImpl.getUser 调用了 audit、selectById
    t.open("demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java")
    t.cursor_at("getUser")
    p = await(t, function(cb) H().call_hierarchy("outgoing", cb) end, "它调用了谁")
    local out = {}
    for _, c in ipairs(p.roots[1].children) do out[#out + 1] = (H().call_label(c.item)) end
    t.ok(vim.tbl_contains(out, "UserServiceImpl.audit(String)"), vim.inspect(out))
    t.ok(vim.tbl_contains(out, "UserMapper.selectById(Long)"), vim.inspect(out))
    t.ok(vim.wo[p.win].winbar:find("它调用了谁"), "标题显示方向")
    -- 预览一个还没打开过的文件（UserMapper.java），进入代码窗口后光标在方法声明处
    local mapper
    for _, c in ipairs(p.roots[1].children) do
      if c.item.name:find("selectById") then mapper = c end
    end
    vim.api.nvim_set_current_win(p.win)
    p:set_cursor(mapper)
    p:preview_node(mapper)
    t.eq(vim.api.nvim_get_current_win(), p.win)
    local cw = p:code_win()
    t.ok(vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(cw)):find("UserMapper.java$"), "预览 UserMapper")
    t.ok(not vim.bo[vim.api.nvim_win_get_buf(cw)].buflisted, "预览的文件不进标签栏")
    vim.wait(300)
    vim.api.nvim_set_current_win(cw)
    t.eq(vim.api.nvim_win_get_cursor(0), { mapper.loc.range.start.line + 1, mapper.loc.range.start.character })
  end,

  ["9 面板按键：折叠/展开/关闭"] = function(t)
    local p = Tree().get("call_hierarchy")
    vim.api.nvim_set_current_win(p.win)
    p:set_cursor(p.roots[1])
    vim.api.nvim_feedkeys("h", "x", false)
    t.ok(not p.roots[1].expanded, "h 折叠")
    t.eq(#vim.api.nvim_buf_get_lines(p.buf, 0, -1, false), 1)
    vim.api.nvim_feedkeys("l", "x", false)
    t.ok(p.roots[1].expanded, "l 展开")
    vim.api.nvim_feedkeys("p", "x", false)
    t.ok(not p.preview, "p 关闭预览")
    t.ok(vim.wo[p.win].winbar:find("预览:关"), "标题显示预览状态")
    vim.api.nvim_feedkeys("q", "x", false)
    t.ok(not p:is_visible(), "q 关闭面板")
  end,

  ["A 依赖库（jdt://）：在依赖库文件里查找用法、跳进依赖库"] = function(t)
    vim.cmd("only")
    t.open("demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java")
    t.cursor_at("ArrayList<>")
    local res = vim.lsp.buf_request_sync(0, "textDocument/definition", vim.lsp.util.make_position_params(0, "utf-16"), 30000)
    local loc
    for _, r in pairs(res or {}) do loc = r.result and (r.result[1] or r.result) end
    t.ok(loc and loc.uri:match("^jdt://"), "ArrayList 定义在 jdt://")
    local b = require("config.kit.tree").load_buf(loc.uri)
    vim.api.nvim_win_set_buf(0, b)
    t.wait(10000, function() return #vim.lsp.get_clients({ bufnr = b, name = "jdtls" }) > 0 end, "jdtls 附加到 jdt 缓冲区")
    local s = loc.range.start
    vim.api.nvim_win_set_cursor(0, { s.line + 1, s.character })
    local p = await(t, function(cb) U().find_usages(cb) end, "依赖库里查找用法")
    local hit
    for _, n in ipairs(p:occurrences()) do
      if n.item.file == "UserServiceImpl.java" and n.item.lnum == 33 then hit = n end
    end
    t.ok(hit, "找到 UserServiceImpl 里的 new ArrayList")
    t.eq(hit.parent.parent.parent.parent.label, "生产代码")

    -- 依赖库里的用法分组
    local roots = U().build_tree({ {
      uri = "jdt://contents/rt.jar/java.util/ArrayList.class?=x", group = "lib", module = "rt.jar", package = "java.util",
      file = "ArrayList.class", lnum = 3, col = 0, end_col = 4, text = "List x",
      range = { start = { line = 2, character = 0 }, ["end"] = { line = 2, character = 4 } },
    } })
    t.eq(roots[1].label, "依赖库")
    t.eq(roots[1].children[1].label, "rt.jar")
    t.eq(roots[1].children[1].children[1].children[1].label, "ArrayList.class")
  end,

  ["B 层级里跳进依赖库（Object）"] = function(t)
    vim.cmd("only")
    t.open("demo-app/src/main/java/com/example/demo/service/AbstractService.java")
    t.cursor_at("AbstractService")
    local p = await(t, function(cb) H().type_hierarchy("full", cb) end, "完整层级")
    t.eq(labels(p.roots), { "Object" })
    vim.api.nvim_set_current_win(p.win)
    p:set_cursor(p.roots[1])
    p:activate()
    t.ok(vim.api.nvim_buf_get_name(0):match("^jdt://"), "跳进 jdt:// 文件")
    t.ok(vim.api.nvim_get_current_line():find("class Object"), "光标在 Object 类声明：" .. vim.api.nvim_get_current_line())
  end,
}
