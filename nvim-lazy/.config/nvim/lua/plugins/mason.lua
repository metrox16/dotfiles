-- Tool installation, adapted to this machine.
--
-- Part of the LazyVim extras in lazyvim.json pull tools that Mason can only
-- install through npm, and this box has neither node nor npm (nor sudo to add
-- them). Left alone, Mason retries and fails on every start. Everything below
-- is conditional, so the defaults come back on their own once npm lands in
-- $PATH.

local have_npm = vim.fn.executable("npm") == 1

-- Mason package names that need npm, plus erb-lint, which needs ruby headers
-- that are not installed either.
local skip_tools = {
  ["markdownlint-cli2"] = not have_npm,
  ["markdown-toc"] = not have_npm,
  ["prettier"] = not have_npm,
  ["erb-lint"] = true,
}

return {
  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      -- The old config used whatever was in $PATH: clangd and clang-format from
      -- the vbuild clang toolchain, shfmt/rustfmt/gofmt from ~/.local and
      -- ~/.cargo. Appending Mason's bin directory keeps those first and lets
      -- Mason fill in only what is missing.
      opts.PATH = "append"

      opts.ensure_installed = vim.tbl_filter(function(tool)
        return not skip_tools[tool]
      end, opts.ensure_installed or {})
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- npm-only language servers from the json, yaml and docker extras.
        jsonls = { enabled = have_npm },
        yamlls = { enabled = have_npm },
        dockerls = { enabled = have_npm },
        docker_compose_language_service = { enabled = have_npm },
      },
    },
  },
}
