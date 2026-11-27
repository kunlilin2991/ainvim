-- options.lua —— 逐条移植 ~/.vimrc 的编辑器设置
-- 本文件在 LazyVim 默认 options 之后加载,因此这里的设置会覆盖 LazyVim 默认。
local opt = vim.opt

-- leader = ";"(install 前已设;这里再设一次,防止 LazyVim 覆盖)
vim.g.mapleader = ";"
vim.g.maplocalleader = "\\"

-- 关闭 LazyVim 的保存自动格式化;内核代码不能被自动格式化
vim.g.autoformat = false

-- 缩进:kernel 风格 8 宽 tab,不展开(vimrc: noexpandtab/shiftwidth=8/tabstop=8/softtabstop=-1)
opt.tabstop = 8
opt.shiftwidth = 8
opt.softtabstop = -1
opt.expandtab = false
opt.smarttab = false
opt.autoindent = true
opt.smartindent = true

-- 行号(vimrc: number + relativenumber)
opt.number = true
opt.relativenumber = true

-- 光标行/列(vimrc: cursorline; cursorcolumn 被注释)
opt.cursorline = true
opt.cursorcolumn = false

-- 编辑行尽量保持在屏幕中部(vimrc: scrolloff=15)
opt.scrolloff = 15

-- 搜索(vimrc: hlsearch/incsearch/ignorecase/smartcase/showmatch)
opt.hlsearch = true
opt.incsearch = true
opt.ignorecase = true
opt.smartcase = true
opt.showmatch = true

-- 折叠(vimrc: foldmethod=manual)
opt.foldenable = true
opt.foldmethod = "manual"

-- 鼠标:vimrc 是 mouse=c(仅命令行),但 AI chat/quickfix/help 需要滚轮,
-- 这里改为 a;若只想要滚轮不想要点击定位,可改成 "nvi"。
opt.mouse = "a"

-- 退格(vimrc: backspace=indent,eol,start)
opt.backspace = "indent,eol,start"

-- 拼写语言(vimrc: spelllang=en_us);spell 默认关
opt.spelllang = { "en_us" }

-- 状态栏(vimrc: laststatus=2/ruler/showmode/showcmd/wildmenu)
opt.laststatus = 2
opt.ruler = true
opt.showmode = true
opt.showcmd = true
opt.wildmenu = true
opt.shortmess:append("c")

-- 文件切换(vimrc: set hidden,避免必须保存才能跳 buffer)
opt.hidden = true

-- 自动切 cwd(vimrc: set autochdir);索引/工程检测全部用绝对路径,不受 cwd 影响
opt.autochdir = true

-- 显示原字符(vimrc 未设 conceallevel;LazyVim 默认 2 会吃掉 markdown 符号)
opt.conceallevel = 0

-- 补全(vimrc: cpt=.,k,w,b + completeopt=menu,menuone,noselect)
opt.cpt = { ".", "k", "w", "b" }
opt.completeopt = { "menu", "menuone", "noselect" }

-- 编码/颜色(vimrc: encoding=utf-8/t_Co=256/background=dark/termguicolors)
opt.background = "dark"
if vim.fn.has("termguicolors") == 1 then
  opt.termguicolors = true
end

-- 性能/体验
opt.updatetime = 300
opt.signcolumn = "yes"
opt.splitright = true
opt.splitbelow = true


-- 剪贴板: SSH 场景优先用 OSC52(把内容发回本地终端,由本地 WezTerm/终端写入剪贴板)
-- 本机有 xclip/xsel/wl-copy 时也一并启用 + 寄存器
if vim.env.SSH_TTY or vim.env.SSH_CONNECTION then
  opt.clipboard = "unnamedplus"
  vim.g.clipboard = {
    name = "OSC 52",
    copy = {
      ["+"] = require("vim.ui.clipboard.osc52").copy("+"),
      ["*"] = require("vim.ui.clipboard.osc52").copy("*"),
    },
    paste = {
      ["+"] = require("vim.ui.clipboard.osc52").paste("+"),
      ["*"] = require("vim.ui.clipboard.osc52").paste("*"),
    },
  }
else
  opt.clipboard = "unnamedplus"
end

-- 说明:
--  * vimrc 的 pastetoggle 在 Neovim 已移除;用 ;sp 映射 :set invpaste 代替。
--  * vimrc 的 tags=./.tags;,.tags 不再使用:跳定义由 gtags tagfunc 接管。
--  * vimrc 的 ;y/;p(系统剪贴板)是注释掉的,这里保持不启用。
