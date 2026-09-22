-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua

-- :Format is the real command (Vim requires a capital); allow typing :format too
vim.cmd([[cnoreabbrev <expr> format (getcmdtype() ==# ':' && getcmdline() ==# 'format') ? 'Format' : 'format']])

-- The LSP mappings from the old lsp.lua are already LazyVim defaults, or moved
-- because LazyVim owns the old prefix:
--   gd / gD / gy           unchanged (definition, declaration, type definition)
--   <leader>e  -> <leader>cd   line diagnostics (<leader>e is the file explorer)
--   <leader>q  -> <leader>xl   diagnostics in a list (<leader>q is the session group)
--   <leader>h  clangd switch source/header, kept in lua/plugins/lsp.lua
