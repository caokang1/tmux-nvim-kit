-- MyBatis Mapper ↔ XML 互跳（config/kit/mybatis.lua）：纯文本解析，不等 jdtls
local MAPPER = "demo-app/src/main/java/com/example/demo/mapper/UserMapper.java"
local XML = "demo-app/src/main/resources/mapper/UserMapper.xml"

local function name() return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t") end
local function line() return vim.api.nvim_get_current_line() end
local function ctrl_b() require("config.idea_keys").definition() end

return {
  ["1 解析 XML 和 Mapper 接口"] = function(t)
    local mb = require("config.kit.mybatis")
    local x = mb.xml(t.fixture .. "/" .. XML)
    t.eq(x.namespace, "com.example.demo.mapper.UserMapper")
    t.eq(x.ns_lnum, 3)
    t.eq(x.ids.selectById, { tag = "select", lnum = 14, col = 16 })
    t.eq(x.ids.BaseResultMap.tag, "resultMap")
    t.eq(x.ids.Base_Column_List.tag, "sql")
    t.eq(x.ids.insertUser.tag, "insert")
    -- 属性换行写的情况
    local y = mb.parse_xml_lines({ '<mapper', '  namespace="a.B">', '<select', '   id="foo"', '   resultType="int">' })
    t.eq(y.namespace, "a.B")
    t.eq(y.ids.foo, { tag = "select", lnum = 4, col = 7 })
    local mp = mb.java_mapper(t.fixture .. "/" .. MAPPER)
    t.eq(mp.fqn, "com.example.demo.mapper.UserMapper")
    t.ok(mp.is_mapper)
    t.eq(mp.methods.selectAll, { lnum = 12, col = 15 })
    t.eq(#mb.find_xml(mp.fqn, t.fixture), 1)
  end,
  ["2 接口方法 → XML 语句"] = function(t)
    t.open(MAPPER)
    t.cursor_at("selectById")
    ctrl_b()
    t.eq(name(), "UserMapper.xml")
    t.eq(vim.api.nvim_win_get_cursor(0), { 14, 16 })
  end,
  ["3 接口名 → namespace"] = function(t)
    t.open(MAPPER)
    t.cursor_at("UserMapper {")
    ctrl_b()
    t.eq(name(), "UserMapper.xml")
    t.eq(vim.api.nvim_win_get_cursor(0)[1], 3)
  end,
  ["4 XML 语句 id → 接口方法，namespace → 接口"] = function(t)
    t.open(XML)
    t.cursor_at('id="insertUser"')
    vim.cmd("normal! 4l") -- 光标移到值上
    ctrl_b()
    t.eq(name(), "UserMapper.java")
    t.eq(vim.api.nvim_win_get_cursor(0), { 14, 8 })
    t.open(XML)
    t.cursor_at("com.example.demo.mapper")
    ctrl_b()
    t.eq(name(), "UserMapper.java")
    t.eq(vim.api.nvim_win_get_cursor(0), { 9, 17 })
  end,
  ["5 resultMap / include refid 在 XML 内跳转"] = function(t)
    t.open(XML)
    t.cursor_at('resultMap="BaseResultMap"')
    vim.cmd("normal! 12l")
    ctrl_b()
    t.eq(vim.api.nvim_win_get_cursor(0)[1], 4)
    t.cursor_at('refid="Base_Column_List"')
    vim.cmd("normal! 8l")
    ctrl_b()
    t.eq(vim.api.nvim_win_get_cursor(0)[1], 10)
    -- namespace.id 形式
    t.ok(require("config.kit.spring.util").attr_at('<include refid="com.example.demo.mapper.UserMapper.Base_Column_List"/>', 20))
  end,
  ["6 type= 全限定类名 → 类文件"] = function(t)
    t.open(XML)
    t.cursor_at('type="com.example')
    vim.cmd("normal! 8l")
    ctrl_b()
    t.eq(name(), "User.java")
    t.ok(line():find("class User"), line())
  end,
  ["7 左侧图标与点击"] = function(t)
    local mb = require("config.kit.mybatis")
    local sc = require("config.kit.signclick")
    local buf = t.open(MAPPER)
    local marks = mb.marks(buf)
    t.eq(vim.tbl_map(function(m) return m.lnum end, marks), { 10, 12, 14 })
    t.wait(3000, function() return #vim.api.nvim_buf_get_extmarks(buf, -1, 0, -1, { details = true, type = "sign" }) >= 3 end, "Mapper 图标")
    t.ok(sc.run(buf, 12), "第 12 行没有点击处理")
    t.eq(name(), "UserMapper.xml")
    t.eq(vim.api.nvim_win_get_cursor(0)[1], 20)
    local xbuf = vim.api.nvim_get_current_buf()
    t.eq(vim.tbl_map(function(m) return m.lnum end, mb.marks(xbuf)), { 3, 14, 20, 24 })
    t.wait(3000, function() return #sc.get(xbuf, 24) == 1 end, "XML 图标")
    sc.run(xbuf, 24)
    t.eq(name(), "UserMapper.java")
    t.eq(vim.api.nvim_win_get_cursor(0)[1], 14)
  end,
  ["7b 鼠标点击左侧栏才执行（文字区照常）"] = function(t)
    local sc = require("config.kit.signclick")
    local buf = t.open(MAPPER)
    t.wait(3000, function() return #sc.get(buf, 12) == 1 end, "图标")
    local win = vim.api.nvim_get_current_win()
    local textoff = vim.fn.getwininfo(win)[1].textoff
    t.ok(textoff > 0, "没有左侧栏")
    t.ok(not sc.click({ winid = win, line = 12, wincol = textoff + 3 }), "文字区不应处理")
    t.ok(not sc.click({ winid = win, line = 11, wincol = 1 }), "没有图标的行不应处理")
    t.ok(vim.fn.maparg("<LeftMouse>", "n") ~= "", "<LeftMouse> 未映射")
    t.ok(sc.click({ winid = win, line = 12, wincol = 1 }))
    t.wait(2000, function() return name() == "UserMapper.xml" end, "点击后跳到 XML")
    t.eq(vim.api.nvim_win_get_cursor(0)[1], 20)
  end,
  ["8 非 Mapper 位置不处理"] = function(t)
    t.open(MAPPER)
    t.cursor_at("import java.util.List")
    t.ok(not require("config.kit.mybatis").navigate())
    t.open(XML)
    t.cursor_at("from t_user where")
    t.ok(not require("config.kit.mybatis").navigate())
  end,
}
