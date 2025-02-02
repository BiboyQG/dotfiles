-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

local keymap = vim.keymap

keymap.set("i", "kj", "<Esc>")
keymap.set("n", "<leader>sv", "<C-w>v")
keymap.set("n", "<leader>sx", ":close<cr>")

keymap.set("n", "te", ":tabedit")
keymap.set("n", "<tab>", ":tabnext<Return>", opts)
keymap.set("n", "<s-tab>", ":tabprev<Return>", opts)

-- Delete a word backwards
keymap.set("n", "dw", 'vb"_d')

-- Select all
keymap.set("n", "<C-a>", "gg<S-v>G")

keymap.set("n", "<C-j>", ":TmuxNavigateDown<CR>", { silent = true })
keymap.set("n", "<C-k>", ":TmuxNavigateUp<CR>", { silent = true })
keymap.set("n", "<C-h>", ":TmuxNavigateLeft<CR>", { silent = true })
keymap.set("n", "<C-l>", ":TmuxNavigateRight<CR>", { silent = true })
