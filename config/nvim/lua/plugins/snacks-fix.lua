-- 修复 snacks 搜索框的一个时序问题：在搜索框里输入后约 30 毫秒内关闭（Esc、回车、切换窗口），
-- 延迟执行的刷新会报 "input.lua:89: attempt to index field 'picker' (a nil value)"。
-- 原因是关闭时立刻清空了 input.picker，延迟刷新拿不到它；这里改为 0.2 秒后再清空，
-- 刷新时 picker 已标记为关闭，会直接返回（picker:find 开头有 closed 检查）。
return {
  {
    "folke/snacks.nvim",
    init = function()
      vim.api.nvim_create_autocmd("User", {
        pattern = "VeryLazy",
        once = true,
        callback = function()
          local ok, Input = pcall(require, "snacks.picker.core.input")
          if not ok or Input._close_patched then
            return
          end
          Input._close_patched = true
          function Input:close()
            self.win:destroy()
            vim.defer_fn(function()
              self.picker = nil -- 仍然释放引用，便于回收内存
            end, 200)
          end
        end,
      })
    end,
  },
}
