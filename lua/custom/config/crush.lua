-- Crush Terminal Panel
local function toggle_crush_terminal()
  local crush_buf = nil
  local crush_win = nil

  -- Find existing crush terminal buffer
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local ok, is_crush_terminal = pcall(vim.api.nvim_buf_get_var, buf, 'is_crush_terminal')
      if ok and is_crush_terminal then
        crush_buf = buf
        break
      end
    end
  end

  -- Find existing crush terminal window
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      if buf == crush_buf then
        crush_win = win
        break
      end
    end
  end

  -- If window exists, close it
  if crush_win and vim.api.nvim_win_is_valid(crush_win) then
    vim.api.nvim_win_close(crush_win, false)
    return
  end

  -- Create new vertical split on the right
  vim.cmd 'rightbelow vsplit'
  local win = vim.api.nvim_get_current_win()

  -- Set window width to 30% of screen
  local screen_width = vim.o.columns
  vim.api.nvim_win_set_width(win, math.floor(screen_width * 0.4))

  if crush_buf and vim.api.nvim_buf_is_valid(crush_buf) then
    -- Use existing buffer
    vim.api.nvim_win_set_buf(win, crush_buf)
  else
    -- Create new terminal buffer
    crush_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_name(crush_buf, 'crush_terminal')
    vim.api.nvim_win_set_buf(win, crush_buf)

    -- Configure buffer options
    vim.bo[crush_buf].buflisted = false

    -- Mark this buffer as the crush terminal
    vim.api.nvim_buf_set_var(crush_buf, 'is_crush_terminal', true)

    -- Start terminal with crush command
    vim.fn.termopen('crush', {
      on_exit = function() end,
    })
  end

  -- Set window options. IE: Don't show linenumbers and vim decorations
  vim.wo[win].number = false
  vim.wo[win].relativenumber = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].cursorline = false
  vim.wo[win].list = false

  -- Enter terminal mode
  vim.cmd 'startinsert'
end

-- Go to Crush terminal pane
-- If one doesn't exist already, make one, otherwise, set active window to it
vim.keymap.set('n', '<leader>ga', function()
  local crush_buf = nil
  local crush_win = nil

  -- Find existing crush terminal buffer
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      local ok, is_crush_terminal = pcall(vim.api.nvim_buf_get_var, buf, 'is_crush_terminal')
      if ok and is_crush_terminal then
        crush_buf = buf
        break
      end
    end
  end

  -- Find existing crush terminal window
  if crush_buf then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_is_valid(win) then
        local buf = vim.api.nvim_win_get_buf(win)
        if buf == crush_buf then
          crush_win = win
          break
        end
      end
    end
  end

  -- If window exists, go to it
  if crush_win and vim.api.nvim_win_is_valid(crush_win) then
    vim.api.nvim_set_current_win(crush_win)
    vim.cmd 'startinsert'
    return
  end

  -- If buffer exists but no window, create window for it
  if crush_buf and vim.api.nvim_buf_is_valid(crush_buf) then
    vim.cmd 'rightbelow vsplit'
    local win = vim.api.nvim_get_current_win()
    local screen_width = vim.o.columns
    vim.api.nvim_win_set_width(win, math.floor(screen_width * 0.4))
    vim.api.nvim_win_set_buf(win, crush_buf)

    -- Set window-local options
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = 'no'
    vim.wo[win].cursorline = false
    vim.wo[win].list = false
    vim.cmd 'startinsert'
    return
  end

  -- If no Crush terminal found, create one
  toggle_crush_terminal()
end, { desc = '[G]o to [A]I terminal pane' })

vim.keymap.set('n', '<leader>ai', toggle_crush_terminal, { desc = 'Toggle [A][I] Crush terminal panel' })
