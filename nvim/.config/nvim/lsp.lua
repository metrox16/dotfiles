-- LSP setup. nvim-lspconfig ships the server definitions under its lsp/
-- directory; vim.lsp.config() only layers our overrides on top and
-- vim.lsp.enable() starts the server when a matching filetype opens.

-- C/C++ (also objc/cuda, which clangd handles through the same definition).
if vim.fn.executable('clangd') == 1 then
  vim.lsp.config('clangd', {
    cmd = {
      'clangd',
      '--background-index',
      '--clang-tidy',
      '--completion-style=detailed',
      '--header-insertion=iwyu',
      '--function-arg-placeholders',
      -- Used when the project has no .clang-format, so indentation of
      -- inserted snippets stays sane.
      '--fallback-style=LLVM',
    },
    -- Without compile_commands.json clangd guesses the flags, which produces
    -- bogus "file not found" diagnostics on includes. Look further up the tree
    -- than the default so a build/ dir one level above the sources is found.
    root_markers = {
      '.clangd',
      'compile_commands.json',
      'compile_flags.txt',
      'CMakeLists.txt',
      'Makefile',
      'configure.ac',
      '.git',
    },
  })
  vim.lsp.enable('clangd')
end

-- Automatic suggestions --------------------------------------------------
-- menuone   show the popup even for a single match
-- noselect  do not insert anything until a match is picked
-- fuzzy     match subsequences, not only prefixes
-- popup     show the item's documentation in a floating window
vim.opt.completeopt = { 'menu', 'menuone', 'noselect', 'fuzzy', 'popup' }
vim.opt.pumheight = 12
-- Keep the "match 1 of 20" chatter out of the message area.
vim.opt.shortmess:append('c')

vim.api.nvim_create_autocmd('LspAttach', {
  desc = 'Enable LSP completion and buffer-local mappings',
  callback = function(args)
    local client = vim.lsp.get_client_by_id(args.data.client_id)
    if not client then
      return
    end

    if client:supports_method('textDocument/completion') then
      -- autotrigger pops the menu up as you type instead of waiting for
      -- <C-x><C-o>.
      vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
    end

    local map = function(lhs, rhs, desc)
      vim.keymap.set('n', lhs, rhs, { buffer = args.buf, desc = desc })
    end

    -- nvim already provides K (hover), grn (rename), gra (code action),
    -- grr (references), gri (implementation) and gO (document symbols).
    map('gd', vim.lsp.buf.definition, 'LSP: go to definition')
    map('gD', vim.lsp.buf.declaration, 'LSP: go to declaration')
    map('gy', vim.lsp.buf.type_definition, 'LSP: go to type definition')
    map('<leader>e', vim.diagnostic.open_float, 'LSP: line diagnostics')
    map('<leader>q', vim.diagnostic.setloclist, 'LSP: diagnostics to loclist')

    -- clangd extension: jump between foo.c and foo.h.
    if client.name == 'clangd' then
      map('<leader>h', function()
        client:request('textDocument/switchSourceHeader', vim.lsp.util.make_text_document_params(), function(err, result)
          if err or not result then
            vim.notify('No matching source/header found', vim.log.levels.WARN)
            return
          end
          vim.cmd.edit(vim.uri_to_fname(result))
        end, args.buf)
      end, 'clangd: switch source/header')
    end
  end,
})

-- Diagnostics ------------------------------------------------------------
vim.diagnostic.config({
  virtual_text = { spacing = 2, prefix = '●' },
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  signs = {
    text = {
      [vim.diagnostic.severity.ERROR] = 'E',
      [vim.diagnostic.severity.WARN] = 'W',
      [vim.diagnostic.severity.INFO] = 'I',
      [vim.diagnostic.severity.HINT] = 'H',
    },
  },
  float = { border = 'rounded', source = true },
})

-- Reserve the sign column so text does not shift when a diagnostic appears.
vim.opt.signcolumn = 'yes'

vim.api.nvim_create_user_command('LspInfo', function()
  vim.cmd('checkhealth vim.lsp')
end, { desc = 'Show attached LSP clients' })
