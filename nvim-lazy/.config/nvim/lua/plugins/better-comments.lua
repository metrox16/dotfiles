-- Better Comments style markers: #! (alert), #* (highlight), #? (question).
--
-- The old config used matchadd() on the Syntax event. mini.hipatterns does the
-- same job per buffer instead of per window, so splits and reloads keep the
-- highlights, and it is already part of the LazyVim setup.

local groups = {
  BetterCommentAlert = { fg = "#FF2D00", italic = true },
  BetterCommentStar = { fg = "#98C379", italic = true },
  BetterCommentQuestion = { fg = "#3498DB", italic = true },
}

local function set_highlights()
  for name, val in pairs(groups) do
    vim.api.nvim_set_hl(0, name, val)
  end
end

return {
  {
    "nvim-mini/mini.hipatterns",
    event = "LazyFile",
    opts = function(_, opts)
      set_highlights()
      vim.api.nvim_create_autocmd("ColorScheme", {
        group = vim.api.nvim_create_augroup("better_comments_hl", { clear = true }),
        callback = set_highlights,
      })

      opts.highlighters = vim.tbl_deep_extend("force", opts.highlighters or {}, {
        comment_alert = { pattern = "#%s*!.*", group = "BetterCommentAlert" },
        comment_star = { pattern = "#%s*%*.*", group = "BetterCommentStar" },
        comment_question = { pattern = "#%s*%?.*", group = "BetterCommentQuestion" },
      })

      return opts
    end,
  },
}
