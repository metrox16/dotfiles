-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua

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
