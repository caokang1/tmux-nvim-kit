-- 左侧实现 / 重写图标（gutter）、在声明处 Ctrl+B 显示用法、Spring Bean 字段跳实现
local D = "demo-app/src/main/java/com/example/demo/"

local function g() return require("config.kit.gutter") end

-- 算出整个文件的图标（反复 update 直到没有新请求：类型的结果回来后才会问方法）
local function compute(t, buf)
  for _ = 1, 4 do
    g().update(buf, true)
    t.wait(30000, function() return not g().busy(buf) end, "图标计算完成")
  end
end

-- 把图标表转成 { [行号 1 基] = "I" / "O" / "↓" / "I↓" ... }，方便比较
local function summary(buf)
  local out = {}
  for row, e in pairs(g().icons(buf)) do
    out[row + 1] = (e.up or "") .. (e.down and "↓" or "")
  end
  return out
end

local function signs(buf)
  local ns = vim.api.nvim_get_namespaces().kit_gutter
  local out = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })) do
    out[m[2] + 1] = vim.trim(m[4].sign_text or "")
  end
  return out
end

return {
  ["1 treesitter 解析结构（不需要语言服务）"] = function(t)
    local buf = t.open(D .. "service/impl/UserServiceImpl.java")
    local items = g().parse(buf)
    local by = {}
    for _, it in ipairs(items) do by[it.kind .. ":" .. (it.name or it.tname)] = it end
    t.ok(by["type:UserServiceImpl"] and by["type:UserServiceImpl"].super and by["type:UserServiceImpl"].ifaces, "类的 extends/implements")
    t.eq(by["method:getUser"].row, 24, "getUser 行")
    t.ok(by["method:getUser"].override, "getUser @Override")
    t.ok(by["field:UserMapper"], "@Autowired 字段")
    t.ok(not by["field:String"], "@Value 字段不算注入")
  end,

  ["2 声明处 Ctrl+B 走用法分支，调用处走跳转分支"] = function(t)
    local du = require("config.kit.decl_usages")
    local buf = t.open(D .. "service/UserService.java")
    t.cursor_at("getUser")
    t.ok(du.at_cursor(), "getUser 声明处应判为声明")
    t.cursor_at("UserService")
    t.ok(du.at_cursor(), "接口名声明")
    t.cursor_at("User user")
    t.ok(not du.at_cursor(), "参数类型不是声明")
    t.cursor_at("user%)")
    t.ok(du.at_cursor(), "参数名是声明")
    -- 声明处：goto.run() 交给用法（替换 usages 模块观察调用）
    local called = 0
    local saved = package.loaded["config.kit.usages"]
    package.loaded["config.kit.usages"] = { show_popup = function() called = called + 1 end }
    t.cursor_at("getUser")
    t.ok(require("config.kit.goto").run(), "声明处应被处理")
    t.eq(called, 1, "声明处调用 show_popup")
    -- 调用处
    t.open(D .. "controller/UserController.java")
    t.cursor_at("getUser%(id")
    t.ok(not du.at_cursor(), "调用处不是声明")
    t.cursor_at("userService;")
    t.ok(du.at_cursor(), "字段名是声明")
    package.loaded["config.kit.usages"] = saved
    t.ok(vim.api.nvim_buf_is_valid(buf))
  end,

  ["3 各文件图标种类正确"] = function(t)
    t.open(D .. "controller/UserController.java")
    t.wait_jdtls()
    local cases = {
      [D .. "service/UserService.java"] = { [6] = "↓", [7] = "↓", [9] = "↓", [11] = "↓" },
      [D .. "service/AbstractService.java"] = { [3] = "↓", [4] = "↓", [8] = "↓" },
      [D .. "service/impl/UserServiceImpl.java"] = { [25] = "I", [32] = "I", [39] = "I", [44] = "O", [49] = "O" },
      [D .. "service/impl/AdminUserServiceImpl.java"] = { [10] = "I", [15] = "I", [20] = "I" },
      [D .. "entity/User.java"] = { [12] = "O" },
      ["demo-common/src/main/java/com/example/common/BaseEntity.java"] = { [5] = "↓", [21] = "↓" },
      [D .. "controller/UserController.java"] = { [20] = "↓" },
    }
    for file, want in pairs(cases) do
      local buf = t.open(file)
      t.wait(60000, function() return #vim.lsp.get_clients({ name = "jdtls", bufnr = buf }) > 0 end, "jdtls 附加 " .. file)
      compute(t, buf)
      t.eq(summary(buf), want, file)
      local s = signs(buf)
      for l, v in pairs(want) do
        local exp = v == "↓" and "↓" or "↑"
        t.eq(s[l], exp, file .. " 第 " .. l .. " 行图标")
      end
    end
  end,

  ["4 UserServiceImpl 全部图标计算耗时"] = function(t)
    local buf = t.open(D .. "service/impl/UserServiceImpl.java")
    t.wait_jdtls()
    g().invalidate()
    local req0 = g().requests or 0
    local t0 = vim.uv.hrtime()
    compute(t, buf)
    local ms = (vim.uv.hrtime() - t0) / 1e6
    io.stdout:write(string.format("    UserServiceImpl 全部图标计算耗时：%.0f ms，LSP 请求 %d 个（含类型结果回来后重算前的 200ms 节流等待）\n",
      ms, (g().requests or 0) - req0))
    -- 结构解析（每次打开 / 修改时同步执行的部分）
    vim.api.nvim_buf_set_lines(buf, 0, 0, false, { "" })
    local t1 = vim.uv.hrtime()
    g().parse(buf)
    io.stdout:write(string.format("    treesitter 结构解析：%.2f ms\n", (vim.uv.hrtime() - t1) / 1e6))
    vim.cmd("silent! undo")
    t.eq(summary(buf)[25], "I")
  end,

  ["5 Spring Bean 字段：图标点击和 Ctrl+Alt+B 列出两个实现"] = function(t)
    local buf = t.open(D .. "controller/UserController.java")
    t.wait_jdtls()
    compute(t, buf)
    local hs = require("config.kit.signclick").get(buf, 20)
    t.eq(#hs, 1, "第 20 行有点击处理")
    -- 名字上的 Ctrl+Alt+B 改到类型名上查
    t.cursor_at("userService;")
    local pos = vim.api.nvim_win_get_cursor(0)
    local r, c = g().impl_position(buf, pos[1] - 1, pos[2])
    t.eq({ r, c }, { 19, 12 }, "类型 UserService 的位置")
    local res = vim.lsp.buf_request_sync(buf, "textDocument/implementation",
      { textDocument = { uri = vim.uri_from_bufnr(buf) }, position = { line = r, character = c } }, 20000)
    local names = {}
    for _, x in pairs(res or {}) do
      for _, loc in ipairs(x.result or {}) do names[#names + 1] = vim.fn.fnamemodify(vim.uri_to_fname(loc.uri), ":t") end
    end
    table.sort(names)
    t.eq(names, { "AdminUserServiceImpl.java", "UserServiceImpl.java" })
    -- 点击图标：打开实现列表
    hs[1].fn()
    t.wait(10000, function()
      local p = Snacks.picker.get()[1]
      return p and p:count() >= 2
    end, "实现列表打开并有 2 项")
    Snacks.picker.get()[1]:close()
    t.eq(vim.api.nvim_win_get_cursor(0), { 20, 12 }, "光标移到类型名上")
  end,

  ["6 开关"] = function(t)
    local buf = t.open(D .. "service/UserService.java")
    compute(t, buf)
    t.ok(next(signs(buf)), "有图标")
    g().toggle(false)
    t.eq(signs(buf), {}, "关闭后无图标")
    t.eq(require("config.kit.signclick").get(buf, 7), {}, "关闭后无点击处理")
    g().toggle(true)
    compute(t, buf)
    t.ok(next(signs(buf)), "重新开启有图标")
    t.ok(vim.fn.maparg("<leader>uO", "n") ~= "", "空格 u O 已映射")
  end,
}
