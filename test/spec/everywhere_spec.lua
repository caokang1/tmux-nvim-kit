-- 到处搜索（Search Everywhere）和 Ctrl+N 查找类
local function ev() return require("config.kit.everywhere") end

local function names(items, cat)
  local ret = {}
  for _, it in ipairs(items) do
    if not cat or it.cat == cat then
      ret[#ret + 1] = it.name or it.desc or (it.lib and it.display) or vim.fs.basename(it.file)
    end
  end
  return ret
end

local function has(list, v) return vim.tbl_contains(list, v) end

-- 关掉上一个用例留下的弹框，打开新弹框并等它显示出来
local function opened(t, picker)
  t.ok(picker, "弹框没打开")
  t.wait(5000, function() return picker.input and picker.input.win:valid() end, "弹框显示")
  return picker
end

local function close_all()
  for _, p in ipairs(Snacks.picker.get()) do p:close() end
end

local function wait_picker(t, picker, cond, msg)
  t.wait(30000, function() return not picker:is_active() and cond(picker) end, msg)
  return picker
end

return {
  ["0 按键已映射"] = function(t)
    t.ok(vim.fn.maparg("<C-S-Space>", "n") ~= "", "Ctrl+Shift+Space 未映射")
    t.ok(vim.fn.maparg("<leader>se", "n") ~= "", "空格 s e 未映射")
    t.ok(vim.fn.maparg("<C-n>", "n", false, true).desc:find("查找类"), "Ctrl+N")
  end,

  ["1 各分类的数据源都能找到 UserServiceImpl"] = function(t)
    t.open("demo-app/src/main/java/com/example/demo/controller/UserController.java")
    t.wait_jdtls()
    local root = t.fixture
    -- 类：小写、驼峰缩写、片段都能找到
    for _, q in ipairs({ "UserServiceImpl", "userserviceimpl", "USI", "ServiceImpl" }) do
      local items = ev().collect({ category = "class", root = root }, q)
      t.ok(has(names(items, "class"), "UserServiceImpl"), q .. "：" .. vim.inspect(names(items)))
    end
    -- 文件
    local items = ev().collect({ category = "file", root = root }, "UserServiceImpl")
    t.ok(has(names(items, "file"), "UserServiceImpl.java"), vim.inspect(names(items)))
    t.eq(items[1].file, root .. "/demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java")
    -- 符号（方法）：listUsers 在 UserService / UserServiceImpl / AdminUserServiceImpl 里
    items = ev().collect({ category = "symbol", root = root }, "listUsers")
    local containers = {}
    for _, it in ipairs(items) do containers[#containers + 1] = it.container end
    t.ok(has(containers, "com.example.demo.service.impl.UserServiceImpl"), vim.inspect(containers))
    -- 操作
    items = ev().collect({ category = "action", root = root }, "查找类")
    t.ok(#items > 0 and items[1].desc:find("查找类"), vim.inspect(names(items)))
    -- 最近的文件：先打开 UserServiceImpl 再回来
    t.open("demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java")
    t.open("demo-app/src/main/java/com/example/demo/controller/UserController.java")
    items = ev().collect({ category = "file", root = root }, "")
    t.ok(items[1] and items[1].recent and vim.fs.basename(items[1].file) == "UserServiceImpl.java", vim.inspect(names(items)))
  end,

  ["2 全部：分组显示、每组限量、类在最前"] = function(t)
    local items = ev().collect({ category = "all", root = t.fixture }, "user")
    local order, counts = {}, {}
    for _, it in ipairs(items) do
      if order[#order] ~= it.cat then order[#order + 1] = it.cat end
      counts[it.cat] = (counts[it.cat] or 0) + 1
    end
    t.eq(order[1], "class")
    -- 每组连续出现一次
    local seen = {}
    for _, c in ipairs(order) do
      t.ok(not seen[c], "分组不连续：" .. vim.inspect(order))
      seen[c] = true
    end
    for c, n in pairs(counts) do t.ok(n <= ev().group_limit[c], c .. " 超过限量 " .. n) end
    t.ok(seen.file and seen.symbol, vim.inspect(order))
  end,

  ["3 弹框：Tab 切换分类，标题显示当前分类"] = function(t)
    close_all()
    local picker = opened(t, ev().everywhere({ search = "UserServiceImpl" }))
    picker = wait_picker(t, picker, function(p) return p:count() > 0 end, "全部有结果")
    t.ok(picker.title:find("[全部]", 1, true), picker.title)
    local first = picker:items()[1]
    t.eq({ first.cat, first.name }, { "class", "UserServiceImpl" })
    picker:action("kit_ev_next")
    t.ok(picker.title:find("[类]", 1, true), picker.title)
    wait_picker(t, picker, function(p)
      for _, it in ipairs(p:items()) do if it.cat ~= "class" then return false end end
      return p:count() > 0
    end, "只剩类")
    picker:action("kit_ev_next")
    t.ok(picker.title:find("[文件]", 1, true), picker.title)
    wait_picker(t, picker, function(p) return p:count() > 0 and p:items()[1].cat == "file" end, "文件")
    picker:action("kit_ev_prev")
    picker:action("kit_ev_prev")
    t.ok(picker.title:find("[全部]", 1, true), picker.title)
    picker:action("kit_ev_prev")
    t.ok(picker.title:find("[操作]", 1, true), picker.title)
    picker:close()
  end,

  ["4 Ctrl+N 默认只看项目，再按 Ctrl+N 包含依赖库"] = function(t)
    local items = ev().collect({ category = "class", root = t.fixture }, "ArrayList")
    t.eq(#items, 0)
    items = ev().collect({ category = "class", root = t.fixture, libs = true }, "ArrayList")
    t.ok(has(names(items), "ArrayList"), vim.inspect(names(items)))
    t.eq(items[1].name, "ArrayList") -- 完全匹配的排第一
    t.ok(items[1].lib and items[1].lib.jar == "java.base", vim.inspect(items[1].lib))
    -- 项目内搜索不出依赖库的类
    items = ev().collect({ category = "class", root = t.fixture }, "Service")
    for _, it in ipairs(items) do t.ok(not it.lib, "项目内结果里有依赖库类：" .. it.name) end
    t.ok(has(names(items), "UserService"), vim.inspect(names(items)))

    -- 弹框：标题显示状态，按 Ctrl+N 切换
    close_all()
    local picker = opened(t, ev().goto_class())
    t.ok(picker.title:find("仅项目", 1, true), picker.title)
    picker.input:set("", "ArrayList")
    vim.wait(1500)
    picker = wait_picker(t, picker, function() return true end, "搜索完成")
    t.eq(picker:count(), 0)
    picker:action("kit_ev_libs")
    t.ok(picker.title:find("含依赖库", 1, true), picker.title)
    wait_picker(t, picker, function(p) return p:count() > 0 end, "包含依赖库后有结果")
    local it = picker:items()[1]
    t.eq(it.name, "ArrayList")
    -- 打开依赖库里的类
    picker.list:view(1)
    picker:action("confirm")
    t.wait(20000, function() return vim.api.nvim_buf_get_name(0):find("^jdt://.*ArrayList") ~= nil end, "打开 ArrayList")
  end,

  ["5 操作：选中后执行对应的快捷键"] = function(t)
    t.open("demo-app/src/main/java/com/example/demo/controller/UserController.java")
    vim.g.kit_ev_test = 0
    vim.keymap.set("n", "<leader>zq", function() vim.g.kit_ev_test = 1 end, { desc = "测试用操作 甲乙丙" })
    close_all()
    local picker = opened(t, ev().everywhere({ category = "action", search = "甲乙丙" }))
    picker = wait_picker(t, picker, function(p) return p:count() == 1 end, "找到操作")
    picker:action("confirm")
    -- 选中后用 nvim_input 模拟按下这个快捷键；无界面测试里要手动让编辑器处理输入
    t.wait(3000, function()
      vim.api.nvim_feedkeys("", "x", false)
      return vim.g.kit_ev_test == 1
    end, "执行了操作")
    vim.keymap.del("n", "<leader>zq")
  end,
}
