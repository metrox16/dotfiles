-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
--
-- Only the options from the old init.vim that LazyVim does not already set are
-- repeated here. LazyVim covers termguicolors, mouse=a, number, ignorecase,
-- smartcase, expandtab, shiftwidth=2, tabstop=2, signcolumn=yes and
-- formatoptions (jcroqlnt, which already contains "o").

local opt = vim.opt

opt.background = "dark"
opt.title = true
opt.ruler = true -- LazyVim turns this off
opt.showmatch = true
opt.hlsearch = true
opt.autoindent = true

-- Plain line numbers. LazyVim ships relativenumber on, the old config never had
-- it. <leader>uL toggles it per session.
opt.relativenumber = false

-- Never hard-wrap while typing; soft wrap long lines instead. LazyVim ships
-- wrap=false, the old config kept Neovim's default. <leader>uw toggles it.
opt.textwidth = 0
opt.wrap = true

-- Completion popup height, kept from the old native-completion setup.
opt.pumheight = 12

-- LazyVim's Python extra defaults to pyright, which Mason installs through npm.
-- basedpyright comes from pip, which does work here.
if vim.fn.executable("npm") == 0 then
  vim.g.lazyvim_python_lsp = "basedpyright"
end
