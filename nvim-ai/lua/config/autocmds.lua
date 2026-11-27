-- autocmds.lua —— 少量必要的行为固定
local grp = vim.api.nvim_create_augroup("Aivim", { clear = true })

-- 内核/C 文件强制 8 宽 tab/noexpandtab,防止 LazyVim 的 filetype 默认改回空格
vim.api.nvim_create_autocmd("FileType", {
  group = grp,
  pattern = { "c", "cpp", "objc", "objcpp", "make" },
  callback = function()
    vim.opt_local.tabstop = 8
    vim.opt_local.shiftwidth = 8
    vim.opt_local.softtabstop = -1
    vim.opt_local.expandtab = false
    vim.opt_local.smarttab = false
    vim.opt_local.autoindent = true
    vim.opt_local.smartindent = true
  end,
  desc = "kernel style: 8-wide tabs, noexpandtab",
})

-- quickfix 窗口里按 q 直接关闭(等价 :cclose)
vim.api.nvim_create_autocmd("FileType", {
  group = grp,
  pattern = "qf",
  callback = function(ev)
    vim.keymap.set("n", "q", "<cmd>cclose<cr>", {
      buffer = ev.buf,
      silent = true,
      desc = "关闭 quickfix 窗口",
    })
  end,
  desc = "quickfix: q 关闭窗口",
})


-- 剪贴板: SSH 环境下确保 clipboard 选项生效(可能被插件覆盖)
vim.api.nvim_create_autocmd("VimEnter", {
  group = grp,
  callback = function()
    if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
      if type(vim.g.clipboard) == "table" then
        vim.opt.clipboard = "unnamedplus"
      end
    end
  end,
  desc = "ssh: 启用 unnamedplus(OSC52)",
})

-- 注册 gtags 索引模块的 autocmd/命令(打开新工作区自动检测/后台建库)
pcall(require, "aivim.index")
