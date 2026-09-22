-- Tool installation, adapted to the machine this config runs on.
--
-- Mason installs a good part of what the extras in lazyvim.json ask for by
-- calling another toolchain: npm for the node based servers, go for the Go
-- tools, R for the R language server, gem for the Ruby ones. On a machine
-- without that toolchain the install fails on every start, so each entry below
-- names the command its installer needs and is left out while that command is
-- missing. Nothing is pinned: the defaults come back on their own once the
-- toolchain is in $PATH.
--
-- Add a row here when an extra brings in a tool that fails the same way.

-- Mason's bin directory is only put on PATH once mason.setup() has run, which
-- is after this file is read, so it is checked by hand. That way a tool Mason
-- already installed still counts when the toolchain that installed it is gone.
local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/"

local function have(cmd)
  return vim.fn.executable(cmd) == 1 or vim.fn.executable(mason_bin .. cmd) == 1
end

-- Mason package name -> the command Mason installs it with.
local tool_needs = {
  ["markdownlint-cli2"] = "npm",
  ["markdown-toc"] = "npm",
  prettier = "npm",
  goimports = "go",
  gofumpt = "go",
  ["erb-formatter"] = "gem",
  rubocop = "gem",
}

-- erb-lint builds a native gem extension and needs the Ruby headers that
-- distributions ship in a separate -devel package, so it is never asked for.
local tool_skip = {
  ["erb-lint"] = true,
}

-- LSP server -> the executable it runs as, and the command Mason installs it
-- with. A server already on PATH is used as it is, one Mason can install is
-- left to Mason, and the rest stay off.
local server_needs = {
  jsonls = { bin = "vscode-json-language-server", needs = "npm" },
  yamlls = { bin = "yaml-language-server", needs = "npm" },
  dockerls = { bin = "docker-langserver", needs = "npm" },
  docker_compose_language_service = { bin = "docker-compose-langserver", needs = "npm" },
  pyright = { bin = "pyright-langserver", needs = "npm" },
  gopls = { bin = "gopls", needs = "go" },
  r_language_server = { bin = "R", needs = "R" },
}

local servers = {}
for name, spec in pairs(server_needs) do
  if have(spec.bin) then
    servers[name] = { mason = false }
  elseif not have(spec.needs) then
    servers[name] = { enabled = false }
  end
end

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
        if tool_skip[tool] then
          return false
        end
        local needs = tool_needs[tool]
        return needs == nil or have(needs)
      end, opts.ensure_installed or {})
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = servers,
    },
  },
}
