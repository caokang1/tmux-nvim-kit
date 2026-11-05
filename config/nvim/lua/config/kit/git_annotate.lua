-- Git Annotate（IDEA: Annotate with Git Blame）：Alt+Shift+G 在左侧显示每行的提交、作者和日期，再按一次关闭。
-- 用 gitsigns 自带的 blame 窗口（:Gitsigns blame）：左侧竖排、和代码同步滚动、同一提交的行高亮。
-- 在注释栏上按回车：弹出该提交的完整改动（git show），q / Esc 关闭；gitsigns 原来的回车菜单改到 空格+回车。
local K = require("config.idea_keys")
local M = {}

local FT = "gitsigns-blame"

--- 当前标签页里的注释栏窗口
function M.find_win()
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == FT then return win end
  end
end

function M.close()
  local win = M.find_win()
  if win then
    pcall(vim.api.nvim_win_close, win, true)
    return true
  end
  return false
end

function M.toggle()
  if M.close() then return end
  local buf = vim.api.nvim_get_current_buf()
  local ok, cache = pcall(function() return require("gitsigns.cache").cache[buf] end)
  if not ok or not cache then
    local name = vim.api.nvim_buf_get_name(buf)
    if name == "" or vim.bo[buf].buftype ~= "" then
      vim.notify("当前不是文件，无法显示 Git 注释", vim.log.levels.WARN)
    else
      vim.notify("当前文件不在 Git 仓库中（或 Git 还没加载完），无法显示 Git 注释", vim.log.levels.WARN)
    end
    return
  end
  require("gitsigns").blame()
end

--- 从注释栏的一行取提交号（每行以缩写的提交号开头）
---@return string?
function M.sha_at(line)
  local sha = (line or ""):match("^[^%w]*(%x%x%x%x%x%x%x+)")
  if not sha or sha:match("^0+$") then return nil end -- 全 0 是还没提交的改动
  return sha
end

--- 注释栏第 row 行（1 基）属于哪个提交：同一提交连续的几行只有第一行写提交号，其余行往上找
---@return string?
function M.sha_for_row(buf, row)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, row, false)
  for i = #lines, 1, -1 do
    local l = lines[i]
    if l:match("^[^%w]*0000000") then return nil end -- 尚未提交的改动
    local sha = M.sha_at(l)
    if sha then return sha end
  end
end

--- 在浮窗里显示提交的改动（git show），dir 是该文件所在目录（git 在那里能找到仓库）
function M.show_commit(sha, dir)
  local res = vim.system({ "git", "-C", dir, "show", "--stat", "--patch", "--format=fuller", sha }, { text = true }):wait()
  if res.code ~= 0 then
    vim.notify("git show 失败：" .. (res.stderr or ""), vim.log.levels.WARN)
    return
  end
  local lines = vim.split(res.stdout, "\n", { plain = true })
  if lines[#lines] == "" then lines[#lines] = nil end
  return Snacks.win({
    text = lines,
    ft = "git",
    title = " 提交 " .. sha .. "（q 关闭） ",
    title_pos = "center",
    border = "rounded",
    width = 0.85,
    height = 0.85,
    wo = { wrap = false, number = false, relativenumber = false, signcolumn = "no", foldenable = false },
    bo = { modifiable = false, filetype = "git" },
    keys = { q = "close", ["<Esc>"] = "close" },
  })
end

-- gitsigns 设置完窗口后会把回车映射成它的菜单（在设置 filetype 之后），所以延迟到下一轮再覆盖
vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("kit_git_annotate", { clear = true }),
  pattern = FT,
  callback = function(ev)
    -- 打开注释栏时代码窗口是"上一个窗口"，记下它所在的目录
    local src = vim.api.nvim_buf_get_name(vim.fn.winbufnr(vim.fn.winnr("#")))
    local dir = src ~= "" and vim.fs.dirname(src) or vim.fn.getcwd()
    vim.schedule(function()
      if not vim.api.nvim_buf_is_valid(ev.buf) then return end
      local o = { buffer = ev.buf, silent = true, nowait = true }
      vim.keymap.set("n", "<CR>", function()
        local sha = M.sha_for_row(0, vim.api.nvim_win_get_cursor(0)[1])
        if not sha then
          vim.notify("这一行是尚未提交的改动", vim.log.levels.INFO)
          return
        end
        M.show_commit(sha, dir)
      end, vim.tbl_extend("force", o, { desc = "查看该提交的改动" }))
      vim.keymap.set("n", "<leader><CR>", function() vim.cmd.popup("]GitsignsBlame") end,
        vim.tbl_extend("force", o, { desc = "gitsigns 注释菜单（按父提交重新注释、对比等）" }))
      vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", o, { desc = "关闭 Git 注释" }))
    end)
  end,
})

for _, lhs in ipairs({ "<M-G>", "<C-S-G>" }) do
  K.map(K.NI, lhs, K.n(M.toggle), "Git 注释：逐行显示作者和日期（再按关闭，回车看提交）")
end

return M
