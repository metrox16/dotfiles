-- Single source of truth for the parser list; install-nvim.sh reads this via
-- vim.g.ts_languages so it never has to duplicate the list.
vim.g.ts_languages = {
    'bash', 'markdown', 'markdown_inline', 'lua', 'vim', 'vimdoc',
    'json', 'yaml', 'python', 'diff', 'git_config',
}

-- Interactive runs install missing parsers in the background. In headless runs
-- (install-nvim.sh) the installer calls install() itself and waits for it, so
-- starting a second, unawaited install here would race it.
if #vim.api.nvim_list_uis() > 0 then
  require('nvim-treesitter').install(vim.g.ts_languages)
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
