-- 接口地址搜索（config/kit/spring.lua）：纯文本解析，不等 jdtls
local function find(eps, method, path)
  for _, e in ipairs(eps) do
    if e.method == method and e.path == path then return e end
  end
end

return {
  ["1 路径拼接"] = function(t)
    local S = require("config.kit.spring")
    t.eq(S.join("/api/user", "/list"), "/api/user/list")
    t.eq(S.join("api/", "list/"), "/api/list")
    t.eq(S.join("", ""), "/")
    t.eq(S.join("/api", ""), "/api")
  end,
  ["2 解析出全部接口及方法、完整路径"] = function(t)
    local S = require("config.kit.spring")
    local eps = S.collect(t.fixture)
    local got = {}
    for _, e in ipairs(eps) do
      got[#got + 1] = string.format("%s %s %s#%s %s", e.method, e.path, e.class, e.name, e.module)
    end
    table.sort(got)
    t.eq(got, {
      "DELETE /api/order/api/legacy/remove OrderController#remove demo-app",
      "GET /api/order/detail OrderController#detail demo-app",
      "GET /api/user/list UserController#list demo-app",
      "GET /api/user/search UserController#search demo-app",
      "GET /api/user/{id} UserController#detail demo-app",
      "POST /api/user/create UserController#save demo-app",
      "POST /api/user/save UserController#save demo-app",
    })
    local e = find(eps, "GET", "/api/user/list")
    t.ok(e.file:find("UserController.java$"), e.file)
    t.eq({ e.lnum, e.col }, { 23, 22 })
  end,
  ["3 常量解析不了时显示 ${...}，Feign 接口标记"] = function(t)
    -- 临时项目放在 fixture 之外，不影响并行运行的其他测试
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir .. "/a", "p")
    vim.fn.writefile({
      "package com.example.demo.feign;",
      "import static com.x.Paths.BASE;",
      "@FeignClient(name = \"x\", path = \"/remote\")",
      "public interface TmpClient {",
      "    @RequestMapping(value = Missing.PATH, method = {RequestMethod.GET, RequestMethod.POST})",
      "    String call();",
      "    @PutMapping(BASE + (\"/x\"))",
      "    String put();",
      "}",
    }, dir .. "/a/TmpClient.java")
    vim.fn.writefile({ "package com.x;", "public interface Paths {", "  String BASE = \"/base\";", "}" }, dir .. "/a/Paths.java")
    local ok, err = pcall(function()
      local eps = require("config.kit.spring").collect(dir)
      local e = find(eps, "GET|POST", "/remote/${Missing.PATH}")
      t.ok(e and e.feign, vim.inspect(eps))
      t.ok(find(eps, "PUT", "/remote/base/x"), vim.inspect(eps))
    end)
    vim.fn.delete(dir, "rf")
    if not ok then error(err) end
  end,
  ["4 Ctrl+\\ 打开接口列表并跳转到方法"] = function(t)
    t.open("README.md")
    t.ok(vim.fn.maparg("<C-\\>", "n") ~= "", "Ctrl+\\ 未映射")
    require("config.kit.spring").open()
    local picker
    t.wait(5000, function()
      picker = Snacks.picker.get()[1]
      return picker ~= nil and #picker:items() >= 7
    end, "接口列表")
    -- 模糊输入路径片段
    picker.input:set("user/li")
    picker:find()
    t.wait(3000, function() local it = picker:items() return #it >= 1 and it[1].path == "/api/user/list" end, "过滤 user/li：" .. vim.inspect(vim.tbl_map(function(i) return i.path end, picker:items())))
    picker:action("confirm")
    t.wait(3000, function() return vim.api.nvim_buf_get_name(0):find("UserController.java$") ~= nil end, "跳到 UserController")
    t.eq(vim.api.nvim_win_get_cursor(0), { 23, 22 })
  end,
}
