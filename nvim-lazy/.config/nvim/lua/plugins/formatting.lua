-- Formatters from the old format.lua, running through conform.nvim so that
-- LazyVim's <leader>cf and format-on-save use the same tools.
--
-- :Format (and the :format abbreviation from lua/config/keymaps.lua) formats the
-- buffer, or the given range in visual mode.
return {
  {
    "stevearc/conform.nvim",
    opts = {
      formatters_by_ft = {
        sh = { "shfmt" },
        bash = { "shfmt" },
        c = { "clang-format" },
        cpp = { "clang-format" },
        objc = { "clang-format" },
        objcpp = { "clang-format" },
        cuda = { "clang-format" },
        java = { "clang-format" },
        json = { "jq" },
        -- LazyVim's Go extra prefers goimports + gofumpt; the old config used
        -- plain gofmt.
        go = { "gofmt" },
        rust = { "rustfmt" },
        xml = { "xmllint" },
      },
      formatters = {
        -- conform already passes -i <shiftwidth> for buffers with expandtab.
        shfmt = {
          prepend_args = { "-ci", "-bn" },
        },
      },
    },
    init = function()
      vim.api.nvim_create_user_command("Format", function(args)
        local range = nil
        if args.count ~= -1 then
          local end_line = vim.api.nvim_buf_get_lines(0, args.line2 - 1, args.line2, true)[1]
          range = {
            start = { args.line1, 0 },
            ["end"] = { args.line2, end_line:len() },
          }
        end
        require("conform").format({ async = true, lsp_format = "fallback", range = range })
      end, {
        range = true,
        desc = "Format buffer or range with the filetype formatter",
      })
    end,
  },
}
