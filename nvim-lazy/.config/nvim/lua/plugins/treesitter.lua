-- Parsers from the old plugins.lua. LazyVim already asks for most of these;
-- ensure_installed is extended, not replaced, so listing them again is cheap
-- and keeps the old list readable in one place.
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = {
      ensure_installed = {
        "bash",
        "c",
        "cmake",
        "cpp",
        "diff",
        "git_config",
        "json",
        "lua",
        "make",
        "markdown",
        "markdown_inline",
        "python",
        "vim",
        "vimdoc",
        "yaml",
      },
    },
  },
}
