-- nvim-ai: 基于 vimrc 习惯的 AI 时代 Neovim 配置
-- leader 必须在加载插件前设置(与 ~/.vimrc 一致: leader = ";")
vim.g.mapleader = ";"
-- localleader 保持默认 "\"; 不要设成 ";",否则会和 ";m = %" 以及 agentic 面板键冲突
vim.g.maplocalleader = "\\"

require("config.lazy")
