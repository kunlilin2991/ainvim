-- 配色完全照搬 vimrc: background=dark + colorscheme jellybeans + 透明背景
return {
  {
    "nanotech/jellybeans.vim",
    lazy = false,
    priority = 1000,
    init = function()
      vim.opt.background = "dark"
      vim.g.jellybeans_overrides = {
        background = { guibg = "none" },
      }
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("AivimTransparentBg", { clear = true }),
        callback = function()
          for _, g in ipairs({
            "Normal", "NormalNC", "NormalFloat", "FloatBorder",
            "SignColumn", "EndOfBuffer", "LineNr", "FoldColumn",
          }) do
            vim.api.nvim_set_hl(0, g, { bg = "none", ctermbg = "NONE" })
          end
          vim.api.nvim_set_hl(0, "CursorLine", { bg = "#303030", ctermbg = 236 })
          -- 鼠标/可视选区: 提高对比度,避免和背景/光标行混在一起
          vim.api.nvim_set_hl(0, "Visual", { bg = "#5a6b8c", fg = "#f8f8f2", ctermbg = 60, ctermfg = 231 })
          vim.api.nvim_set_hl(0, "VisualNOS", { bg = "#5a6b8c", fg = "#f8f8f2", ctermbg = 60, ctermfg = 231 })
          -- 搜索命中
          vim.api.nvim_set_hl(0, "Search", { bg = "#e0af68", fg = "#1c1c1c", ctermbg = 179, ctermfg = 234 })
          vim.api.nvim_set_hl(0, "IncSearch", { bg = "#ff9800", fg = "#000000", ctermbg = 208, ctermfg = 16 })

          for _, g in ipairs({ "Comment", "@comment" }) do
            local cur = vim.api.nvim_get_hl(0, { name = g, link = false })
            vim.api.nvim_set_hl(0, g, vim.tbl_extend("force", cur, {
              italic = false,
              bg = "none",
              ctermbg = "NONE",
            }))
          end
        end,
      })
    end,
  },
  {
    "LazyVim/LazyVim",
    opts = { colorscheme = "jellybeans" },
  },
}
