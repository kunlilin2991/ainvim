-- bufferline:只显示「序号 + 文件名」
-- 去掉:文件类型图标、诊断标记、修改点、关闭 x、左右关闭图标、指示条。
-- numbers = "ordinal" 与 ;1..;12(BufferLineGoToBuffer) 的序号一致。
return {
  {
    "akinsho/bufferline.nvim",
    opts = function(_, opts)
      opts.options = vim.tbl_deep_extend("force", opts.options or {}, {
        numbers = "ordinal",
        show_buffer_icons = false,
        show_buffer_close_icons = false,
        show_close_icon = false,
        buffer_close_icon = "",
        close_icon = "",
        modified_icon = "",
        indicator = { style = "none", icon = "" },
        diagnostics = false,
        show_tab_indicators = false,
        show_duplicate_prefix = false,
        separator_style = "thin",
        padding = 0,
        tab_size = 0,
        max_name_length = 40,
        color_icons = false,
        name_formatter = function(buf)
          return vim.fn.fnamemodify(buf.name, ":t")
        end,
        get_element_icon = function()
          return ""
        end,
      })
      return opts
    end,
  },
}
