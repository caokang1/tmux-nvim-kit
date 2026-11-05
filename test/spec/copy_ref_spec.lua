local IMPL = "demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java"
local function ref(t, pattern)
  t.cursor_at(pattern)
  return (require("config.kit.copy_ref").java_reference())
end
return {
  ["1 方法内 → 类全限定名#方法"] = function(t)
    t.open(IMPL)
    t.eq(ref(t, "counter%+%+"), "com.example.demo.service.impl.UserServiceImpl#getUser")
    t.eq(ref(t, "public User getUser"), "com.example.demo.service.impl.UserServiceImpl#getUser")
    -- 方法上的注解也算这个方法
    vim.api.nvim_win_set_cursor(0, { 24, 0 })
    t.eq(require("config.kit.copy_ref").java_reference(), "com.example.demo.service.impl.UserServiceImpl#getUser")
  end,
  ["2 类名行 → 类全限定名"] = function(t)
    t.open(IMPL)
    t.eq(ref(t, "public class UserServiceImpl"), "com.example.demo.service.impl.UserServiceImpl")
    t.eq(ref(t, "^package"), "com.example.demo.service.impl.UserServiceImpl")
  end,
  ["3 字段 → #字段名"] = function(t)
    t.open(IMPL)
    t.eq(ref(t, "private UserMapper userMapper"), "com.example.demo.service.impl.UserServiceImpl#userMapper")
  end,
  ["4 候选项：相对/绝对路径、全限定名、文件名；可视模式行号 起-止"] = function(t)
    t.open(IMPL)
    t.cursor_at("counter%+%+")
    local items = require("config.kit.copy_ref").candidates()
    local values = vim.tbl_map(function(i) return i.value end, items)
    t.eq(values, {
      IMPL .. ":26",
      "com.example.demo.service.impl.UserServiceImpl#getUser",
      t.fixture .. "/" .. IMPL .. ":26",
      "UserServiceImpl.java",
    })
    items = require("config.kit.copy_ref").candidates({ line1 = 28, line2 = 25 })
    t.eq(items[1].value, IMPL .. ":25-28")
  end,
  ["5 非 Java 文件只有路径和文件名"] = function(t)
    t.open("README.md")
    local items = require("config.kit.copy_ref").candidates({ line1 = 3 })
    t.eq(#items, 3)
    t.eq(items[1].value, "README.md:3")
  end,
  ["6 按键弹出选择并复制到 + 寄存器"] = function(t)
    t.open(IMPL)
    t.cursor_at("counter%+%+")
    local orig = vim.ui.select
    local got
    vim.ui.select = function(items, opts, cb)
      got = opts.format_item(items[2])
      cb(items[2])
    end
    local ok, err = pcall(function()
      local m = vim.fn.maparg("<leader>cy", "n", false, true)
      t.ok(m.callback, "空格 c y 未映射")
      m.callback()
      t.ok(vim.fn.maparg("<C-M-S-c>", "n") ~= "", "Ctrl+Alt+Shift+C 未映射")
    end)
    vim.ui.select = orig
    t.ok(ok, err)
    t.ok(got:find("全限定名"), got)
    t.eq(vim.fn.getreg('"'), "com.example.demo.service.impl.UserServiceImpl#getUser")
  end,
  ["7 语言服务附加后 空格 c y 是复制引用，空格 c r 仍是 LazyVim 的重命名"] = function(t)
    t.open(IMPL)
    t.wait(60000, function() return #vim.lsp.get_clients({ name = "jdtls", bufnr = 0 }) > 0 end, "jdtls 附加")
    vim.wait(1000)
    local m = vim.fn.maparg("<leader>cy", "n", false, true)
    t.ok(m.desc and m.desc:find("复制引用"), "空格 c y 被覆盖为：" .. tostring(m.desc))
    t.wait(20000, function() return vim.fn.maparg("<leader>cr", "n") ~= "" end, "空格 c r（重命名）不见了")
  end,
}
