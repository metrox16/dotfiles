-- Single source of truth for the parser list; install-nvim.sh reads this via
-- vim.g.ts_languages so it never has to duplicate the list.
vim.g.ts_languages = {
    'bash', 'markdown', 'markdown_inline', 'lua', 'vim', 'vimdoc',
    'json', 'yaml', 'python', 'diff', 'git_config',
}

-- Interactive runs install whatever parsers are missing, in the background. In
-- headless runs (install-nvim.sh) the installer calls install() itself and waits
-- for it, so starting a second, unawaited install here would race it.
--
-- The prerequisites are checked first because nvim-treesitter does not compile
-- parsers itself: it shells out to the tree-sitter CLI, which in turn needs a C
-- compiler. Without them every start would download all the parser sources and
-- then fail on each one, so on a machine that cannot build them nothing is
-- attempted and the rest of the config still works.
local function install_missing_parsers()
  if vim.fn.executable('tree-sitter') ~= 1 then return end
  if vim.fn.executable('cc') ~= 1 and vim.fn.executable('gcc') ~= 1 then return end

  local ok, ts = pcall(require, 'nvim-treesitter')
  if not ok then return end

  local installed = {}
  for _, lang in ipairs(ts.get_installed()) do
    installed[lang] = true
  end

  local missing = {}
  for _, lang in ipairs(vim.g.ts_languages) do
    if not installed[lang] then
      missing[#missing + 1] = lang
    end
  end

  if #missing > 0 then
    ts.install(missing)
  end
end

if #vim.api.nvim_list_uis() > 0 then
  install_missing_parsers()
end

vim.treesitter.language.register('bash', 'sh', 'yaml', 'json', 'c', 'java')

local ok2, mv = pcall(require, 'markview')
if ok2 then
  mv.setup({ initial_state = false })
  vim.api.nvim_create_user_command('Mdshow', function() vim.cmd('Markview toggle') end, {})
end

local ok3, todo = pcall(require, 'todo-comments')
if ok3 then
  todo.setup()
end

-- Better Comments style: #! (alert/red), #* (highlight/green), #? (question/blue)
vim.api.nvim_create_autocmd('Syntax', {
  pattern = '*',
  callback = function()
    vim.fn.matchadd('BetterCommentAlert', [[\v#\s*!.*]])
    vim.fn.matchadd('BetterCommentStar', [[\v#\s*\*.*]])
    vim.fn.matchadd('BetterCommentQuestion', [[\v#\s*\?.*]])
  end,
})
vim.api.nvim_set_hl(0, 'BetterCommentAlert', { fg = '#FF2D00', italic = true })
vim.api.nvim_set_hl(0, 'BetterCommentStar', { fg = '#98C379', italic = true })
vim.api.nvim_set_hl(0, 'BetterCommentQuestion', { fg = '#3498DB', italic = true })
