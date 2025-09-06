return {
  {
    'ThePrimeagen/harpoon',
    branch = 'harpoon2',
    dependencies = { 'nvim-lua/plenary.nvim' },
    config = function()
      local harpoon = require 'harpoon'
      harpoon:setup()

      -- Basic telescope configuration
      local conf = require('telescope.config').values
      local function toggle_telescope(harpoon_files)
        local file_paths = {}
        for _, item in ipairs(harpoon_files.items) do
          table.insert(file_paths, item.value)
        end

        require('telescope.pickers')
          .new({}, {
            prompt_title = 'Harpoon',
            finder = require('telescope.finders').new_table {
              results = file_paths,
            },
            previewer = conf.file_previewer {},
            sorter = conf.generic_sorter {},
          })
          :find()
      end

      -- Keymaps
      vim.keymap.set('n', '<leader>ha', function()
        harpoon:list():add()
      end, { desc = '[H]arpoon [A]dd file' })
      vim.keymap.set('n', '<leader>hl', function()
        harpoon.ui:toggle_quick_menu(harpoon:list())
      end, { desc = '[H]arpoon [L]ist' })

      -- Quick navigation
      vim.keymap.set('n', '<leader>h1', function()
        harpoon:list():select(1)
      end, { desc = 'Harpoon file 1' })
      vim.keymap.set('n', '<leader>h2', function()
        harpoon:list():select(2)
      end, { desc = 'Harpoon file 2' })
      vim.keymap.set('n', '<leader>h3', function()
        harpoon:list():select(3)
      end, { desc = 'Harpoon file 3' })
      vim.keymap.set('n', '<leader>h4', function()
        harpoon:list():select(4)
      end, { desc = 'Harpoon file 4' })

      -- Telescope integration
      vim.keymap.set('n', '<leader>hf', function()
        toggle_telescope(harpoon:list())
      end, { desc = '[H]arpoon [F]ind files' })
    end,
  },
}
