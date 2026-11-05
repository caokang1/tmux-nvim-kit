-- 依赖库 / 反编译文件：jdt:// URI 解析、标签栏 / 状态栏 / winbar 显示名、Alt+F1 提示、Ctrl+E、Ctrl+B / Alt+F7 照常可用
local function lib() return require("config.kit.libfiles") end

local SPRING = "jdt://contents/spring-beans-5.3.13.jar/org.springframework.beans.factory.annotation/Autowired.java?=demo-app/%5C/home%5C/kk%5C/.m2%5C/repository%5C/org%5C/springframework%5C/spring-beans%5C/5.3.13%5C/spring-beans-5.3.13.jar=/maven.pomderived=/true=/%3Corg.springframework.beans.factory.annotation%28Autowired.class"
local JDK = "jdt://contents/java.base/java.util/ArrayList.java?=demo-app/%5C/usr%5C/lib%5C/jvm%5C/java-21-openjdk-amd64%5C/lib%5C/jrt-fs.jar%60java.base=/javadoc_location=/https:%5C/%5C/docs.oracle.com%5C/en%5C/java%5C/javase%5C/21%5C/docs%5C/api%5C/=/=/maven.pomderived=/true=/%3Cjava.util%28ArrayList.class"
local INNER = "jdt://contents/snakeyaml-1.27.jar/org.yaml.snakeyaml.util/ArrayUtils.java?=demo-app/%5C/home%5C/kk%5C/.m2%5C/repository%5C/org%5C/yaml%5C/snakeyaml%5C/1.27%5C/snakeyaml-1.27.jar=/maven.pomderived=/true=/%3Corg.yaml.snakeyaml.util%28ArrayUtils$CompositeUnmodifiableArrayList.class"
local OLD = "jdt://contents/rt.jar/java.util/ArrayList.class?=demo/%2Fusr%2Flib%2Fjvm%2Fjava-8%2Fjre%2Flib%2Frt.jar%3Cjava.util(ArrayList.class"
local DEFAULT_PKG = "jdt://contents/foo-1.0.jar/%28default%20package%29/Foo.class?=demo/foo-1.0.jar%3C%28Foo.class"
local ENTRY = "jdt://jarentry/META-INF/spring.factories?=demo-app/%5C/home%5C/kk%5C/.m2%5C/repository%5C/org%5C/springframework%5C/boot%5C/spring-boot%5C/2.4.13%5C/spring-boot-2.4.13.jar=/maven.pomderived=/true"

local function notify_capture(fn)
  local msgs = {}
  local orig = vim.notify
  vim.notify = function(m) msgs[#msgs + 1] = m end
  local ok, err = pcall(fn)
  vim.notify = orig
  assert(ok, err)
  return msgs
end

local function goto_def(t, pattern, offset)
  t.cursor_at(pattern)
  if offset then vim.api.nvim_win_set_cursor(0, { vim.fn.line("."), vim.fn.col(".") - 1 + offset }) end
  local before = vim.api.nvim_get_current_buf()
  -- 和 Ctrl+B 选中结果后一样打开 jdt:// 位置（Ctrl+B 的提供者链由别的模块负责，这里只测依赖库文件本身）
  local res = vim.lsp.buf_request_sync(0, "textDocument/definition", vim.lsp.util.make_position_params(0, "utf-16"), 20000)
  for _, r in pairs(res or {}) do
    local loc = r.result and (r.result[1] or r.result)
    if loc and (loc.uri or loc.targetUri) then vim.lsp.util.show_document(loc, "utf-16", { focus = true }) break end
  end
  t.wait(30000, function()
    return vim.api.nvim_get_current_buf() ~= before and lib().is_lib(vim.api.nvim_buf_get_name(0))
      and vim.api.nvim_buf_line_count(0) > 5
  end, "跳到依赖库类 " .. pattern)
  return vim.api.nvim_get_current_buf()
end

return {
  ["1 解析各种 jdt:// URI"] = function(t)
    local p = lib().parse(SPRING)
    t.eq({ p.kind, p.jar, p.pkg, p.class, p.jdk }, { "class", "spring-beans-5.3.13.jar", "org.springframework.beans.factory.annotation", "Autowired", false })
    p = lib().parse(JDK)
    t.eq({ p.jar, p.pkg, p.class, p.jdk }, { "java.base", "java.util", "ArrayList", true })
    t.eq(lib().jar_label(p), "JDK java.base")
    p = lib().parse(INNER)
    t.eq({ p.class, p.inner }, { "ArrayUtils", "ArrayUtils$CompositeUnmodifiableArrayList" })
    p = lib().parse(OLD)
    t.eq({ p.jar, p.pkg, p.class, p.jdk }, { "rt.jar", "java.util", "ArrayList", false })
    p = lib().parse(DEFAULT_PKG)
    t.eq({ p.jar, p.pkg, p.class }, { "foo-1.0.jar", "", "Foo" })
    p = lib().parse(ENTRY)
    t.eq({ p.kind, p.class, p.jar }, { "entry", "spring.factories", "spring-boot-2.4.13.jar" })
    t.eq(lib().display_name(ENTRY), "spring.factories")
    t.eq(lib().display_name(SPRING), "Autowired.class") -- 没加载时按 .class 显示
    t.eq(lib().parse("/home/x/Foo.java"), nil)
  end,

  ["2 跳到 JDK 类（反编译）：标签栏、状态栏、winbar 显示类名和 jar"] = function(t)
    t.open("demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java")
    t.wait_jdtls()
    local buf = goto_def(t, "ArrayList<>")
    t.eq(lib().display_name(vim.api.nvim_buf_get_name(buf), buf), "ArrayList.class")
    -- 标签栏（bufferline 实际渲染结果）
    vim.cmd("redraw")
    local tab = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str
    t.ok(tab:find("ArrayList.class", 1, true), "标签栏没有 ArrayList.class：" .. tab)
    t.ok(not tab:find("jdt:", 1, true), "标签栏显示了 URI：" .. tab)
    -- 状态栏（lualine）
    vim.o.columns = 220
    -- 全新环境里 lualine 可能还没加载完，等状态栏出现再检查
    local st = ""
    t.wait(10000, function()
      pcall(function() require("lualine").refresh({ place = { "statusline" }, scope = "window", trigger = "test" }) end)
      st = vim.api.nvim_eval_statusline(vim.wo.statusline ~= "" and vim.wo.statusline or vim.o.statusline, {}).str
      return st:find("java.base › ArrayList.class", 1, true) ~= nil
    end, "状态栏：" .. st) -- 窗口窄时左边被截断
    -- 窗口顶部
    t.ok(vim.wo.winbar ~= "", "没有 winbar")
    local wb = vim.api.nvim_eval_statusline(vim.wo.winbar, { use_winbar = true }).str
    t.ok(wb:find("java.base › java.util › ArrayList.class", 1, true), "winbar：" .. wb)
  end,

  ["3 在依赖库文件里 Alt+F1 提示、Ctrl+B / Alt+F7 照常可用"] = function(t)
    local msgs = notify_capture(function() lib().reveal() end)
    t.eq(msgs, { "JDK 文件（java.base），不在项目文件中" })
    -- Ctrl+B：extends AbstractList 跳到另一个 JDK 类
    local buf = vim.api.nvim_get_current_buf()
    t.cursor_at("extends AbstractList")
    vim.cmd("normal! w")
    local res = vim.lsp.buf_request_sync(0, "textDocument/definition", vim.lsp.util.make_position_params(0, "utf-16"), 20000)
    local uri
    for _, r in pairs(res or {}) do
      local loc = r.result and (r.result[1] or r.result)
      uri = loc and (loc.uri or loc.targetUri)
    end
    t.ok(uri and uri:find("AbstractList", 1, true), "定义：" .. tostring(uri))
    require("config.idea_keys").definition()
    -- Ctrl+B 弹出的"跳转到定义"列表（只有一项时直接跳转）：无界面测试里列表不一定自动确认，手动确认
    vim.wait(20000, function()
      local p = Snacks.picker.get()[1]
      return vim.api.nvim_buf_get_name(0):find("AbstractList", 1, true) ~= nil or (p and p:count() > 0)
    end)
    local p = Snacks.picker.get()[1]
    if p then p:action("confirm") end
    t.wait(20000, function() return vim.api.nvim_buf_get_name(0):find("AbstractList", 1, true) ~= nil end, "Ctrl+B 跳到 AbstractList")
    t.eq(lib().display_name(vim.api.nvim_buf_get_name(0), 0), "AbstractList.class")
    vim.api.nvim_set_current_buf(buf)
    -- Alt+F7：查找用法请求在 jdt:// 缓冲区里能正常返回
    -- 依赖库类本身的用法：应能找到项目里的 UserServiceImpl
    t.cursor_at("public class ArrayList")
    vim.cmd("normal! 2w")
    local params = vim.lsp.util.make_position_params(0, "utf-16")
    params.context = { includeDeclaration = false }
    local t0 = vim.uv.now()
    local refs = vim.lsp.buf_request_sync(0, "textDocument/references", params, 60000)
    io.stdout:write(("    （依赖库类查找用法耗时 %d ms）\n"):format(vim.uv.now() - t0))
    local ok = false
    for _, r in pairs(refs or {}) do
      for _, loc in ipairs(r.result or {}) do
        if loc.uri:find("UserServiceImpl.java", 1, true) then ok = true end
      end
    end
    t.ok(ok, "查找用法出错：" .. vim.inspect(refs))
  end,

  ["4 有源码的依赖类显示 .java；Alt+F1 显示 jar 名"] = function(t)
    t.open("demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java")
    local buf = goto_def(t, "@Service", 1)
    local name = vim.api.nvim_buf_get_name(buf)
    t.ok(name:find("spring%-context"), name)
    local head = table.concat(vim.api.nvim_buf_get_lines(buf, 0, 5, false), "\n")
    local expect = head:lower():find("decompiled") and "Service.class" or "Service.java"
    t.eq(lib().display_name(name, buf), expect)
    local msgs = notify_capture(function() lib().reveal() end)
    t.ok(msgs[1]:find("^依赖库文件（spring%-context%-[%d.]+%.jar），不在项目文件中$"), msgs[1])
    vim.cmd("redraw")
    local tab = vim.api.nvim_eval_statusline(vim.o.tabline, { use_tabline = true }).str
    t.ok(tab:find(expect, 1, true), "标签栏：" .. tab)
  end,

  ["5 Ctrl+E 最近的文件列出依赖库类（显示类名）和项目文件"] = function(t)
    t.open("demo-app/src/main/java/com/example/demo/entity/User.java")
    local items = lib().recent_items()
    local names = {}
    for _, it in ipairs(items) do names[#names + 1] = it.lib and it.display or vim.fs.basename(it.file) end
    t.ok(vim.tbl_contains(names, "ArrayList.class"), vim.inspect(names))
    t.ok(vim.tbl_contains(names, "UserServiceImpl.java"), vim.inspect(names))
    t.ok(not vim.tbl_contains(names, "User.java"), "不应包含当前文件")
    -- 打开列表，选中依赖库类能打开
    lib().recent()
    local picker = Snacks.picker.get()[1]
    t.ok(picker, "没有打开列表")
    t.wait(3000, function() return picker:count() > 0 end, "列表有内容")
    local target
    for i, it in ipairs(picker:items()) do
      if it.lib and it.display == "ArrayList.class" then target = i end
    end
    t.ok(target, "列表里没有 ArrayList.class")
    picker.list:view(target)
    picker:action("confirm")
    t.wait(10000, function() return vim.api.nvim_buf_get_name(0):find("ArrayList", 1, true) ~= nil end, "打开 ArrayList")
  end,
}
