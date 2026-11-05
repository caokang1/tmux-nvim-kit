-- 配置项 ↔ 代码（config/kit/config_keys.lua）：纯文本解析，不等 jdtls
local YML = "demo-app/src/main/resources/application.yml"
local function name() return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t") end
local function ctrl_b() require("config.idea_keys").definition() end
local function close_pickers() for _, p in ipairs(Snacks.picker.get()) do p:close() end end

return {
  ["1 解析 yml / properties 的完整键"] = function(t)
    local C = require("config.kit.config_keys")
    local keys, profiles = C.parse_yaml({
      "server:", "  port: 8080", "demo:", "  name: x  # 注释", "  feature:", "    max-size: 100",
      "  desc: |", "    a: b", "  list:", "    - id: 1", "      name: n", "---", "spring:", "  profiles: dev", "demo:", "  name: y",
    })
    t.eq(keys[2].key, "server.port")
    t.eq(keys[6].key, "demo.feature.max-size")
    t.eq(keys[6].col, 4)
    t.eq(keys[8], nil) -- 多行文本里的内容不是键
    t.eq(keys[10].key, "demo.list.id")
    t.eq(keys[11].key, "demo.list.name")
    t.eq(keys[16].key, "demo.name")
    t.eq(profiles[keys[16].doc], "dev")
    local p = C.parse_properties({ "# c", "a.b-c=1", "x: y", "long=a\\", "  b", "z 1" })
    t.eq(p[2].key, "a.b-c")
    t.eq(p[3].key, "x")
    t.eq(p[5], nil)
    t.eq(p[6].key, "z")
    t.eq(C.canon("demo.feature.max-size"), C.canon("demo.feature.maxSize"))
    t.eq(C.value_key_at('    @Value("${demo.name:默认}")', 14), "demo.name")
    t.eq(C.value_key_at('    @Value("${demo.name}")', 2), nil)
    t.eq(C.profile_of("/x/application-dev.yml"), "dev")
    t.eq(C.profile_of("/x/application.yml"), "默认")
  end,
  ["2 yml 中 demo.name → @Value 行"] = function(t)
    t.open(YML)
    t.cursor_at("  name: demo%-app")
    ctrl_b()
    t.eq(name(), "UserServiceImpl.java")
    t.eq(vim.api.nvim_win_get_cursor(0)[1], 19)
  end,
  ["3 yml 中 max-size → DemoProperties.maxSize"] = function(t)
    t.open(YML)
    t.cursor_at("max%-size")
    ctrl_b()
    t.eq(name(), "DemoProperties.java")
    t.eq(vim.api.nvim_win_get_cursor(0), { 10, 16 })
    -- 前缀键 → 类
    local items = require("config.kit.config_keys").usages("demo.feature", t.fixture)
    t.eq(#items, 1)
    t.eq(items[1].lnum, 8)
  end,
  ["4 Java @Value → 列出 application.yml 和 application-dev.yml"] = function(t)
    local C = require("config.kit.config_keys")
    local defs = C.definitions("demo.name", t.fixture)
    t.eq(vim.tbl_map(function(d) return name and vim.fn.fnamemodify(d.file, ":t") .. ":" .. d.lnum .. ":" .. d.label end, defs),
      { "application-dev.yml:2:dev", "application.yml:4:默认" })
    t.open("demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java")
    t.cursor_at("demo.name")
    ctrl_b()
    local picker
    t.wait(3000, function() picker = Snacks.picker.get()[1] return picker ~= nil and #picker:items() == 2 end, "profile 列表")
    picker.list:view(2)
    picker:action("confirm")
    t.wait(3000, function() return name() == "application.yml" end, "跳到 application.yml")
    t.eq(vim.api.nvim_win_get_cursor(0), { 4, 2 })
    close_pickers()
  end,
  ["5 @ConfigurationProperties 字段 → 配置定义"] = function(t)
    t.open("demo-app/src/main/java/com/example/demo/config/DemoProperties.java")
    t.cursor_at("maxSize;")
    t.eq(require("config.kit.config_keys").java_key_at(), "demo.feature.maxSize")
    ctrl_b()
    t.eq(name(), "application.yml")
    t.eq(vim.api.nvim_win_get_cursor(0), { 7, 4 })
  end,
  ["6 yml 里 Alt+F7 是缓冲区内的列出使用处"] = function(t)
    local buf = t.open(YML)
    local m = vim.fn.maparg("<M-F7>", "n", false, true)
    t.eq(m.buffer, 1)
    t.eq(m.desc, "列出配置项的使用处")
    t.ok(buf)
    t.cursor_at("  name: demo%-app")
    m.callback()
    t.eq(name(), "UserServiceImpl.java")
  end,
  ["7 不相关位置不处理"] = function(t)
    t.open("demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java")
    t.cursor_at("private int counter")
    t.ok(not require("config.kit.config_keys").navigate())
  end,
}
