-- treesitter: C/C++ 高亮;解析器本地编译/下载,不需要 compile_commands.json
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "c", "cpp", "lua", "vim", "vimdoc", "bash", "make", "json", "yaml",
      },
    },
  },
}
