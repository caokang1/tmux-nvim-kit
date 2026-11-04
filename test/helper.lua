-- 极简测试框架：spec 文件返回 { ["用例名"] = function(t) ... end }，按名字顺序执行
local M = {}
local root = vim.env.NVIM_KIT_ROOT
M.fixture = root .. "/test/fixtures/demo"

function M.eq(a, b, msg)
  if not vim.deep_equal(a, b) then
    error(string.format("%s\n  期望: %s\n  实际: %s", msg or "不相等", vim.inspect(b), vim.inspect(a)), 2)
  end
end
function M.ok(v, msg) if not v then error(msg or "断言失败", 2) end end

-- 等待条件成立（会处理事件循环），超时报错
function M.wait(ms, cond, msg)
  if not vim.wait(ms, cond, 50) then error("等待超时：" .. (msg or ""), 2) end
end

-- 打开 fixture 里的文件
function M.open(rel)
  vim.cmd("edit " .. vim.fn.fnameescape(M.fixture .. "/" .. rel))
  return vim.api.nvim_get_current_buf()
end

-- 把光标放到第一个匹配 pattern 的位置（1 基行号）
function M.cursor_at(pattern)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, l in ipairs(lines) do
    local c = l:find(pattern)
    if c then vim.api.nvim_win_set_cursor(0, { i, c - 1 }) return i, c end
  end
  error("找不到：" .. pattern, 2)
end

-- 等 jdtls 附加并完成导入：能按名字搜到示例项目里的类即视为就绪
function M.wait_jdtls(ms)
  local deadline = vim.uv.now() + (ms or 300000)
  M.wait(60000, function() return #vim.lsp.get_clients({ name = "jdtls", bufnr = 0 }) > 0 end, "jdtls 附加")
  while vim.uv.now() < deadline do
    local res = vim.lsp.buf_request_sync(0, "workspace/symbol", { query = "UserServiceImpl" }, 5000)
    for _, r in pairs(res or {}) do
      if r.result and #r.result > 0 then return end
    end
    vim.wait(1000)
  end
  error("等待超时：jdtls 导入项目", 2)
end

function M.run(file)
  vim.fn.chdir(M.fixture)
  -- 无界面启动不会触发 VeryLazy（LazyVim 在这时加载按键 / 自动命令），手动触发
  if vim.fn.maparg("<C-b>", "n") == "" then
    vim.api.nvim_exec_autocmds("User", { pattern = "VeryLazy", modeline = false })
  end
  local ok, spec = pcall(dofile, file)
  if not ok then io.stdout:write("加载失败：" .. spec .. "\n") vim.cmd("cquit 1") end
  local names = vim.tbl_keys(spec)
  table.sort(names)
  local failed = 0
  for _, name in ipairs(names) do
    local ok2, err = xpcall(spec[name], debug.traceback, M)
    if ok2 then
      io.stdout:write("  ✓ " .. name .. "\n")
    else
      failed = failed + 1
      io.stdout:write("  ✗ " .. name .. "\n    " .. tostring(err):gsub("\n", "\n    ") .. "\n")
    end
  end
  io.stdout:write(string.format("  %d 通过，%d 失败\n", #names - failed, failed))
  vim.cmd(failed > 0 and "cquit 1" or "qall!")
end

return M
