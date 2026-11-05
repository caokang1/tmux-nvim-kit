-- properties 里的 \uXXXX 显示为中文
local pv = function() return require("config.kit.properties_view") end

-- 反斜杠 u 转义：用拼接写，避免源码里直接出现转义序列
local B = string.char(92)
local function U(...)
  local out = {}
  for _, h in ipairs({ ... }) do out[#out + 1] = B .. "u" .. h end
  return table.concat(out)
end

local function tmp_props(lines)
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local f = dir .. "/messages_zh_CN.properties"
  vim.fn.writefile(lines, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))
  return vim.api.nvim_get_current_buf(), f
end

return {
  ["1 转义解析（含代理对、双反斜杠不算）"] = function(t)
    local e = pv().escapes
    t.eq(e("a=" .. U("7528", "6237") .. "x"), { { s = 2, e = 14, text = "用户" } })
    t.eq(e("a=" .. U("D83D", "DE00"))[1].text, "😀")
    t.eq(e("a=" .. B .. U("0041")), {})
    t.eq(e("a=" .. B .. B .. U("0041")), { { s = 4, e = 10, text = "A" } })
    t.eq(#e("a=" .. B .. "u12"), 0)
  end,

  ["2 打开 properties 显示中文，文件内容不变"] = function(t)
    local buf, f = tmp_props({
      "# " .. U("63d0", "793a"),
      "user.not.found=" .. U("7528", "6237", "4e0d", "5b58", "5728"),
      "user.saved=" .. U("4fdd", "5b58", "6210", "529f") .. ": {0}",
      "plain.text=hello",
    })
    t.eq(vim.bo[buf].filetype, "jproperties")
    local m = pv()
    t.eq(m.display_line(buf, 1), "user.not.found=用户不存在")
    t.eq(m.display_line(buf, 2), "user.saved=保存成功: {0}")
    t.eq(m.display_line(buf, 3), "plain.text=hello")
    t.eq(vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1], "user.not.found=" .. U("7528", "6237", "4e0d", "5b58", "5728"))
    t.eq(vim.wo.conceallevel, 2)
    vim.cmd("write")
    t.eq(vim.fn.readfile(f)[2], "user.not.found=" .. U("7528", "6237", "4e0d", "5b58", "5728"), "文件内容被改写")
  end,

  ["3 改动后只刷新改动的行；插入模式光标行显示原文"] = function(t)
    local buf = tmp_props({ "a=" .. U("7528"), "b=" .. U("6237") })
    local m = pv()
    t.eq(m.display_line(buf, 0), "a=用")
    local before = vim.api.nvim_buf_get_extmarks(buf, m.ns, { 1, 0 }, { 1, -1 }, {})[1][1]
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "a=" .. U("4e2d", "6587") })
    t.wait(1000, function() return m.display_line(buf, 0) == "a=中文" end, "改动行没有刷新")
    local after = vim.api.nvim_buf_get_extmarks(buf, m.ns, { 1, 0 }, { 1, -1 }, {})[1][1]
    t.eq(after, before, "没改动的行被重新计算了")
    -- 插入模式：光标所在行没有 extmark（显示原文），离开后恢复
    vim.api.nvim_win_set_cursor(0, { 2, 0 })
    vim.api.nvim_exec_autocmds("InsertEnter", { buffer = buf })
    t.eq(#vim.api.nvim_buf_get_extmarks(buf, m.ns, { 1, 0 }, { 1, -1 }, {}), 0, "插入模式光标行仍显示文字")
    t.eq(m.display_line(buf, 0), "a=中文", "其他行应仍显示文字")
    vim.api.nvim_exec_autocmds("InsertLeave", { buffer = buf })
    t.wait(1000, function() return m.display_line(buf, 1) == "b=户" end, "离开插入模式后没有恢复")
  end,
}
