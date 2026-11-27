-- 从 vimrc 原样移植的老牌插件:按键语义优先
return {
  -- easymotion(vimrc: <leader><leader>w / f)
  {
    "easymotion/vim-easymotion",
    lazy = false,
    init = function()
      vim.g.EasyMotion_do_mapping = 0 -- 不用插件默认键,只保留 vimrc 的两个
      vim.g.EasyMotion_smartcase = 1
    end,
  },

  -- nerdcommenter(vimrc: ;cc ;cu ;cn ;cA)
  {
    "preservim/nerdcommenter",
    lazy = false,
    init = function()
      vim.g.NERDCreateDefaultMappings = 0
      vim.g.NERDSpaceDelims = 1
      vim.g.NERDCompactSexyComs = 1
      vim.g.NERDDefaultAlign = "left"
      vim.g.NERDAltDelims_java = 1
      vim.g.NERDCustomDelimiters = { c = { left = "/**", right = "*/" } }
      vim.g.NERDCommentEmptyLines = 1
      vim.g.NERDTrimTrailingWhitespace = 1
    end,
  },

  -- vim-easy-align(vimrc: visual <Enter>)
  {
    "junegunn/vim-easy-align",
    lazy = false,
  },

  -- NERDTree(vimrc: <leader>n;支持 .. 上级、子目录展开、书签)
  {
    "preservim/nerdtree",
    cmd = { "NERDTreeToggle", "NERDTree", "NERDTreeFind" },
    init = function()
      vim.g.NERDTreeShowHidden = 0
      -- 左对齐
      vim.g.NERDTreeWinPos = "left"
      -- 宽度: 约 20% 宽度,夹在 16~30 列之间(竖屏也不挤)
      local function tree_width()
        return math.max(16, math.min(30, math.floor(vim.o.columns * 0.2)))
      end
      vim.g.NERDTreeWinSize = tree_width()
      vim.g.NERDTreeMinimalUI = 1
      vim.g.NERDTreeDirArrows = 1
      vim.g.NERDTreeAutoDeleteBuffer = 1
      vim.g.NERDTreeHighlightCursorline = 1
      vim.g.NERDTreeIgnore = { '\\.pyc$', '\\.pyo$', '\\.obj$', '\\.o$', '\\.so$', '\\.egg$', '^\\.git$', '^\\.svn$', '^\\.hg$' }
      vim.g.NERDTreeWinSizeMax = tree_width()
      -- 每次打开前按当前宽度重算,适配终端 resize
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "nerdtree",
        callback = function()
          local width = tree_width()
          vim.g.NERDTreeWinSize = width
          vim.g.NERDTreeWinSizeMax = width
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            if vim.bo[vim.api.nvim_win_get_buf(win)].filetype == "nerdtree" then
              pcall(vim.api.nvim_win_set_width, win, width)
            end
          end
        end,
      })

      -- 关闭 NERDTree 时若只剩它一个窗口则退出
      vim.api.nvim_create_autocmd("BufEnter", {
        callback = function()
          if vim.fn.winnr("$") == 1
            and vim.bo.buftype == ""
            and vim.bo.filetype == "nerdtree" then
            vim.cmd("quit")
          end
        end,
      })
    end,
  },

  -- a.vim(vimrc: ;a 头/源切换)
  {
    "vim-scripts/a.vim",
    cmd = { "A" },
  },

  -- ALE(vimrc: gcc 风格 + <C-k>/<C-j>)
  -- 内核/vendor 路径默认不自动跑,避免没有 compile flags 时的满屏误报。
  {
    "dense-analysis/ale",
    event = { "BufReadPre", "BufNewFile" },
    init = function()
      vim.g.ale_sign_column_always = 1
      vim.g.ale_sign_error = ">>"
      vim.g.ale_sign_warning = "--"
      vim.g.ale_echo_msg_error_str = "E"
      vim.g.ale_echo_msg_format = "[%linter%] %s [%severity%]"
      vim.g.ale_linters_explicit = 1
      vim.g.ale_linters = { c = { "gcc" }, cpp = { "gcc" } }
      vim.g.ale_completion_enabled = 0
      vim.g.ale_lint_on_text_changed = "normal"
      vim.g.ale_lint_on_insert_leave = 1
      vim.g.ale_lint_delay = 500
      vim.g.ale_echo_delay = 20
      vim.g.ale_c_gcc_options = "-Wall -O2 -std=c99"
      vim.g.ale_cpp_gcc_options = "-Wall -O2 -std=c++14"
      vim.g.ale_pattern_options = {
        [".*/kernel_platform/.*"] = { ale_enabled = 0 },
        [".*/vendor/.*"] = { ale_enabled = 0 },
      }
    end,
  },
}
