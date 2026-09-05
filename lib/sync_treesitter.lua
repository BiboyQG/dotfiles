-- Run in a fresh Neovim process so validation cannot reuse an old loaded parser.
local root = vim.fn.stdpath("data") .. "/lazy/nvim-treesitter"
vim.opt.runtimepath:prepend(root)
vim.opt.runtimepath:prepend(root .. "/runtime")
vim.opt.runtimepath:prepend(vim.fn.stdpath("data") .. "/site")
dofile(root .. "/plugin/filetypes.lua")

local treesitter = require("nvim-treesitter")
local required = { "diff", "vim", "lua", "json" }
assert(treesitter.install(required, { summary = true }):wait(300000), "Tree-sitter parser installation failed")
assert(treesitter.update(nil, { summary = true }):wait(300000), "Tree-sitter parser update failed")

for _, language in ipairs(required) do
  vim.treesitter.language.add(language)
  assert(vim.treesitter.query.get(language, "highlights"), "Missing highlights query: " .. language)
end
print("Tree-sitter parsers and highlight queries verified.")
