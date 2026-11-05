local IMPL = "demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java"
local function ga() return require("config.kit.git_annotate") end
return {
  ["1 从注释栏行解析提交号"] = function(t)
    t.eq(ga().sha_at("9409330a kk 2026-11-04"), "9409330a")
    t.eq(ga().sha_at("┍ 9409330a kk"), "9409330a")
    t.eq(ga().sha_at("00000000 Not Committed Yet"), nil)
    -- 同一提交的后续行没有提交号：往上找
    local b = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(b, 0, -1, false, { "┍ 9409330a kk", "│", "┕", "┍ abcdef12 kk", "│" })
    t.eq(ga().sha_for_row(b, 3), "9409330a")
    t.eq(ga().sha_for_row(b, 5), "abcdef12")
  end,
  ["2 Alt+Shift+G 打开注释栏，再按关闭"] = function(t)
    t.open(IMPL)
    local buf = vim.api.nvim_get_current_buf()
    t.wait(10000, function() return require("gitsigns.cache").cache[buf] ~= nil end, "gitsigns 附加")
    local m = vim.fn.maparg("<M-G>", "n", false, true)
    t.ok(m.callback, "Alt+Shift+G 未映射")
    t.ok(vim.fn.maparg("<C-S-G>", "n") ~= "", "Ctrl+Shift+G 未映射")
    m.callback()
    t.wait(10000, function() return ga().find_win() ~= nil end, "出现注释栏")
    local bwin = ga().find_win()
    local line = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(bwin), 0, 1, false)[1]
    t.ok(ga().sha_at(line), "注释栏第一行没有提交号：" .. tostring(line))
    -- 回车被换成"查看提交"
    t.wait(2000, function()
      local cr = vim.fn.maparg("<CR>", "n", false, true)
      return cr.desc == "查看该提交的改动"
    end, "回车映射")
    -- 在注释栏里按回车：弹出 git show
    vim.api.nvim_set_current_win(bwin)
    vim.fn.maparg("<CR>", "n", false, true).callback()
    t.ok(vim.bo.filetype == "git", "没有弹出提交窗口：" .. vim.bo.filetype)
    t.ok(table.concat(vim.api.nvim_buf_get_lines(0, 0, 5, false), "\n"):find("^commit %x+"), "提交窗口内容不对")
    vim.cmd("close")
    m.callback()
    t.eq(ga().find_win(), nil, "注释栏未关闭")
  end,
  ["3 非 git 文件提示"] = function(t)
    local tmp = vim.fn.tempname() .. ".txt"
    vim.fn.writefile({ "x" }, tmp)
    vim.cmd("edit " .. tmp)
    local msg
    local orig = vim.notify
    vim.notify = function(m) msg = m end
    vim.wait(500)
    ga().toggle()
    vim.notify = orig
    t.ok(msg and msg:find("不在 Git 仓库"), tostring(msg) .. " buftype=" .. vim.bo.buftype .. " name=" .. vim.api.nvim_buf_get_name(0) .. " win=" .. vim.inspect(vim.api.nvim_win_get_config(0).relative))
    t.eq(ga().find_win(), nil)
  end,
}
