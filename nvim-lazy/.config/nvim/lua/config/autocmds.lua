-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

-- LazyVim turns 'spell' on for text, markdown, gitcommit, plaintex and typst,
-- which underlines every identifier in a technical document in red. The old
-- config never had it, so its group goes away. The wrap it sets in the same
-- callback is not lost: lua/config/options.lua sets wrap for every buffer.
pcall(vim.api.nvim_del_augroup_by_name, "lazyvim_wrap_spell")

-- Autocmds are loaded on the VeryLazy event, after LazyVim's own, so deleting
-- the group here is enough - ours does not need to re-register anything.

-- Treat bashrc-ish files as bash, so shfmt and the bash parser handle them
-- instead of the plain-sh defaults.
vim.filetype.add({
  pattern = {
    [".*bashrc.*"] = "bash",
  },
})

-- register(lang, filetype) maps a filetype onto a parser of a *different*
-- name. Only sh needs it: yaml, json, c, cpp and java resolve to same-named
-- parsers on their own, and aliasing them to bash would parse them as shell
-- scripts.
vim.treesitter.language.register("bash", { "sh" })
