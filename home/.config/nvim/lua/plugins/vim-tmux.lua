return {
  "christoomey/vim-tmux-navigator",
  -- Declaring the keys here makes LazyVim skip its own <C-h/j/k/l> window maps,
  -- which otherwise replace the navigator maps on VeryLazy.
  keys = {
    { "<c-h>", "<cmd>TmuxNavigateLeft<cr>" },
    { "<c-j>", "<cmd>TmuxNavigateDown<cr>" },
    { "<c-k>", "<cmd>TmuxNavigateUp<cr>" },
    { "<c-l>", "<cmd>TmuxNavigateRight<cr>" },
    { "<c-\\>", "<cmd>TmuxNavigatePrevious<cr>" },
  },
}
