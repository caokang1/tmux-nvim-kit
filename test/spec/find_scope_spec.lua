local IMPL = "demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java"
local function fs() return require("config.kit.find_scope") end
return {
  ["1 模块根目录：离文件最近的 pom.xml"] = function(t)
    t.eq(fs().module_root(t.fixture .. "/" .. IMPL, t.fixture), t.fixture .. "/demo-app")
    t.eq(fs().module_root(t.fixture .. "/pom.xml", t.fixture), t.fixture)
    t.eq(fs().module_root("/tmp/x/y.java", t.fixture), nil)
  end,
  ["2 范围 → 搜索目录、排除规则、标题"] = function(t)
    local dirs = fs().scope_dirs(t.fixture .. "/" .. IMPL, t.fixture)
    t.eq(dirs.module, t.fixture .. "/demo-app")
    t.eq(dirs.dir, t.fixture .. "/demo-app/src/main/java/com/example/demo/service/impl")
    local r = fs().resolve({ scope = "project" }, dirs)
    t.eq(r.cwd, t.fixture)
    t.eq(r.title, "在文件中查找")
    for _, g in ipairs({ "target/", "build/", "node_modules/", ".git/" }) do
      t.ok(vim.tbl_contains(r.exclude, g), "默认未排除 " .. g)
    end
    t.ok(not vim.tbl_contains(r.exclude, "**/src/test/**"), "默认不该排除测试")
    r = fs().resolve({ scope = "module", exclude_tests = true }, dirs)
    t.eq(r.cwd, t.fixture .. "/demo-app")
    t.eq(r.title, "在文件中查找 [模块 demo-app] [排除测试]")
    t.ok(vim.tbl_contains(r.exclude, "**/src/test/**"), "未排除测试")
    r = fs().resolve({ scope = "dir" }, dirs)
    t.eq(r.title, "在文件中查找 [目录 demo-app/src/main/java/com/example/demo/service/impl]")
    -- 没有当前文件时模块 / 目录退回整个项目
    r = fs().resolve({ scope = "module" }, fs().scope_dirs("", t.fixture))
    t.eq(r.scope, "project")
  end,
  ["3 Alt+S 循环顺序（跳过不可用的范围）"] = function(t)
    local dirs = fs().scope_dirs(t.fixture .. "/" .. IMPL, t.fixture)
    t.eq(fs().next_scope("project", dirs), "module")
    t.eq(fs().next_scope("module", dirs), "dir")
    t.eq(fs().next_scope("dir", dirs), "custom")
    t.eq(fs().next_scope("custom", dirs), "project")
    local root_dirs = fs().scope_dirs(t.fixture .. "/pom.xml", t.fixture)
    t.eq(fs().next_scope("project", root_dirs), "custom")
  end,
  ["4 实际 rg 结果：排除 target 和测试代码"] = function(t)
    local dirs = fs().scope_dirs(t.fixture .. "/" .. IMPL, t.fixture)
    local function rg(st)
      local r = fs().resolve(st, dirs)
      local cmd = { "rg", "-l", "--no-ignore", "UserServiceImpl" }
      for _, e in ipairs(r.exclude) do vim.list_extend(cmd, { "-g", "!" .. e }) end
      local out = vim.system(cmd, { cwd = r.cwd, text = true }):wait().stdout
      return out
    end
    local all = rg({ scope = "module" })
    t.ok(not all:find("target/"), "没有排除 target：" .. all)
    t.ok(all:find("src/test/"), "应包含测试代码：" .. all)
    t.ok(not rg({ scope = "module", exclude_tests = true }):find("src/test/"), "没有排除测试代码")
  end,
  ["5 打开查找弹框、切换范围不报错"] = function(t)
    t.open(IMPL)
    fs().state.scope = "project"
    fs().state.exclude_tests = false
    local m = vim.fn.maparg("<M-F>", "n", false, true)
    t.ok(m.desc:find("Alt%+S"), "Alt+Shift+F 没有被覆盖：" .. tostring(m.desc))
    t.ok(vim.fn.maparg("<C-S-F>", "x", false, true).desc:find("选中"), "Ctrl+Shift+F 可视模式")
    local picker = fs().find_in_files("getUser")
    t.wait(5000, function() return picker:count() > 0 end, "有结果")
    t.eq(picker.title, "在文件中查找")
    picker:action("idea_scope")
    t.eq(picker.title, "在文件中查找 [模块 demo-app]")
    t.eq(picker:cwd(), t.fixture .. "/demo-app")
    picker:action("idea_tests")
    t.eq(picker.title, "在文件中查找 [模块 demo-app] [排除测试]")
    vim.wait(300)
    t.wait(5000, function() return not picker:is_active() end, "搜索结束")
    for item in picker:iter() do
      t.ok(not item.file:find("src/test/"), "排除测试后仍有：" .. item.file)
    end
    t.ok(picker:count() > 0, "模块范围内应有结果")
    picker:close()
    -- 下次打开记住范围
    picker = fs().find_in_files("getUser")
    t.eq(picker.title, "在文件中查找 [模块 demo-app] [排除测试]")
    picker:close()
  end,
  ["6 自选目录：弹出目录列表"] = function(t)
    t.open(IMPL)
    fs().state.scope = "dir"
    local picker = fs().find_in_files("getUser", { root = t.fixture })
    picker:action("idea_scope")
    t.wait(3000, function()
      local p = Snacks.picker.get({ source = nil })
      for _, x in ipairs(p) do
        if x.title == "选择查找范围（目录）" and x:count() > 0 then return true end
      end
    end, "目录选择框")
    local dp
    for _, x in ipairs(Snacks.picker.get()) do if x.title == "选择查找范围（目录）" then dp = x end end
    t.wait(5000, function() return not dp:is_active() end, "目录列表加载完")
    local target, seen = nil, {}
    for item in dp:iter() do
      seen[#seen + 1] = item.file
      if item.file == "demo-common" then target = item end
      t.ok(not item.file:find("target"), "目录列表不应包含 target")
    end
    t.ok(target, "目录列表中没有 demo-common：" .. table.concat(seen, ", "))
    dp.list:view(target.idx)
    dp:action("confirm")
    t.wait(3000, function()
      for _, x in ipairs(Snacks.picker.get()) do
        if x.title:find("demo%-common") then return true end
      end
    end, "重新打开查找框")
    t.eq(fs().state.custom, t.fixture .. "/demo-common")
    for _, x in ipairs(Snacks.picker.get()) do x:close() end
  end,
  ["7 全局替换按范围预填路径"] = function(t)
    fs().state.scope = "module"
    fs().state.exclude_tests = true
    local p = fs().replace_prefills(t.fixture .. "/" .. IMPL, t.fixture)
    t.eq(p.paths, t.fixture .. "/demo-app")
    t.eq(p.filesFilter, "!**/src/test/**")
    fs().state.scope = "project"
    fs().state.exclude_tests = false
    t.eq(fs().replace_prefills(t.fixture .. "/" .. IMPL, t.fixture), {})
  end,
}
