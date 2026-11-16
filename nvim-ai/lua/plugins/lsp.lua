-- 无 LSP 设计:高亮走 treesitter、跳转/引用走 gtags、补全走 gtags+buffer+path。
-- 显式关掉 clangd,避免它在没有 compile_commands.json 的内核/vendor 树里满屏诊断。
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        clangd = { enabled = false },
      },
    },
  },
  {
    "mason-org/mason-lspconfig.nvim",
    opts = { ensure_installed = {} },
  },
}
