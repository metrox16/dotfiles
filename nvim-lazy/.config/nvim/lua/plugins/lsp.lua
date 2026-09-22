-- Diagnostic look and clangd tweaks from the old lsp.lua.
return {
  {
    "neovim/nvim-lspconfig",
    opts = {
      diagnostics = {
        -- Letters instead of nerd-font glyphs, as in the old config.
        signs = {
          text = {
            [vim.diagnostic.severity.ERROR] = "E",
            [vim.diagnostic.severity.WARN] = "W",
            [vim.diagnostic.severity.INFO] = "I",
            [vim.diagnostic.severity.HINT] = "H",
          },
        },
        virtual_text = {
          spacing = 2,
          prefix = "●",
          source = "if_many",
        },
        float = {
          border = "rounded",
          source = true,
        },
      },
      servers = {
        clangd = {
          -- Without compile_commands.json clangd guesses the flags, which
          -- produces bogus "file not found" diagnostics on includes. Look
          -- further up the tree than LazyVim does so a build/ dir one level
          -- above the sources is found. Lists replace rather than merge here.
          root_markers = {
            ".clangd",
            "compile_commands.json",
            "compile_flags.txt",
            "CMakeLists.txt",
            "Makefile",
            "configure.ac",
            "configure.in",
            "config.h.in",
            "meson.build",
            "meson_options.txt",
            "build.ninja",
            ".git",
          },
          keys = {
            -- <leader>ch is LazyVim's mapping for this; <leader>h is the old one.
            { "<leader>h", "<cmd>LspClangdSwitchSourceHeader<cr>", desc = "Switch Source/Header (C/C++)" },
          },
        },
      },
    },
  },
}
