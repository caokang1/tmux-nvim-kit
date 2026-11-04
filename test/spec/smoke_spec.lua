return {
  ["1 配置能加载、IDEA 键位存在"] = function(t)
    t.ok(vim.fn.maparg("<C-b>", "n") ~= "", "Ctrl+B 未映射")
    t.ok(package.loaded["config.kit"], "config.kit 未加载")
  end,
  ["2 jdtls 能导入示例项目并跳转到定义"] = function(t)
    t.open("demo-app/src/main/java/com/example/demo/controller/UserController.java")
    t.wait_jdtls()
    t.cursor_at("listUsers")
    local res = vim.lsp.buf_request_sync(0, "textDocument/definition",
      vim.lsp.util.make_position_params(0, "utf-16"), 20000)
    local uri
    for _, r in pairs(res or {}) do
      local loc = r.result and (r.result[1] or r.result)
      uri = loc and (loc.uri or loc.targetUri)
    end
    t.ok(uri and uri:find("UserService.java"), "定义不在 UserService.java：" .. tostring(uri))
  end,
}
