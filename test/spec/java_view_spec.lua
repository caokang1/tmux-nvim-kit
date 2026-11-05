-- Java 文件阅读：import 默认折叠、全部折叠 / 展开、文件结构里的继承成员
local jv = function() return require("config.kit.java_view") end
local IMPL = "demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java"

local function line_of(pattern)
  for i, l in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, false)) do
    if l:find(pattern) then return i end
  end
  error("找不到：" .. pattern)
end

return {
  ["1 打开 Java 文件时 import 已折叠，其余代码展开"] = function(t)
    t.open(IMPL)
    local s, e = jv().import_range(0)
    t.eq({ s, e }, { 3, 11 })
    t.wait(3000, function() return vim.fn.foldclosed(3) == 3 end, "import 没有折叠")
    t.eq(vim.fn.foldclosedend(3), 11)
    t.eq(vim.wo.foldexpr, "v:lua.vim.treesitter.foldexpr()")
    for _, p in ipairs({ "public class UserServiceImpl", "public User getUser", "counter%+%+", "return \"user\"" }) do
      t.eq(vim.fn.foldclosed(line_of(p)), -1, "不该折叠：" .. p)
    end
    -- 折叠行显示 "󰋺 import ... (9)"
    vim.v.foldstart, vim.v.foldend = 3, 11
    local text = table.concat(vim.tbl_map(function(c) return c[1] end, jv().foldtext()))
    t.eq(text, "󰋺 import ... (9)")
  end,

  ["2 全部折叠只折方法体和 import，全部展开"] = function(t)
    t.open(IMPL)
    t.wait(3000, function() return vim.fn.foldclosed(3) == 3 end, "import 没有折叠")
    vim.api.nvim_win_set_cursor(0, { line_of("public class"), 0 })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<M-_>", true, false, true), "mx", false)
    t.eq(vim.fn.foldclosed(3), 3, "import 应折叠")
    t.eq(vim.fn.foldclosed(line_of("public class UserServiceImpl")), -1, "类本身不该折叠")
    t.eq(vim.fn.foldclosed(line_of("private int counter")), -1, "字段不该折叠")
    for _, p in ipairs({ "public User getUser", "public List<User> listUsers", "public void audit", "protected String serviceName" }) do
      local l = line_of(p)
      t.eq(vim.fn.foldclosed(l), l, "方法体没有折叠：" .. p)
    end
    -- 方法的折叠行：签名 + ⋯ }
    local l = line_of("public void audit")
    vim.v.foldstart, vim.v.foldend = l, vim.fn.foldclosedend(l)
    local text = table.concat(vim.tbl_map(function(c) return c[1] end, jv().foldtext()))
    t.eq(text, "    public void audit(String action) { ⋯ }")
    -- 全部展开
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<M-+>", true, false, true), "mx", false)
    t.eq(vim.fn.foldclosed(3), -1, "import 应展开")
    t.eq(vim.fn.foldclosed(l), -1, "方法应展开")
    -- Alt+- / Alt+= 折叠 / 展开当前块
    vim.api.nvim_win_set_cursor(0, { l + 1, 0 })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<M-->", true, false, true), "mx", false)
    t.eq(vim.fn.foldclosed(l + 1), l, "Alt+- 没有折叠当前方法")
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<M-=>", true, false, true), "mx", false)
    t.eq(vim.fn.foldclosed(l + 1), -1, "Alt+= 没有展开")
  end,

  ["3 继承的成员（jdtls 类型层级）"] = function(t)
    t.open(IMPL)
    t.wait_jdtls()
    local res, err
    jv().collect_inherited(0, function(r, e) res, err = r, e end)
    t.wait(60000, function() return res ~= nil or err ~= nil end, "取继承的成员")
    t.ok(res, tostring(err))
    local names = {}
    for _, m in ipairs(res) do names[m.from .. "." .. m.symbol.name:gsub("%(.*$", "")] = m end
    t.ok(names["AbstractService.audit"], "缺 AbstractService.audit：" .. vim.inspect(vim.tbl_keys(names)))
    t.ok(names["AbstractService.serviceName"], "缺 AbstractService.serviceName")
    t.ok(names["UserService.getUser"], "缺 UserService.getUser")
    -- 依赖库里的 Object（jdt:// 地址）
    t.ok(names["Object.toString"], "缺 Object.toString（依赖库父类）：" .. vim.inspect(vim.tbl_keys(names)))
    t.ok(names["Object.toString"].uri:match("^jdt://"), "Object 不是 jdt:// 地址")
    -- 近的父类在前
    local order = {}
    for _, m in ipairs(res) do if not vim.tbl_contains(order, m.from) then order[#order + 1] = m.from end end
    t.eq(order[#order], "Object")
  end,

  ["4 文件结构弹框：Ctrl+F12 切换继承成员，过滤保留"] = function(t)
    t.open(IMPL)
    t.wait_jdtls()
    local picker = jv().structure()
    t.wait(20000, function() return #picker:items() > 0 end, "文件结构条目")
    local function has_inherited()
      for _, it in ipairs(picker:items()) do if it.inherited_from then return true end end
    end
    t.ok(not has_inherited(), "默认不该显示继承成员")
    t.ok(picker.title:find("Ctrl%+F12 显示继承"), "标题没有提示：" .. picker.title)
    t.wait(5000, function() return picker.input.win:valid() end, "弹框没有显示")
    picker.input:set("audit")
    picker:find({ refresh = false }) -- 无界面时不触发 TextChanged，手动刷新
    local function names()
      return vim.tbl_map(function(it) return it.name end, picker:items())
    end
    -- 树形显示：匹配项和它所在的类
    local function only_audit()
      local n, hit = names(), false
      for _, it in ipairs(picker:items()) do
        if it.name:find("^audit") then hit = true elseif it.kind ~= "Class" then return false end
      end
      return hit and #n <= 2
    end
    local ok = vim.wait(5000, only_audit, 50)
    t.ok(ok, "过滤 audit：" .. vim.inspect(names()))
    picker:action("kit_toggle_inherited")
    t.wait(30000, function() return has_inherited() end, "切换后没有继承成员")
    t.ok(picker.title:find("含继承"), "标题没有显示状态：" .. picker.title)
    t.eq(picker.input:get(), "audit", "过滤文字丢了")
    local froms = {}
    for _, it in ipairs(picker:items()) do froms[#froms + 1] = it.inherited_from or "本类" end
    t.ok(vim.tbl_contains(froms, "AbstractService") and vim.tbl_contains(froms, "本类"), vim.inspect(froms))
    -- 格式化不报错，带来源类名
    for _, it in ipairs(picker:items()) do
      local ret = picker.format(it, picker)
      if it.inherited_from then
        t.ok(ret[#ret][1]:find("← " .. it.inherited_from, 1, true), "没有来源类名")
        if it.inherited_from == "AbstractService" and it.name:find("^audit") then
          t.ok(ret[#ret][1]:find("已重写"), "被重写的 audit 没有标出：" .. ret[#ret][1])
        end
      end
    end
    -- 选中继承成员能跳到父类文件
    t.wait(5000, function()
      if picker:is_active() then return false end
      for i = 1, picker.list:count() do
        if picker.list:get(i).inherited_from == "AbstractService" then
          picker.list:view(i)
          local c = picker:current()
          return c and c.inherited_from == "AbstractService"
        end
      end
    end, "列表里没有 AbstractService 的成员")
    local cur = picker:current()
    t.eq(cur and cur.inherited_from, "AbstractService", "没有选中继承成员")
    picker:action("confirm")
    local ok = vim.wait(5000, function() return vim.api.nvim_buf_get_name(0):match("AbstractService%.java$") end, 50)
    t.ok(ok, "没有跳到 AbstractService：" .. vim.api.nvim_buf_get_name(0) .. " " .. vim.inspect({ cur.file, cur.buf, cur.pos }))
    t.ok(vim.api.nvim_get_current_line():find("audit"), "没有定位到 audit")
  end,

  ["5 继承自依赖库（jdt://）的成员能跳转"] = function(t)
    t.open(IMPL)
    t.wait_jdtls()
    local picker = jv().structure()
    t.wait(5000, function() return picker.input.win:valid() end, "弹框没有显示")
    picker:action("kit_toggle_inherited")
    picker.input:set("hashCode")
    picker:find({ refresh = false })
    t.wait(30000, function()
      if picker:is_active() then return false end
      for i = 1, picker.list:count() do
        if picker.list:get(i).inherited_from == "Object" then
          picker.list:view(i)
          local c = picker:current()
          return c and c.inherited_from == "Object"
        end
      end
    end, "列表里没有 Object 的成员")
    picker:action("confirm")
    t.wait(20000, function()
      return vim.api.nvim_buf_get_name(0):match("^jdt://") and vim.api.nvim_get_current_line():find("hashCode")
    end, "没有跳到 Object.hashCode：" .. vim.api.nvim_buf_get_name(0))
  end,

  ["6 同一窗口换成非 Java 文件时还原折叠设置"] = function(t)
    t.open(IMPL)
    t.eq(vim.wo.foldtext:find("java_view") ~= nil, true)
    t.open("README.md")
    t.eq(vim.wo.foldtext, "")
    t.ok(vim.wo.foldexpr ~= "v:lua.vim.treesitter.foldexpr()", "foldexpr 没有还原：" .. vim.wo.foldexpr)
    t.open(IMPL)
    t.eq(vim.wo.foldexpr, "v:lua.vim.treesitter.foldexpr()")
  end,

  ["7 javadoc 可折叠，父类 private 成员不算继承"] = function(t)
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local f = dir .. "/Base.java"
    vim.fn.writefile({
      "package x;", "", "/**", " * 说明", " */", "public class Base {",
      "    private int secret;", "    protected void hook() {", "    }", "    private",
      "    void hidden() {", "    }", "}",
    }, f)
    vim.cmd("edit " .. vim.fn.fnameescape(f))
    t.wait(3000, function() return vim.fn.foldlevel(3) > 0 end, "javadoc 没有折叠范围")
    t.eq(vim.fn.foldclosed(3), -1, "javadoc 默认不该折叠")
    vim.cmd("3foldclose")
    t.eq(vim.fn.foldclosed(3), 3)
    vim.v.foldstart, vim.v.foldend = 3, 5
    local text = table.concat(vim.tbl_map(function(c) return c[1] end, jv().foldtext()))
    t.eq(text, "/** ⋯ */")
    local uri = vim.uri_from_fname(f)
    local function sym(name, l1, l2)
      return { name = name, range = { start = { line = l1 } }, selectionRange = { start = { line = l2 } } }
    end
    t.eq(jv().is_private(uri, sym("secret", 6, 6)), true)
    t.eq(jv().is_private(uri, sym("hook()", 7, 7)), false)
    t.eq(jv().is_private(uri, sym("hidden()", 9, 10)), true)
    t.eq(jv().is_private("jdt://x", sym("a", 0, 0)), false)
  end,
}
