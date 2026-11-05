-- 书签：增删、助记符、持久化、行移动后跟随、外部改动后按文字重新定位、列表
local function bm() return require("config.kit.bookmarks") end

-- 用临时文件，不改 fixture
local function tmpfile(lines)
  local f = vim.fn.tempname() .. ".java"
  vim.fn.writefile(lines, f)
  vim.cmd("edit " .. vim.fn.fnameescape(f))
  return vim.api.nvim_get_current_buf(), vim.fs.normalize(f)
end

local function signs(buf)
  local ret = {}
  for _, m in ipairs(vim.api.nvim_buf_get_extmarks(buf, bm().ns, 0, -1, { details = true })) do
    if not m[4].invalid then ret[#ret + 1] = { m[2] + 1, vim.trim(m[4].sign_text or "") } end
  end
  table.sort(ret, function(a, b) return a[1] < b[1] end)
  return ret
end

local function sample()
  local l = {}
  for i = 1, 20 do l[i] = "line " .. i end
  return l
end

return {
  ["0 清空本项目的书签文件"] = function(t)
    local s = bm().store()
    os.remove(s.path)
    bm()._reset()
    t.eq(#bm().store().list, 0)
    t.ok(vim.fn.maparg("<M-F11>", "n") ~= "", "Alt+F11 未映射")
    t.ok(vim.fn.maparg("<C-F11>", "n") ~= "", "Ctrl+F11 未映射")
    t.ok(vim.fn.maparg("<M-S-F11>", "n") ~= "", "Alt+Shift+F11 未映射")
    t.ok(vim.fn.maparg("<leader>mA", "n") ~= "", "空格 m A 未映射")
    t.ok(vim.fn.maparg("<leader>mm", "n") ~= "", "空格 m m 未映射")
  end,

  ["1 切换书签：加上、左侧有图标、再按去掉"] = function(t)
    local buf = tmpfile(sample())
    vim.api.nvim_win_set_cursor(0, { 5, 0 })
    vim.api.nvim_feedkeys(vim.keycode("<M-F11>"), "mx", false)
    t.eq(signs(buf), { { 5, bm().icon } })
    t.eq(#bm().store().list, 1)
    bm().toggle()
    t.eq(signs(buf), {})
    t.eq(#bm().store().list, 0)
  end,

  ["2 助记符：设置、移动到别的行、跳转、弹框按键"] = function(t)
    local buf, file = tmpfile(sample())
    bm().set_mnemonic(buf, 3, "a")
    t.eq(signs(buf), { { 3, "A" } })
    -- 同一个字符设到另一行：从第 3 行移走，第 3 行保留普通书签
    bm().set_mnemonic(buf, 7, "A")
    t.eq(signs(buf), { { 3, bm().icon }, { 7, "A" } })
    -- 弹框：按 1 给第 10 行设置助记符 1
    vim.api.nvim_win_set_cursor(0, { 10, 0 })
    vim.api.nvim_feedkeys("1", "t", false)
    bm().mnemonic_prompt()
    t.eq(signs(buf), { { 3, bm().icon }, { 7, "A" }, { 10, "1" } })
    -- 跳转：先到别的文件，再 空格 m A
    t.open("README.md")
    bm().jump("A")
    t.eq(vim.fs.normalize(vim.api.nvim_buf_get_name(0)), file)
    t.eq(vim.api.nvim_win_get_cursor(0)[1], 7)
    bm().jump("1")
    t.eq(vim.api.nvim_win_get_cursor(0)[1], 10)
    -- 弹框里按 Delete 删除当前行的书签
    vim.api.nvim_feedkeys(vim.keycode("<Del>"), "t", false)
    bm().mnemonic_prompt()
    t.eq(signs(buf), { { 3, bm().icon }, { 7, "A" } })
    for _, b in ipairs(bm().list()) do bm().remove(b) end
  end,

  ["3 编辑时书签跟着行移动，保存时写回行号"] = function(t)
    local buf = tmpfile(sample())
    bm().set_mnemonic(buf, 10, "B")
    vim.api.nvim_buf_set_lines(buf, 2, 2, false, { "new a", "new b", "new c" })
    t.eq(signs(buf), { { 13, "B" } })
    vim.cmd("silent write")
    local data = vim.json.decode(table.concat(vim.fn.readfile(bm().store().path), "\n"))
    t.eq(data.bookmarks[1].line, 13)
    t.eq(data.bookmarks[1].text, "line 10")
    -- 删掉书签所在行：书签随之删除（IDEA 同样）
    vim.api.nvim_buf_set_lines(buf, 12, 13, false, {})
    bm().save()
    t.eq(bm().by_mnemonic("B"), nil)
  end,

  ["4 持久化：写盘后清掉内存，重新读回"] = function(t)
    local buf, file = tmpfile(sample())
    local b = bm().set_mnemonic(buf, 4, "C")
    bm().set_desc(b, "入口")
    bm().toggle(buf, 8)
    bm()._reset()
    local list = bm().list()
    t.eq(#list, 2)
    t.eq({ list[1].file, list[1].line, list[1].mnemonic, list[1].desc, list[1].text }, { file, 4, "C", "入口", "line 4" })
    t.eq({ list[2].line, list[2].mnemonic }, { 8, nil })
    -- 重新打开文件时放回图标
    bm().attach(buf)
    t.eq(signs(buf), { { 4, "C" }, { 8, bm().icon } })
    for _, x in ipairs(bm().list()) do bm().remove(x) end
  end,

  ["5 文件在外部被改动：按该行文字重新定位"] = function(t)
    local buf, file = tmpfile(sample())
    bm().set_mnemonic(buf, 6, "D")
    -- 外部在文件开头插入两行
    local l = sample()
    table.insert(l, 1, "// header 1")
    table.insert(l, 1, "// header 2")
    vim.fn.writefile(l, file)
    vim.cmd("edit!")
    t.eq(signs(buf), { { 8, "D" } })
    t.eq(bm().by_mnemonic("D").line, 8)
    -- 没打开时外部改动：关掉缓冲区后再改文件，重开时定位
    vim.cmd("bwipeout!")
    table.insert(l, 1, "// header 3")
    vim.fn.writefile(l, file)
    vim.cmd("edit " .. vim.fn.fnameescape(file))
    t.eq(signs(0), { { 9, "D" } })
    t.eq(bm().relocate({ "a", "b", "x", "c" }, 1, "x"), 3)
    t.eq(bm().relocate({ "a", "b" }, 9, "zzz"), 2)
    for _, x in ipairs(bm().list()) do bm().remove(x) end
  end,

  ["6 书签列表：显示、删除"] = function(t)
    local buf = tmpfile(sample())
    bm().set_mnemonic(buf, 2, "E")
    bm().toggle(buf, 9)
    local items = bm().items()
    t.eq(#items, 2)
    t.eq(items[1].bm.mnemonic, "E")
    local picker = bm().picker()
    t.wait(3000, function() return picker:count() == 2 end, "列表有 2 项")
    picker.list:view(1)
    picker:action("bookmark_delete")
    t.wait(3000, function() return picker:count() == 1 end, "删除后剩 1 项")
    t.eq(#bm().store().list, 1)
    picker:close()
    for _, x in ipairs(bm().list()) do bm().remove(x) end
  end,
}
