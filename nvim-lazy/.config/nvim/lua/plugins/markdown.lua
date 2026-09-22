-- Markdown rendering: markview.nvim from the old config, off until :Mdshow.
-- LazyVim's markdown extra ships render-markdown.nvim, so that one is disabled
-- to keep a single renderer touching the buffer.
return {
  { "MeanderingProgrammer/render-markdown.nvim", enabled = false },

  {
    "OXY2DEV/markview.nvim",
    ft = { "markdown", "markdown.mdx" },
    cmd = { "Markview", "Mdshow" },
    opts = {
      -- Do not render on attach; :Mdshow turns it on per buffer.
      preview = {
        enable = false,
      },
    },
    config = function(_, opts)
      require("markview").setup(opts)

      vim.api.nvim_create_user_command("Mdshow", function()
        vim.cmd("Markview toggle")
      end, { desc = "Toggle markdown rendering (markview)" })
    end,
  },
}
