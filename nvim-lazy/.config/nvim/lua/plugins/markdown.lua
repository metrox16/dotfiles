-- Markdown rendering: markview.nvim, same as the old config. It renders as soon
-- as a markdown file is opened and :Mdshow toggles it off and on again.
--
-- LazyVim's markdown extra ships render-markdown.nvim, so that one is disabled
-- to keep a single renderer touching the buffer.
return {
  { "MeanderingProgrammer/render-markdown.nvim", enabled = false },

  {
    "OXY2DEV/markview.nvim",
    ft = { "markdown", "markdown.mdx" },
    cmd = { "Markview", "Mdshow" },
    config = function()
      require("markview").setup()

      vim.api.nvim_create_user_command("Mdshow", function()
        vim.cmd("Markview toggle")
      end, { desc = "Toggle markdown rendering (markview)" })
    end,
  },
}
