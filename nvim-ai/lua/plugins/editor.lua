-- 编辑增强:大纲/任务/括号配色/缩进线/文件树
return {
  -- 大纲(vimrc: tagbar F9 / ;tb);用 treesitter,不依赖 ctags
  {
    "stevearc/aerial.nvim",
    cmd = { "AerialToggle", "AerialOpen" },
    dependencies = { "nvim-treesitter/nvim-treesitter" },
    opts = {
      backends = { "treesitter", "markdown", "man" },
      layout = { width = 48, default_direction = "right" },
      attach_mode = "global",
      show_guides = true,
    },
  },

  -- TODO/FIXME/HACK 列表(vimrc: TaskList ;td)
  {
    "folke/todo-comments.nvim",
    cmd = { "TodoTrouble", "TodoQuickFix", "TodoLocList" },
    opts = {
      keywords = {
        MODIFY = { icon = " ", color = "hint" },
      },
    },
  },

  -- 括号配色(vimrc: rainbow)
  { "HiPhish/rainbow-delimiters.nvim", event = "BufReadPost" },

  -- 缩进线(vimrc: indentLine, F8 切换)
  {
    "Yggdroot/indentLine",
    lazy = false,
    init = function()
      vim.g.indentLine_char_list = { "|", "¦", "┆", "┊" }
      vim.g.indentLine_concealcursor = "inc"
      vim.g.indentLine_conceallevel = 1
      vim.g.vim_json_conceal = 0
    end,
  },

  -- 文件树(vimrc: NERDTree, ;n 切换)
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "MunifTanjim/nui.nvim",
      "nvim-tree/nvim-web-devicons",
    },
    cmd = { "Neotree" },
    opts = {
      filesystem = { follow_current_file = { enabled = true } },
    },
  },
}
