-- 依赖库 / 反编译文件（jdt://...）的显示名：标签栏显示 ArrayList.class，状态栏显示 jar › 类名
-- 逻辑在 config/kit/libfiles.lua，这里只把它接到 bufferline、lualine 上
local function lib() return require("config.kit.libfiles") end

return {
  {
    "akinsho/bufferline.nvim",
    opts = function(_, opts)
      opts.options = opts.options or {}
      local orig = opts.options.name_formatter
      opts.options.name_formatter = function(buf)
        if buf.path and buf.path:find("^jdt://") then
          return lib().display_name(buf.path, buf.bufnr)
        end
        if orig then return orig(buf) end
      end
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    opts = function(_, opts)
      local c = opts.sections and opts.sections.lualine_c
      if not c then return end
      -- LazyVim 的文件名组件（pretty_path）紧跟在只显示图标的 filetype 组件后面；依赖库文件时换成 "jar › 类名"
      for i, comp in ipairs(c) do
        local nxt = c[i + 1]
        if type(comp) == "table" and comp[1] == "filetype" and type(nxt) == "table" and type(nxt[1]) == "function" then
          local orig = nxt[1]
          nxt[1] = function(self, ...)
            local s = lib().statusline(0)
            if s then return s end
            return orig(self, ...)
          end
          break
        end
      end
    end,
  },
}
