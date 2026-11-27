-- keymaps.lua —— 逐条移植 ~/.vimrc 的按键习惯
-- 原则:与 LazyVim 默认冲突处,一律以 vimrc 为准;本文件在 LazyVim 默认键位之后加载。
local map = vim.keymap.set

-- ── 行首/行尾(vimrc: le→$  lb→0)
map({ "n", "x", "o" }, "le", "$", { desc = "行尾" })
map({ "n", "x", "o" }, "lb", "0", { desc = "行首" })

-- ── 保存/退出(vimrc)
map("n", "<leader>w", "<cmd>w<cr>", { desc = "保存" })
map("n", "<leader>wq", function()
  pcall(vim.cmd, "wa")
  pcall(vim.cmd, "q")
end, { desc = "保存全部并退出" })
map("n", "<leader>W", "<cmd>w !sudo tee % > /dev/null<cr>", { desc = "sudo 保存" })
map("n", "<leader>Q", "<cmd>bd<cr>", { desc = "关闭 buffer" })

-- ── 窗口(vimrc: wn 循环; wl=右 wr=左,注意 vimrc 里是反的,保持原样)
map("n", "wn", "<C-w><C-w>", { desc = "窗口循环" })
map("n", "<leader>wl", "<C-w>l", { desc = "右侧窗口" })
map("n", "<leader>wr", "<C-w>h", { desc = "左侧窗口" })
map("n", "<leader>wj", "<C-w>j", { desc = "下方窗口" })
map("n", "<leader>wk", "<C-w>k", { desc = "上方窗口" })

-- ── 窗口跳转: normal 与 terminal 模式都可用(终端里也能跳到代码窗口)
for _, d in ipairs({ "h", "j", "k", "l" }) do
  for _, mode in ipairs({ "n", "t" }) do
    map(mode, "<C-w>" .. d, "<C-w>" .. d, { remap = true, desc = "窗口 " .. d })
  end
end
map({ "n", "t" }, "<C-w>w", "<C-w>w", { remap = true, desc = "窗口循环" })

-- ── 搜索/命令(vimrc)
map("n", "<leader>/", "<cmd>nohlsearch<cr>", { desc = "清除搜索高亮" })
map("n", "<leader>.", ":<up><cr>", { remap = true, desc = "重复上一条命令" })
map("n", "<leader>m", "%", { desc = "配对符跳转" })

-- ── paste 切换(vimrc pastetoggle 在 Neovim 已移除)
map("n", "<leader>sp", "<cmd>set invpaste paste?<cr>", { desc = "paste 切换" })

-- ── 缓冲区(vimrc: airline tabline ;1..;12 / [b ]b / ;Q)
for i = 1, 12 do
  map("n", "<leader>" .. i, function()
    local ok = pcall(vim.cmd, "BufferLineGoToBuffer " .. i)
    if not ok then
      pcall(vim.cmd, "buffer " .. i)
    end
  end, { desc = "buffer " .. i })
end
map("n", "[b", "<cmd>bp<cr>", { desc = "上一个 buffer" })
map("n", "]b", "<cmd>bn<cr>", { desc = "下一个 buffer" })

-- ── 文件树/文件查找/头源切换(vimrc: ;n / ;f / ;a)
-- ── 文件树(vimrc: <leader>n → NERDTree,支持 .. 上级/o 展开/t 新标签/i s 分屏/m 书签)
map("n", "<leader>n", "<cmd>NERDTreeToggle<cr>", { desc = "文件树(NERDTree)" })
map("n", "<leader>f", function()
  local ok, pick = pcall(function()
    return LazyVim.pick("files")
  end)
  if ok and pick then
    pick()
  else
    pcall(vim.cmd, "Explore")
  end
end, { desc = "查找文件" })
map("n", "<leader>a", "<cmd>A<cr>", { desc = "头/源切换" })

-- ── 注释(vimrc: nerdcommenter ;cc ;cu ;cn ;cA)
map({ "n", "x" }, "<leader>cc", "<Plug>NERDCommenterComment", { remap = true, desc = "注释" })
map({ "n", "x" }, "<leader>cu", "<Plug>NERDCommenterUncomment", { remap = true, desc = "取消注释" })
map({ "n", "x" }, "<leader>cn", "<Plug>NERDCommenterNested", { remap = true, desc = "嵌套注释" })
map({ "n", "x" }, "<leader>cA", "<Plug>NERDCommenterAppend", { remap = true, desc = "行尾注释" })

-- ── 对齐(vimrc: visual <Enter> EasyAlign)
map("x", "<CR>", "<Plug>(EasyAlign)", { remap = true, desc = "对齐" })

-- ── 结构/任务/历史(vimrc: F9/;tb tagbar, ;td TaskList, ;bm blame, F8 indent)
map("n", "<F9>", "<cmd>AerialToggle<cr>", { desc = "结构大纲" })
map("n", "<leader>tb", "<cmd>AerialToggle<cr>", { desc = "结构大纲" })
map("n", "<leader>td", "<cmd>TodoTrouble<cr>", { desc = "TODO/FIXME" })
map("n", "<leader>bm", function()
  local ok, gs = pcall(require, "gitsigns")
  if ok then
    gs.blame_line({ full = true })
  else
    pcall(vim.cmd, "Gitsigns blame_line")
  end
end, { desc = "git blame 当前行" })
map("n", "<F8>", "<cmd>IndentLinesToggle<cr>", { desc = "缩进线" })

-- ── ALE(vimrc: <C-k>/<C-j> 上一个/下一个错误)
map("n", "<C-k>", "<Plug>(ale_previous_wrap)", { remap = true, desc = "上一个错误" })
map("n", "<C-j>", "<Plug>(ale_next_wrap)", { remap = true, desc = "下一个错误" })

-- ── easymotion: 与原始 Vim/easymotion 一致
-- 小写 = 向前(行数增大方向,同 w/f),大写 = 向后(同 b/F)
local function em(plug)
  return function()
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes("<Plug>(" .. plug .. ")", true, false, true),
      "m",
      false
    )
  end
end

map({ "n", "x", "o" }, "<leader><leader>w", em("easymotion-w"), { desc = "easymotion 词首(向前/下)" })
map({ "n", "x", "o" }, "<leader><leader>W", em("easymotion-b"), { desc = "easymotion 词首(向后/上)" })
map({ "n", "x", "o" }, "<leader><leader>f", em("easymotion-f"), { desc = "easymotion 字符(向前/下)" })
map({ "n", "x", "o" }, "<leader><leader>F", em("easymotion-F"), { desc = "easymotion 字符(向后/上)" })

-- ── 索引查询(vimrc: gutentags_plus 的 ;g* / ;j*)
local function idx()
  return require("aivim.index")
end
map("n", "<leader>gg", function() idx().query("-d") end, { silent = true, desc = "gtags 定义" })
map("n", "<leader>gr", function() idx().query("-r") end, { silent = true, desc = "gtags 引用" })
map("n", "<leader>gs", function() idx().symbol(vim.fn.expand("<cword>")) end, { silent = true, desc = "符号(定义+引用)" })
map("n", "<leader>gt", function() idx().text(vim.fn.expand("<cword>")) end, { silent = true, desc = "文本查询" })
map("n", "<leader>gf", function() idx().file(vim.fn.expand("<cfile>")) end, { silent = true, desc = "gtags 文件" })
map("n", "<leader>gi", function() idx().includes(vim.fn.expand("<cword>")) end, { silent = true, desc = "include 查询" })
map("n", "<leader>gc", function() idx().callers(vim.fn.expand("<cword>")) end, { silent = true, desc = "callers" })
map("n", "<leader>gd", function() idx().callees() end, { silent = true, desc = "callees" })
map("n", "<leader>ga", function() idx().assignments(vim.fn.expand("<cword>")) end, { silent = true, desc = "赋值位置" })
map("n", "<leader>gz", function() idx().symbol(vim.fn.expand("<cword>")) end, { silent = true, desc = "extra/symbol" })
map("n", "<leader>ge", function()
  local p = vim.fn.input("egrep: ")
  if p ~= "" then
    idx().egrep(p)
  end
end, { silent = true, desc = "egrep" })
map("n", "<leader>gh", "<cmd>cclose<cr>", { desc = "关闭 quickfix" })
map("n", "<leader>jd", function() vim.cmd("tag " .. vim.fn.expand("<cword>")) end, { silent = true, desc = "跳定义" })
map("n", "<leader>jc", function() vim.cmd("tselect " .. vim.fn.expand("<cword>")) end, { silent = true, desc = "定义列表" })

-- ── 语义查询:vimrc 是 nmap <C-\> g<C-]>(定义列表)
-- 智能版:1 个定义直接跳,多个才列表;<C-]> 仍直接跳;<C-t>/<C-o>/<C-i> 原生。
map("n", "<C-\\>", function()
  require("aivim.index").definition()
end, { desc = "定义:1个直接跳,多个列表" })

-- AI 键位在 lua/plugins/ai.lua
