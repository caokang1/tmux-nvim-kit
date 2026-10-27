-- 中文帮助面板：按 空格 h 或 F1 打开，根据当前窗口（文件树 / 搜索 / Java / Markdown / 普通编辑）显示常用操作
local M = {}

local basic = {
  { "编辑（和 IDEA 相同；Ctrl+Shift+字母 不灵时可用 Alt+Shift+字母）" },
  { "i / Esc", "开始输入 / 结束输入（左下角 INSERT 时按字母会打进文字）" },
  { "Ctrl+S", "全部保存" },
  { "Ctrl+Z / Alt+Shift+Z", "撤销 / 重做" },
  { "Ctrl+C / Ctrl+X / Ctrl+V", "复制 / 剪切 / 粘贴（不选中时针对整行）" },
  { "Ctrl+D / Ctrl+Y", "复制一行 / 删除一行" },
  { "Ctrl+/", "注释 / 取消注释" },
  { "Ctrl+A / Ctrl+W", "全选 / 扩大选区（Alt+Shift+W 缩小）" },
  { "Shift+方向键", "选择文字，选中后 Tab / Shift+Tab 缩进" },
  { "Shift+滚轮 / 空格 u w", "左右滚动看长代码（触控板左右滑也可以）/ 切换自动折行" },
  { "Alt+Shift+↑ / ↓", "整行上移 / 下移" },
  { "Ctrl+Alt+L / Ctrl+Alt+O", "格式化 / 整理 import" },
  { "Ctrl+F / Ctrl+R", "在文件中查找 / 替换（F3、Shift+F3 下一个 / 上一个）" },
  { "Ctrl+Shift+F / Ctrl+Shift+R", "在所有文件中查找 / 替换（Alt+C/W/X 大小写/整词/正则）" },
  { ":q! / :qa!", "不保存关闭 / 全部不保存退出" },
}

local files = {
  { "导航（和 IDEA 相同）" },
  { "Ctrl+B Ctrl+B / Ctrl+点击", "跳转到声明（Ctrl+B 是 tmux 前缀，要连按两次）" },
  { "Ctrl+Alt+← / →", "后退 / 前进" },
  { "Ctrl+Shift+N", "查找文件（浏览器里用 Alt+Shift+N）" },
  { "Ctrl+N / Alt+N", "查找类和方法（浏览器里用 Alt+N）" },
  { "Ctrl+E / Ctrl+Shift+E", "最近的文件 / 最近的位置" },
  { "Ctrl+G", "跳转到行" },
  { "Alt+← / → / Ctrl+F4", "切换标签页 / 关闭标签页" },
  { "Alt+1 / Alt+F1", "文件树 / 在文件树中定位当前文件" },
  { "Alt+6 / Alt+7 / Alt+9", "问题 / 结构 / Git 面板" },
  { "Alt+F12", "终端" },
  { "Ctrl+Shift+A", "查找操作（所有快捷键）" },
}

local code = {
  { "代码（和 IDEA 相同）" },
  { "Alt+Enter", "意图操作 / 快速修复（选中代码后可提取方法）" },
  { "Alt+Insert / Ctrl+O", "生成代码 / 重写方法" },
  { "Shift+F6", "重命名" },
  { "Ctrl+Alt+V / Ctrl+Alt+C", "提取变量 / 常量" },
  { "Ctrl+Alt+B / Alt+Shift+B", "跳转到实现 / 类型声明" },
  { "Ctrl+U", "跳转到父类方法" },
  { "Alt+F7", "查找用法" },
  { "Ctrl+H / Ctrl+Alt+H", "类型层级 / 调用层级" },
  { "Ctrl+Q / Ctrl+P", "查看文档 / 参数信息" },
  { "Ctrl+F12", "文件结构" },
  { "Alt+↑ / ↓", "上一个 / 下一个方法" },
  { "F2 / Shift+F2", "下一个 / 上一个问题" },
}

local markdown = {
  { "Markdown" },
  { "空格 u m", "切换渲染效果 / 源码" },
  { "]] / [[", "下一个 / 上一个标题" },
  { "gO", "文件大纲" },
}

local explorer = {
  { "文件树" },
  { "回车 / →", "打开文件或展开目录" },
  { "←", "折叠目录" },
  { "a", "新建文件（名字以 / 结尾则新建目录）" },
  { "r / d", "重命名 / 删除" },
  { "c / m", "复制到… / 移动到…" },
  { "y / p", "复制路径 / 粘贴文件" },
  { "o", "用系统程序打开" },
  { "H / I", "显示或隐藏点文件 / Git 忽略的文件" },
  { "Z", "折叠全部目录" },
  { "Backspace / .", "上一级目录 / 以此目录为根" },
  { "/ 或 i", "输入关键字过滤文件" },
  { "u", "刷新" },
  { "Alt+1 / Esc", "关闭文件树" },
}

local picker = {
  { "搜索窗口" },
  { "直接输入", "过滤结果" },
  { "↑ ↓ / Ctrl+j Ctrl+k", "上下选择" },
  { "回车", "打开" },
  { "Ctrl+v / Ctrl+s", "在左右 / 上下分屏中打开" },
  { "Tab", "多选" },
  { "Alt+h / Alt+i", "显示隐藏文件 / Git 忽略的文件" },
  { "Alt+p", "显示或隐藏预览" },
  { "Esc", "关闭" },
}

local terminal = {
  { "终端" },
  { "Ctrl+\\ Ctrl+n", "回到普通模式（可以滚动、复制）" },
  { "i", "回到终端继续输入" },
}

local function context(buf)
  local ft = vim.bo[buf].filetype
  local bt = vim.bo[buf].buftype
  if ft == "snacks_picker_list" or ft == "snacks_picker_input" then
    local ok, picker_obj = pcall(function()
      return Snacks.picker.get()[1]
    end)
    local is_explorer = ok and picker_obj and picker_obj.opts and picker_obj.opts.source == "explorer"
    if is_explorer then
      return "文件树", { explorer, files }
    end
    return "搜索窗口", { picker }
  end
  if bt == "terminal" then
    return "终端", { terminal, files }
  end
  if ft == "markdown" then
    return "Markdown 文件", { markdown, basic, files }
  end
  if #vim.lsp.get_clients({ bufnr = buf }) > 0 or ft == "java" then
    return (ft ~= "" and ft or "代码") .. " 文件", { code, basic, files }
  end
  return "编辑器", { basic, files, code }
end

local function render(title, sections)
  local lines, marks = {}, {}
  local keyw = 0
  for _, sec in ipairs(sections) do
    for i = 2, #sec do
      keyw = math.max(keyw, vim.fn.strdisplaywidth(sec[i][1]))
    end
  end
  table.insert(lines, " 当前窗口：" .. title)
  table.insert(marks, { #lines - 1, "Title" })
  for _, sec in ipairs(sections) do
    table.insert(lines, "")
    table.insert(lines, " " .. sec[1][1])
    table.insert(marks, { #lines - 1, "Function" })
    for i = 2, #sec do
      local k, d = sec[i][1], sec[i][2]
      local pad = string.rep(" ", keyw - vim.fn.strdisplaywidth(k))
      table.insert(lines, "   " .. k .. pad .. "   " .. d)
      table.insert(marks, { #lines - 1, "Special", 3, 3 + #k })
    end
  end
  table.insert(lines, "")
  table.insert(lines, " 按 a 查看当前窗口的全部快捷键（中文）  ·  空格 后稍等也会弹出菜单  ·  q / Esc 关闭")
  table.insert(marks, { #lines - 1, "Comment" })
  return lines, marks
end

function M.open()
  -- 在命令行窗口（q: 或 q/ 打开的历史窗口）里不能切到别的窗口，先提示退出
  if vim.fn.getcmdwintype() ~= "" then
    vim.notify("当前在命令历史窗口里，先输入 :q 回车退出，再按 F1", vim.log.levels.WARN)
    return
  end
  local src_win = vim.api.nvim_get_current_win()
  local src_buf = vim.api.nvim_get_current_buf()
  local title, sections = context(src_buf)
  local lines, marks = render(title, sections)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "zh_help"
  local ns = vim.api.nvim_create_namespace("zh_help")
  for _, m in ipairs(marks) do
    vim.api.nvim_buf_set_extmark(buf, ns, m[1], m[3] or 0, {
      end_col = m[4] or #lines[m[1] + 1],
      hl_group = m[2],
    })
  end

  local width = 0
  for _, l in ipairs(lines) do
    width = math.max(width, vim.fn.strdisplaywidth(l))
  end
  width = math.min(width + 2, vim.o.columns - 4)
  local height = math.min(#lines, vim.o.lines - 4)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " 帮助 ",
    title_pos = "center",
  })
  vim.wo[win].wrap = false
  vim.wo[win].cursorline = false

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
    if vim.api.nvim_win_is_valid(src_win) then
      vim.api.nvim_set_current_win(src_win)
    end
  end
  -- 面板内容被别的操作换掉时，连同浮窗一起关闭
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then pcall(vim.api.nvim_win_close, win, true) end
      end)
    end,
  })
  -- 光标离开帮助面板（鼠标点了别处、焦点被其他窗口抢走）时自动关闭，避免面板留在屏幕上关不掉
  vim.api.nvim_create_autocmd("WinLeave", {
    buffer = buf,
    once = true,
    callback = function()
      vim.schedule(function()
        if vim.api.nvim_win_is_valid(win) then
          vim.api.nvim_win_close(win, true)
        end
      end)
    end,
  })

  local o = { buffer = buf, nowait = true, silent = true }
  vim.keymap.set("n", "q", close, o)
  vim.keymap.set("n", "<Esc>", close, o)
  vim.keymap.set("n", "<F1>", close, o)
  vim.keymap.set("n", "a", function()
    close()
    vim.schedule(function()
      require("which-key").show({ keys = "", mode = "n" })
    end)
  end, o)
end

return M
