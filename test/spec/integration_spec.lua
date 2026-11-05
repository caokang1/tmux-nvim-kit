-- 跨模块集成：各功能模块放在一起时，Ctrl+B 提供者的顺序、跳转后的光标位置等
local CTRL = "demo-app/src/main/java/com/example/demo/controller/UserController.java"
local SVC = "demo-app/src/main/java/com/example/demo/service/UserService.java"
local MAPPER = "demo-app/src/main/java/com/example/demo/mapper/UserMapper.java"

local function name() return vim.fn.fnamemodify(vim.api.nvim_buf_get_name(0), ":t") end
local function row() return vim.api.nvim_win_get_cursor(0)[1] end
local function close_pickers()
  for _, p in ipairs(Snacks.picker.get()) do p:close() end
  vim.cmd("stopinsert")
end

return {
  ["1 Ctrl+B 在调用处：唯一结果直接跳到 UserService.listUsers"] = function(t)
    t.open(CTRL)
    t.wait_jdtls()
    t.cursor_at("listUsers")
    require("config.idea_keys").definition()
    t.wait(15000, function() return name() == "UserService.java" end, "没有跳到 UserService.java，当前 " .. name())
    t.ok(vim.api.nvim_get_current_line():find("listUsers"), "光标行不对：" .. vim.api.nvim_get_current_line())
    close_pickers()
  end,
  ["2 Ctrl+B 在声明处：显示用法而不是跳到自己"] = function(t)
    t.open(SVC)
    t.wait_jdtls()
    t.cursor_at("getUser")
    t.ok(require("config.kit.decl_usages").at_cursor(), "getUser 声明处未识别为声明")
  end,
  ["3 Ctrl+B 在 Mapper 方法上：MyBatis 优先于在声明处显示用法"] = function(t)
    t.open(MAPPER)
    t.cursor_at("selectById")
    require("config.idea_keys").definition()
    t.wait(5000, function() return name() == "UserMapper.xml" end, "没有跳到 XML，当前 " .. name())
    t.ok(vim.api.nvim_get_current_line():find('id="selectById"'), vim.api.nvim_get_current_line())
  end,
  ["4 查找用法面板：回车跳到正确的行（Java 文件 import 已折叠时）"] = function(t)
    t.open(SVC)
    t.wait_jdtls()
    t.cursor_at("getUser")
    local done
    require("config.kit.usages").find_usages(function() done = true end)
    t.wait(20000, function() return done or vim.bo.filetype == "kit_tree" end, "用法面板")
    t.wait(20000, function()
      for _, w in ipairs(vim.api.nvim_list_wins()) do
        if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "kit_tree" then return true end
      end
    end, "用法面板窗口")
    -- 在面板里找到 UserController 的那一行用法并回车
    local tw
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(w)].filetype == "kit_tree" then tw = w end
    end
    vim.api.nvim_set_current_win(tw)
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local target
    t.wait(10000, function()
      lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
      for i, l in ipairs(lines) do
        if l:find("userService.getUser") then target = i return true end
      end
      -- 分组可能是折叠的：全部展开
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("ggl", true, false, true), "x", false)
      for i = 1, #lines do
        vim.api.nvim_win_set_cursor(0, { i, 0 })
        vim.api.nvim_feedkeys("l", "x", false)
      end
    end, "面板里找不到 userService.getUser：\n" .. table.concat(lines, "\n"))
    vim.api.nvim_win_set_cursor(0, { target, 0 })
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<CR>", true, false, true), "x", false)
    t.wait(5000, function() return name() == "UserController.java" end, "没有跳到 UserController")
    t.ok(vim.api.nvim_get_current_line():find("userService.getUser"),
      "光标在第 " .. row() .. " 行：" .. vim.api.nvim_get_current_line())
  end,
  ["5 配置项：yml 上 Ctrl+B 不被在声明处显示用法抢走"] = function(t)
    t.open("demo-app/src/main/resources/application.yml")
    t.cursor_at("name:")
    require("config.idea_keys").definition()
    t.wait(5000, function() return name() == "UserServiceImpl.java" end, "当前 " .. name())
  end,
}
