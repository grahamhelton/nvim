return {
  {
    'MattesGroeger/vim-bookmarks',
    dependencies = { 'nvim-telescope/telescope.nvim' },
    config = function()
      -- Plugin configuration options

      -- Customize bookmark signs
      vim.g.bookmark_sign = '⚑' -- Bookmark icon
      vim.g.bookmark_annotation_sign = '☰' -- Annotation icon

      -- Behavior settings
      vim.g.bookmark_save_per_working_dir = 1 -- Save bookmarks per working directory
      vim.g.bookmark_auto_save = 1 -- Auto-save bookmarks
      vim.g.bookmark_manage_per_buffer = 0 -- Don't manage per buffer (use working dir instead)
      vim.g.bookmark_auto_close = 1 -- Auto-close bookmark window when jumping
      vim.g.bookmark_highlight_lines = 1 -- Highlight bookmark lines
      vim.g.bookmark_center = 1 -- Center line when jumping to bookmark
      vim.g.bookmark_location_list = 0 -- Use quickfix instead of location list
      vim.g.bookmark_disable_ctrlp = 1 -- Disable ctrlp integration (we use telescope)
      vim.g.bookmark_display_annotation = 1 -- Display annotations on status line

      -- Warning settings
      vim.g.bookmark_show_warning = 1 -- Show warning when clearing all bookmarks
      vim.g.bookmark_show_toggle_warning = 1 -- Show warning when toggling annotated bookmark

      -- Disable default key mappings (we'll set our own)
      vim.g.bookmark_no_default_key_mappings = 1

      -- Custom bookmark file location function for git projects
      vim.cmd [[
        function! g:BMWorkDirFileLocation()
          let filename = 'vim-bookmarks'
          let location = ''
          if isdirectory('.git')
            " Current work dir is git's work tree
            let location = getcwd().'/.git'
          else
            " Look upwards (at parents) for a directory named '.git'
            let location = finddir('.git', '.;')
          endif
          if len(location) > 0
            return location.'/'.filename
          else
            return getcwd().'/.'.filename
          endif
        endfunction
      ]]

      -- Telescope bookmark picker
      local function telescope_bookmarks()
        local has_telescope, telescope = pcall(require, 'telescope')
        if not has_telescope then
          vim.notify('Telescope not found, falling back to quickfix', vim.log.levels.WARN)
          vim.cmd 'BookmarkShowAll'
          return
        end

        local pickers = require 'telescope.pickers'
        local finders = require 'telescope.finders'
        local conf = require('telescope.config').values
        local actions = require 'telescope.actions'
        local action_state = require 'telescope.actions.state'

        -- Get bookmarks using vim-bookmarks internal functions
        local bookmarks = {}

        -- Call vim-bookmarks internal function to get all bookmarks
        vim.cmd [[
          redir => bookmark_list
          silent! BookmarkShowAll
          redir END
        ]]

        -- Alternative approach: read from quickfix list after BookmarkShowAll
        vim.cmd 'silent! BookmarkShowAll'
        local qf_list = vim.fn.getqflist()
        vim.cmd 'cclose' -- Close the quickfix window immediately

        for _, item in ipairs(qf_list) do
          local filename = vim.fn.bufname(item.bufnr)
          if filename == '' then
            filename = '[No Name]'
          else
            filename = vim.fn.fnamemodify(filename, ':.')
          end

          local line_text = item.text or ''
          local annotation = ''

          -- Extract annotation if present (format: "| annotation")
          local pipe_pos = line_text:find ' | '
          if pipe_pos then
            annotation = line_text:sub(pipe_pos + 3)
            line_text = line_text:sub(1, pipe_pos - 1)
          end

          table.insert(bookmarks, {
            filename = filename,
            lnum = item.lnum,
            col = item.col or 1,
            text = line_text,
            annotation = annotation,
            bufnr = item.bufnr,
            display = string.format('%s:%d: %s%s', filename, item.lnum, line_text, annotation ~= '' and ' | ' .. annotation or ''),
          })
        end

        pickers
          .new({}, {
            prompt_title = 'Bookmarks',
            finder = finders.new_table {
              results = bookmarks,
              entry_maker = function(entry)
                return {
                  value = entry,
                  display = entry.display,
                  ordinal = entry.filename .. ' ' .. entry.text .. ' ' .. entry.annotation,
                  filename = entry.filename,
                  lnum = entry.lnum,
                  col = entry.col,
                }
              end,
            },
            sorter = conf.generic_sorter {},
            previewer = conf.file_previewer {},
            attach_mappings = function(prompt_bufnr, map)
              actions.select_default:replace(function()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection then
                  -- Jump to the bookmark
                  vim.cmd('edit ' .. selection.filename)
                  vim.api.nvim_win_set_cursor(0, { selection.lnum, selection.col - 1 })
                  if vim.g.bookmark_center == 1 then
                    vim.cmd 'normal! zz'
                  end
                end
              end)

              -- Add custom mapping to delete bookmark
              map('i', '<C-d>', function()
                local selection = action_state.get_selected_entry()
                if selection then
                  -- Open the file and go to the line to delete the bookmark
                  vim.cmd('edit ' .. selection.filename)
                  vim.api.nvim_win_set_cursor(0, { selection.lnum, selection.col - 1 })
                  vim.cmd 'BookmarkToggle' -- This will remove the bookmark
                  actions.close(prompt_bufnr)
                  -- Refresh the picker
                  telescope_bookmarks()
                end
              end)

              return true
            end,
          })
          :find()
      end

      -- Core bookmark operations
      vim.keymap.set('n', '<leader>bm', '<Plug>BookmarkToggle', { desc = 'Toggle bookmark' })
      vim.keymap.set('n', '<leader>bi', ':BookmarkAnnotate ', { desc = 'Annotate bookmark' })
      vim.keymap.set('n', '<leader>ba', telescope_bookmarks, { desc = 'Show all bookmarks (Telescope)' })

      -- Navigation
      vim.keymap.set('n', '<leader>bn', '<Plug>BookmarkNext', { desc = 'Next bookmark' })
      vim.keymap.set('n', '<leader>bp', '<Plug>BookmarkPrev', { desc = 'Previous bookmark' })

      -- Clearing bookmarks
      vim.keymap.set('n', '<leader>bc', '<Plug>BookmarkClear', { desc = 'Clear bookmarks in buffer' })
      vim.keymap.set('n', '<leader>bx', '<Plug>BookmarkClearAll', { desc = 'Clear all bookmarks' })

      -- Moving bookmarks
      vim.keymap.set('n', '<leader>bk', '<Plug>BookmarkMoveUp', { desc = 'Move bookmark up' })
      vim.keymap.set('n', '<leader>bj', '<Plug>BookmarkMoveDown', { desc = 'Move bookmark down' })
      vim.keymap.set('n', '<leader>bg', '<Plug>BookmarkMoveToLine', { desc = 'Move bookmark to line' })

      -- Setup highlights (subtle colors for dark themes)
      vim.cmd [[
        highlight BookmarkSign ctermbg=NONE ctermfg=240 guibg=NONE guifg=#374151
        highlight BookmarkAnnotationSign ctermbg=NONE ctermfg=245 guibg=NONE guifg=#374151
        highlight BookmarkLine ctermbg=NONE ctermfg=NONE guibg=#374151 guifg=NONE
        highlight BookmarkAnnotationLine ctermbg=NONE ctermfg=NONE guibg=#374151 guifg=NONE
      ]]

      -- Create a custom command for Telescope bookmarks
      vim.api.nvim_create_user_command('TelescopeBookmarks', telescope_bookmarks, {
        desc = 'Show bookmarks in Telescope',
      })

      -- Setup additional custom commands
      vim.api.nvim_create_user_command('BookmarkSave', function(opts)
        if opts.args ~= '' then
          vim.cmd('BookmarkSave ' .. opts.args)
        else
          local file = vim.fn.input('Save bookmarks to: ', vim.fn.getcwd() .. '/bookmarks.txt')
          if file ~= '' then
            vim.cmd('BookmarkSave ' .. file)
            print('Bookmarks saved to: ' .. file)
          end
        end
      end, {
        nargs = '?',
        complete = 'file',
        desc = 'Save bookmarks to file',
      })

      vim.api.nvim_create_user_command('BookmarkLoad', function(opts)
        if opts.args ~= '' then
          vim.cmd('BookmarkLoad ' .. opts.args)
        else
          local file = vim.fn.input('Load bookmarks from: ', vim.fn.getcwd() .. '/bookmarks.txt')
          if file ~= '' and vim.fn.filereadable(file) == 1 then
            vim.cmd('BookmarkLoad ' .. file)
            print('Bookmarks loaded from: ' .. file)
          elseif file ~= '' then
            print('File not found: ' .. file)
          end
        end
      end, {
        nargs = '?',
        complete = 'file',
        desc = 'Load bookmarks from file',
      })
    end,
  },
}
