-- Neo-tree is a Neovim plugin to browse the file system
-- https://github.com/nvim-neo-tree/neo-tree.nvim

return {
  'nvim-neo-tree/neo-tree.nvim',
  version = '*',
  dependencies = {
    'nvim-lua/plenary.nvim',
    'nvim-tree/nvim-web-devicons', -- not strictly required, but recommended
    'MunifTanjim/nui.nvim',
    's1n7ax/nvim-window-picker', -- Add window-picker
  },
  -- lazy = false,
  keys = {
    { '<leader>e', ':Neotree toggle<CR>', desc = 'NeoTree toggle', silent = true },
  },
  opts = {
    filesystem = {
      window = {
        mappings = {
          ['<leader>e'] = 'close_window',
          ['<CR>'] = 'open_with_window_picker',
        },
        position = 'left',
      },
    },
    event_handlers = {
      {
        event = 'file_opened',
        handler = function()
          require('neo-tree.command').execute { action = 'close' }
        end,
      },
    },
  },
  config = function(_, opts)
    -- Configure window-picker
    require('window-picker').setup {
      autoselect_one = true,
      include_current = true,
      filter_rules = {
        -- filter using buffer options
        bo = {
          -- if the file type is one of following, the window will be ignored
          filetype = { 'neo-tree', 'neo-tree-popup', 'notify' },

          -- if the buffer type is one of following, the window will be ignored
          buftype = { 'terminal', 'quickfix' },
        },
      },
      other_win_hl_color = '#e35e4f',
    }

    require('neo-tree').setup(opts)
  end,
}
