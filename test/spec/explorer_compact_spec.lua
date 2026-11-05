local function ec() return require("config.kit.explorer_compact") end
local function explorer() return Snacks.picker.get({ source = "explorer" })[1] end
local function lines()
  local p = explorer()
  return p and table.concat(vim.api.nvim_buf_get_lines(p.list.win.buf, 0, -1, false), "\n") or ""
end
-- 列表缓冲区只渲染可见的几十行，检查完整的树用列表项（压缩节点取显示名）
local function names()
  local out = {}
  for item in explorer():iter() do
    out[#out + 1] = item.compact or vim.fs.basename(item.file)
  end
  return table.concat(out, "\n") .. "\n"
end
local function find_item(pred)
  for item in explorer():iter() do
    if pred(item) then return item end
  end
end
return {
  ["1 压缩计算：单子目录链合并"] = function(t)
    t.eq(ec().compress({
      ["pom.xml"] = true,
      src = { main = { java = { com = { example = { demo = { ["A.java"] = true, service = { ["B.java"] = true } } } } }, resources = { ["a.yml"] = true } } },
      empty = { a = { b = {} } },
    }), {
      "empty/a/b",
      "src/main",
      "  java/com/example/demo",
      "    service",
      "      B.java",
      "    A.java",
      "  resources",
      "    a.yml",
      "pom.xml",
    })
  end,
  ["2 打开文件树后出现 com/example/demo 合并节点"] = function(t)
    t.open("demo-app/src/main/java/com/example/demo/service/impl/UserServiceImpl.java")
    Snacks.explorer({ cwd = t.fixture })
    t.wait(5000, function() return lines():find("java/com/example/demo") ~= nil end, "合并节点：\n" .. lines())
    local text = lines()
    t.ok(not text:find("\n[^\n]*[│ ]com\n"), "中间目录 com 不应单独显示")
    t.ok(text:find("UserServiceImpl.java"), "跟随当前文件")
    -- 当前文件仍被选中（follow_file）
    t.wait(3000, function()
      local cur = explorer():current()
      return cur and cur.file:find("UserServiceImpl.java$")
    end, "定位当前文件")
  end,
  ["3 折叠 / 展开整条链"] = function(t)
    local p = explorer()
    local node = find_item(function(i) return i.compact and i.file:find("demo%-app/src/main/java/com/example/demo$") end)
    t.ok(node, "找不到压缩节点")
    t.eq(node.compact, "java/com/example/demo")
    p.list:view(node.idx)
    p:action("confirm") -- 折叠
    t.wait(3000, function() return not lines():find("UserServiceImpl.java") end, "折叠后子项消失")
    node = find_item(function(i) return i.compact == "java/com/example/demo" end)
    t.ok(node and not node.open, "折叠后仍应显示压缩节点")
    -- 在折叠的压缩节点上按 ←：跳到 main（链的上一级）
    p.list:view(node.idx)
    p:action("explorer_close")
    t.wait(3000, function()
      local cur = p:current()
      return cur and cur.file:find("demo%-app/src/main$")
    end, "← 跳到上一级：" .. tostring(p:current() and p:current().file) .. "\n" .. lines())
    -- snacks 原有行为：在折叠的目录上按 ← 会同时折叠上一级；再展开 main
    p:action("confirm")
    t.wait(3000, function() return find_item(function(i) return i.compact == "java/com/example/demo" end) ~= nil end, "展开 main")
    vim.wait(300)
    node = find_item(function(i) return i.compact == "java/com/example/demo" end)
    p.list:view(node.idx)
    t.eq(p:current().compact, "java/com/example/demo")
    p:action("confirm") -- 展开
    t.wait(3000, function() return lines():find("controller") ~= nil end, "展开后显示子目录：\n" .. lines())
  end,
  ["4 新建 / 删除文件后显示正确"] = function(t)
    -- demo-common 下 src/main/java/com/example/common 整条合并（src 下只有 main）
    local dir = t.fixture .. "/demo-common/src/main/java/com/example"
    local p = explorer()
    require("snacks.explorer.tree"):open(dir .. "/common")
    require("snacks.explorer.actions").update(p, { refresh = true })
    t.wait(3000, function() return names():find("java/com/example/common") ~= nil end, "demo-common 合并节点：\n" .. names())
    -- 在中间目录 example 下新建文件 → example 不再是空包，链断开为 src/main/java/com/example + common
    local f = dir .. "/Tmp_explorer_compact.java"
    vim.fn.writefile({ "class Tmp {}" }, f)
    local ok, err = pcall(function()
      require("snacks.explorer.tree"):refresh(dir)
      require("snacks.explorer.actions").update(p, { refresh = true })
      t.wait(3000, function() return names():find("Tmp_explorer_compact.java") ~= nil end, "新文件出现：\n" .. names())
      t.ok(names():find("\nsrc/main/java/com/example\ncommon\n"), "应显示 java/com/example 和 common：\n" .. names())
    end)
    vim.fn.delete(f)
    t.ok(ok, err)
    require("snacks.explorer.tree"):refresh(dir)
    require("snacks.explorer.actions").update(p, { refresh = true })
    t.wait(3000, function() return names():find("java/com/example/common") ~= nil end, "删除后恢复合并：\n" .. names())
  end,
  ["5 空格 u P 关闭后恢复原样"] = function(t)
    ec().enabled = false
    ec().refresh()
    t.wait(3000, function() return not lines():find("com/example") end, "关闭后不再合并：\n" .. lines())
    ec().enabled = true
    ec().refresh()
    t.wait(3000, function() return lines():find("com/example") ~= nil end, "重新开启")
  end,
}
