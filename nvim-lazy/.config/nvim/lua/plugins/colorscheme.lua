-- Theme from the old config: VS Code Dark+ via vim-code-dark.
return {
  {
    "tomasiser/vim-code-dark",
    lazy = false,
    priority = 1000,
  },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "codedark",
    },
  },
}
