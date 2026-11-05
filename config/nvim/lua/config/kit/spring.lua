-- 接口地址搜索（IDEA Endpoints / RestfulTool 插件）：Ctrl+\ 或 空格 s U
-- 列出项目里所有 Controller 方法的接口地址，例如 "GET  /api/user/list  UserController#list  demo-app"，
-- 输入地址片段（user/li）过滤，预览并跳到方法。@FeignClient 接口里的映射也列出，标 [Feign]。
--
-- 只做文本解析（ripgrep 先筛出含 Mapping 注解的文件，再用 treesitter 解析），不依赖 jdtls，
-- 大项目没导入完也能用。支持类上的 @RequestMapping 前缀、value/path/数组、常量和常量拼接
-- （ApiConst.API_PREFIX + "/x"，跨文件跨模块），解析不了的常量显示为 ${ApiConst.X}。
-- 结果按文件修改时间缓存（连同用到的常量文件），第二次打开只重新解析改过的文件。
local K = require("config.idea_keys")
local U = require("config.kit.spring.util")
local J = require("config.kit.spring.java")

local M = {}

local http = {
  GetMapping = "GET",
  PostMapping = "POST",
  PutMapping = "PUT",
  DeleteMapping = "DELETE",
  PatchMapping = "PATCH",
  RequestMapping = false, -- 由 method = 参数决定
}

-- 拼接类前缀和方法路径：保证以 / 开头，去掉重复的 /
function M.join(prefix, path)
  local s = "/" .. (prefix or "") .. "/" .. (path or "")
  s = s:gsub("/+", "/")
  if #s > 1 then s = s:gsub("/$", "") end
  return s
end

local function methods_of(name, args, ctx)
  if http[name] then return http[name] end
  local m = args.method
  if not m then return "ALL" end
  local list = {}
  if m:type() == "element_value_array_initializer" then
    for c in m:iter_children() do
      if c:named() and c:type() ~= "comment" then list[#list + 1] = J.last_name(c, ctx.info.src) end
    end
  else
    list[1] = J.last_name(m, ctx.info.src)
  end
  return #list > 0 and table.concat(list, "|") or "ALL"
end

local function paths_of(args, ctx)
  local node = args.value or args.path
  local list = J.eval_list(node, ctx)
  if #list == 0 then list = { "" } end
  return list
end

-- 解析一个 Java 文件里的接口。返回 endpoints 列表和用到的其他文件（常量所在文件）
function M.parse_file(path, root)
  local info = J.file(path)
  if not info then return {}, {} end
  local ctx = { info = info, root = root, deps = {} }
  local src = info.src
  local res = {}
  local module = U.module_of(path)
  for _, c in ipairs(info.classes) do
    local node = c.node
    local anns = J.annotations(node, src)
    local feign = anns.FeignClient ~= nil
    local is_ctrl = anns.RestController or anns.Controller or feign
    -- 只看顶层类 / 接口（内部类不会是 Controller）
    if is_ctrl and node:parent() and node:parent():type() == "program" then
      local prefixes = { "" }
      if anns.RequestMapping then prefixes = paths_of(anns.RequestMapping, ctx) end
      if feign and anns.FeignClient.path then
        local fp = J.eval(anns.FeignClient.path, ctx)
        for i, p in ipairs(prefixes) do prefixes[i] = M.join(fp, p) end
      end
      local body = node:field("body")[1]
      for member in body:iter_children() do
        if member:type() == "method_declaration" then
          local manns = J.annotations(member, src)
          for ann, _ in pairs(http) do
            local args = manns[ann]
            if args then
              local name_node = member:field("name")[1]
              local mname = J.text(name_node, src)
              local row, col = name_node:range()
              local verb = methods_of(ann, args, ctx)
              for _, prefix in ipairs(prefixes) do
                for _, p in ipairs(paths_of(args, ctx)) do
                  res[#res + 1] = {
                    method = verb,
                    path = M.join(prefix, p),
                    class = c.name,
                    name = mname,
                    module = module,
                    feign = feign,
                    file = path,
                    lnum = row + 1,
                    col = col,
                  }
                end
              end
            end
          end
        end
      end
    end
  end
  return res, ctx.deps
end

-- 缓存：路径 → { mtime, deps = { 路径 = mtime }, endpoints }
local cache = {}

local function fresh(entry, path)
  if entry.mtime ~= U.mtime(path) then return false end
  for p, mt in pairs(entry.deps) do
    if U.mtime(p) ~= mt then return false end
  end
  return true
end

-- 收集项目里的所有接口，按地址排序
function M.collect(root)
  root = root or U.root()
  local files = U.rg({ "-l", "-g", "*.java", "-e", "@(Get|Post|Put|Delete|Patch|Request)Mapping\\b", "." }, root)
  local all = {}
  for _, f in ipairs(files) do
    local e = cache[f]
    if not (e and fresh(e, f)) then
      local mt = U.mtime(f)
      local eps, deps = M.parse_file(f, root)
      e = { mtime = mt, deps = deps, endpoints = eps }
      cache[f] = e
    end
    vim.list_extend(all, e.endpoints)
  end
  table.sort(all, function(a, b)
    if a.path ~= b.path then return a.path < b.path end
    return a.method < b.method
  end)
  return all
end

function M.open()
  local root = U.root()
  local eps = M.collect(root)
  if #eps == 0 then
    vim.notify("没有找到接口（@RestController / @Controller / @FeignClient 中的 @XxxMapping）", vim.log.levels.INFO)
    return
  end
  local wm, wp, wc = 4, 10, 10
  local items = {}
  for i, e in ipairs(eps) do
    wm = math.max(wm, #e.method)
    wp = math.max(wp, vim.fn.strdisplaywidth(e.path))
    wc = math.max(wc, #(e.class .. "#" .. e.name))
    items[i] = vim.tbl_extend("force", e, {
      idx = i,
      text = e.path .. " " .. e.method .. " " .. e.class .. "#" .. e.name .. (e.feign and " Feign" or ""),
      pos = { e.lnum, e.col },
    })
  end
  wp = math.min(wp, 60)
  local function pad(s, w) return s .. string.rep(" ", math.max(w - vim.fn.strdisplaywidth(s), 0)) end
  Snacks.picker.pick({
    title = "接口地址（" .. #items .. " 个）",
    items = items,
    format = function(item)
      return {
        { pad(item.method, wm) .. "  ", "Keyword" },
        { pad(item.path, wp) .. "  ", "String" },
        { pad(item.class .. "#" .. item.name, wc) .. "  ", "Function" },
        { item.module, "Comment" },
        { item.feign and "  [Feign]" or "", "Special" },
      }
    end,
    preview = "file",
    layout = { preset = "vertical" },
    confirm = function(picker, item)
      picker:close()
      if item then U.jump(item.file, item.lnum, item.col) end
    end,
  })
end

K.map(K.NI, "<C-\\>", K.n(M.open), "查找接口地址（IDEA RestfulTool: Ctrl+\\）")
K.map("n", "<leader>sU", M.open, "查找接口地址（Spring 接口）")

return M
