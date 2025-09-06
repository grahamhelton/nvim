local lspconfig = require 'lspconfig'
return {
  {
    'neovim/nvim-lspconfig',
    opts = {
      -- Useful for debugging formatter issues
      format_notify = true,
      inlay_hints = { enabled = false },
      servers = {
        bashls = {
          filetypes = { 'sh', 'zsh' },
        },
        denols = {},
        dockerls = {},
        helm_ls = {},
        jsonls = {},
        jsonnet_ls = {},
        lua_ls = {
          Lua = {
            workspace = { checkThirdParty = false },
            telemetry = { enable = false },
          },
        },
        marksman = {},
        -- regols is not maanged by Mason. i install it with `brew install kitagry/tap/regols`.
        -- See: https://github.com/kitagry/regols
        regols = {},
        -- This should be renamed to `ruby_lsp` once this PR gets merged
        -- https://github.com/williamboman/mason-lspconfig.nvim/pull/395
        ruby_lsp = {
          -- cmd = { "bundle", "exec", "ruby-lsp" },
          -- init_options = {
          --   formatter = "auto",
          -- },
        },
        rubocop = {
          -- See: https://docs.rubocop.org/rubocop/usage/lsp.html
          cmd = { 'bundle', 'exec', 'rubocop', '--lsp' },
          root_dir = lspconfig.util.root_pattern('Gemfile', '.git', '.'),
        },
        sqlls = {},
        terraformls = {},
        yamlls = {},
        gopls = {
          settings = {
            gopls = {
              gofumpt = true,
              usePlaceholders = true,
              completeUnimported = true,
            },
          },
        },
      },
    },
    config = function(_, opts)
      -- Set up LSP keybindings when LSP attaches to buffer
      vim.api.nvim_create_autocmd('LspAttach', {
        group = vim.api.nvim_create_augroup('UserLspConfig', {}),
        callback = function(ev)
          local bufopts = { noremap = true, silent = true, buffer = ev.buf }

          -- LSP keybindings using Telescope (wrapped in functions)
          vim.keymap.set('n', 'gd', function()
            require('telescope.builtin').lsp_definitions()
          end, bufopts)
          vim.keymap.set('n', 'gr', function()
            require('telescope.builtin').lsp_references()
          end, bufopts)
          vim.keymap.set('n', 'gi', function()
            require('telescope.builtin').lsp_implementations()
          end, bufopts)
          vim.keymap.set('n', 'K', vim.lsp.buf.hover, bufopts)
          vim.keymap.set('n', '<leader>rn', vim.lsp.buf.rename, bufopts)
          vim.keymap.set('n', '<leader>ca', function()
            require('telescope.builtin').lsp_code_actions()
          end, bufopts)

          -- Additional useful Telescope LSP functions
          vim.keymap.set('n', '<leader>ds', function()
            require('telescope.builtin').lsp_document_symbols()
          end, bufopts)
          vim.keymap.set('n', '<leader>ws', function()
            require('telescope.builtin').lsp_workspace_symbols()
          end, bufopts)
          vim.keymap.set('n', '<leader>td', function()
            require('telescope.builtin').lsp_type_definitions()
          end, bufopts)
          vim.keymap.set('n', '<leader>d', function()
            require('telescope.builtin').diagnostics()
          end, bufopts)
        end,
      })

      -- Set up servers
      for server, config in pairs(opts.servers) do
        require('lspconfig')[server].setup(config)
      end
    end,
  },
}
