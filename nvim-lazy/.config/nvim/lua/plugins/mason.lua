-- Tool installation, adapted to the machine this config runs on.
--
-- Mason installs a good part of what the extras in lazyvim.json ask for by
-- calling another toolchain: npm for the node based servers, go for the Go
-- tools, R for the R language server, gem for the Ruby ones. On a machine
-- without that toolchain the install fails on every start, so each entry below
-- names what its installer needs and is left out while that is missing. Nothing
-- is pinned: the defaults come back on their own once the toolchain is there.
--
-- Add a row here when an extra brings in a tool that fails the same way.

-- Mason's bin directory is only put on PATH once mason.setup() has run, which
-- is after this file is read, so it is checked by hand. That way a tool Mason
-- already installed still counts when the toolchain that installed it is gone.
local mason_bin = vim.fn.stdpath("data") .. "/mason/bin/"

local function have(cmd)
  return vim.fn.executable(cmd) == 1 or vim.fn.executable(mason_bin .. cmd) == 1
end

local uv = vim.uv or vim.loop

local check = {
  npm = function()
    return have("npm")
  end,
  go = function()
    return have("go")
  end,
  R = function()
    return have("R")
  end,
  gem = function()
    return have("gem")
  end,
  -- A gem carrying a C extension is compiled at install time: rubocop pulls in
  -- prism, ruby-lsp pulls in rbs, and both need the Ruby headers that
  -- distributions ship in a separate -devel package. `gem` on its own says
  -- nothing about those, so RbConfig is asked where they should be.
  gem_native = function()
    if not have("ruby") then
      return false
    end
    local dir = vim.fn.system({ "ruby", "-rrbconfig", "-e", "print RbConfig::CONFIG['rubyhdrdir'].to_s" })
    if vim.v.shell_error ~= 0 or dir == "" then
      return false
    end
    return uv.fs_stat(dir .. "/ruby.h") ~= nil
  end,
}

-- Each check runs at most once, and only when Mason or lspconfig loads, so the
-- Ruby process this costs is not on the startup path.
local answers = {}

local function available(what)
  if answers[what] == nil then
    answers[what] = check[what] ~= nil and check[what]() or false
  end
  return answers[what]
end

-- Mason package name -> what Mason installs it with.
local tool_needs = {
  ["markdownlint-cli2"] = "npm",
  ["markdown-toc"] = "npm",
  prettier = "npm",
  goimports = "go",
  gofumpt = "go",
  ["erb-formatter"] = "gem",
  ["erb-lint"] = "gem_native",
  rubocop = "gem_native",
}

-- LSP server -> the executable it runs as, and what Mason installs it with. A
-- server already on PATH is used as it is, one Mason can install is left to
-- Mason, and the rest stay off.
local server_needs = {
  jsonls = { bin = "vscode-json-language-server", needs = "npm" },
  yamlls = { bin = "yaml-language-server", needs = "npm" },
  dockerls = { bin = "docker-langserver", needs = "npm" },
  docker_compose_language_service = { bin = "docker-compose-langserver", needs = "npm" },
  pyright = { bin = "pyright-langserver", needs = "npm" },
  gopls = { bin = "gopls", needs = "go" },
  r_language_server = { bin = "R", needs = "R" },
  ruby_lsp = { bin = "ruby-lsp", needs = "gem_native" },
  -- LazyVim's Ruby extra runs rubocop as a language server as well as a
  -- formatter, so Mason installs it through the server list, not the tool list.
  rubocop = { bin = "rubocop", needs = "gem_native" },
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
        local needs = tool_needs[tool]
        return needs == nil or available(needs)
      end, opts.ensure_installed or {})
    end,
  },

  {
    "neovim/nvim-lspconfig",
    opts = function(_, opts)
      opts.servers = opts.servers or {}
      for name, spec in pairs(server_needs) do
        -- A server can be configured as `true` rather than a table, so the
        -- existing value is only merged when there is a table to merge.
        local current = opts.servers[name]
        if type(current) ~= "table" then
          current = {}
        end
        if have(spec.bin) then
          opts.servers[name] = vim.tbl_deep_extend("force", current, { mason = false })
        elseif not available(spec.needs) then
          opts.servers[name] = vim.tbl_deep_extend("force", current, { enabled = false })
        end
      end
    end,
  },
}
