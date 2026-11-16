-- 关闭会改变 vimrc 习惯的 LazyVim 默认插件
return {
  -- flash 会占用 s/S/f/F/r 等键,且与 ; 前缀冲突;easymotion 由 legacy.lua 提供
  { "folke/flash.nvim", enabled = false },
  -- 自动括号补全不是 vimrc 的行为,内核代码里尤其容易干扰
  { "nvim-mini/mini.pairs", enabled = false },
  -- mini.ai 改变 a/i 文本对象语义;vimrc 没有这个习惯
  { "nvim-mini/mini.ai", enabled = false },
  -- noice 改变命令行/消息 UI,影响 ;. 等 vimrc 习惯
  { "folke/noice.nvim", enabled = false },
}
