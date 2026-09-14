-- :Format -- run the current buffer (or a range) through an external formatter.
-- Filters via stdin/stdout so the change lands as a single undo step and the
-- cursor/view is restored. Nothing is modified unless the formatter exits 0.

-- Indent width taken from the buffer's own options so formatting matches the
-- editor settings. Returns "0" when the buffer uses real tabs.
local function indent_width()
  if not vim.bo.expandtab then
    return '0'
  end
  local sw = vim.bo.shiftwidth
  if sw == 0 then
    sw = vim.bo.tabstop
  end
  return tostring(sw)
end

local function shfmt()
  return { 'shfmt', '-i', indent_width(), '-ci', '-bn' }
end

local function clang_format()
  -- --assume-filename lets clang-format pick the right language and still find
  -- the project's .clang-format while reading from stdin.
  local name = vim.fn.expand('%:t')
  if name == '' then
    name = 'stdin.cpp'
  end
  return { 'clang-format', '--assume-filename=' .. name }
end

local function jq()
  local width = indent_width()
  if width == '0' then
    return { 'jq', '--tab', '.' }
  end
  return { 'jq', '--indent', width, '.' }
end

local formatters = {
  sh = shfmt,
  bash = shfmt,
  c = clang_format,
  cpp = clang_format,
  objc = clang_format,
  java = clang_format,
  cuda = clang_format,
  json = jq,
  go = function() return { 'gofmt' } end,
  rust = function() return { 'rustfmt', '--emit', 'stdout', '--quiet' } end,
  xml = function() return { 'xmllint', '--format', '-' } end,
}

local function format_range(line1, line2)
  local ft = vim.bo.filetype
  local build = formatters[ft]
  if not build then
    vim.notify(
      ('No formatter configured for filetype %q'):format(ft),
      vim.log.levels.WARN
    )
    return
  end

  local cmd = build()
  if vim.fn.executable(cmd[1]) ~= 1 then
    vim.notify(cmd[1] .. ' not found in $PATH', vim.log.levels.ERROR)
    return
  end

  local input = vim.api.nvim_buf_get_lines(0, line1 - 1, line2, false)
  -- systemlist merges stderr into the output, so on failure this holds the
  -- formatter's diagnostics.
  local output = vim.fn.systemlist(cmd, input)

  if vim.v.shell_error ~= 0 then
    vim.notify(
      ('%s failed (exit %d):\n%s'):format(cmd[1], vim.v.shell_error, table.concat(output, '\n')),
      vim.log.levels.ERROR
    )
    return
  end

  if #output == 0 then
    vim.notify(cmd[1] .. ' produced no output; buffer left unchanged', vim.log.levels.WARN)
    return
  end

  if vim.deep_equal(input, output) then
    vim.notify('Already formatted (' .. cmd[1] .. ')', vim.log.levels.INFO)
    return
  end

  local view = vim.fn.winsaveview()
  vim.api.nvim_buf_set_lines(0, line1 - 1, line2, false, output)
  vim.fn.winrestview(view)
  vim.notify(('Formatted %d lines with %s'):format(#output, cmd[1]), vim.log.levels.INFO)
end

vim.api.nvim_create_user_command('Format', function(opts)
  format_range(opts.line1, opts.line2)
end, {
  range = '%', -- no range given -> whole buffer
  desc = 'Format buffer or range with the filetype formatter',
})
