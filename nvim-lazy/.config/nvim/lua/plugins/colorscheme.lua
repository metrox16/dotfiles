-- Theme: VS Code Dark+ via vscode.nvim, which keeps up with the treesitter
-- capture names and the LSP semantic token groups. vim-code-dark, the one the
-- old config used, still maps the pre-0.9 names, so directives and control flow
-- came out blue instead of purple.
--
-- vscode.nvim colours @keyword.import but not @keyword.directive, so `#define`
-- and `#pragma` still fall through to @keyword and turn blue while `#include` is
-- purple. Its own PreProc and Define groups already hold the purple VS Code
-- uses, so the two captures are pointed at those.
local links = {
  ["@keyword.directive"] = "PreProc",
  ["@keyword.directive.define"] = "Define",
}

local function fix_directives()
  if vim.g.colors_name ~= "vscode" then
    return
  end
  for group, target in pairs(links) do
    vim.api.nvim_set_hl(0, group, { link = target })
  end
end

return {
  {
    "Mofiqul/vscode.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      style = "dark",
      italic_comments = true,
      underline_links = true,
      terminal_colors = true,
    },
    init = function()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("vscode_ts_directives", { clear = true }),
        callback = fix_directives,
      })
    end,
  },

  {
    "LazyVim/LazyVim",
    opts = {
      colorscheme = "vscode",
    },
  },
}
