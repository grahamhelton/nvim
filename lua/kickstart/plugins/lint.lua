return {

  { -- Linting
    'mfussenegger/nvim-lint',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      local lint = require 'lint'
      
      -- Gosec cache management
      local gosec_cache = {}
      local cache_file = vim.fn.stdpath('cache') .. '/gosec_results.json'
      local last_scan_time = 0
      local scan_interval = 30 -- seconds between background scans
      
      -- Load gosec cache from disk
      local function load_cache()
        local file = io.open(cache_file, 'r')
        if file then
          local content = file:read('*all')
          file:close()
          local ok, data = pcall(vim.json.decode, content)
          if ok and data then
            gosec_cache = data
            return true
          end
        end
        return false
      end
      
      -- Save gosec cache to disk
      local function save_cache()
        local file = io.open(cache_file, 'w')
        if file then
          file:write(vim.json.encode(gosec_cache))
          file:close()
          return true
        end
        return false
      end
      
      -- Get project root for consistent cache keys
      local function get_project_root()
        local root = vim.fn.findfile('go.mod', '.;')
        if root ~= '' then
          return vim.fn.fnamemodify(root, ':p:h')
        end
        return vim.fn.getcwd()
      end
      
      -- Get file modification time
      local function get_file_mtime(filepath)
        local stat = vim.loop.fs_stat(filepath)
        return stat and stat.mtime.sec or 0
      end
      
      -- Check if cache is valid for current project
      local function is_cache_valid()
        local project_root = get_project_root()
        local cache_key = project_root
        
        if not gosec_cache[cache_key] then
          return false
        end
        
        local cached_data = gosec_cache[cache_key]
        local cache_time = cached_data.scan_time or 0
        
        -- Check if any Go files changed since last scan
        local go_files = vim.fn.globpath(project_root, '**/*.go', false, true)
        for _, file in ipairs(go_files) do
          local mtime = get_file_mtime(file)
          if mtime > cache_time then
            return false -- File changed since last scan
          end
        end
        
        return true
      end
      
      -- Get cached diagnostics for current file
      local function get_cached_diagnostics(filepath)
        local project_root = get_project_root()
        local cache_key = project_root
        
        if not gosec_cache[cache_key] then
          return {}
        end
        
        local cached_data = gosec_cache[cache_key]
        local rel_path = filepath:gsub('^' .. vim.pesc(project_root) .. '/?', '')
        
        -- Try exact match first
        if cached_data.issues[rel_path] then
          return cached_data.issues[rel_path]
        end
        
        -- Try fuzzy matching if exact fails
        for cached_file, issues in pairs(cached_data.issues) do
          if filepath:match(cached_file:gsub('%.', '%%%.')) or cached_file:match(rel_path:gsub('%.', '%%%.')) then
            return issues
          end
        end
        
        return {}
      end
      
      -- Update cache with new gosec results
      local function update_cache(gosec_output)
        local project_root = get_project_root()
        local cache_key = project_root
        
        gosec_cache[cache_key] = {
          scan_time = os.time(),
          issues = {}
        }
        
        if gosec_output.Issues then
          for _, issue in ipairs(gosec_output.Issues) do
            local filepath = issue.file
            if filepath then
              local rel_path = filepath:gsub('^' .. vim.pesc(project_root) .. '/?', '')
              if not gosec_cache[cache_key].issues[rel_path] then
                gosec_cache[cache_key].issues[rel_path] = {}
              end
              table.insert(gosec_cache[cache_key].issues[rel_path], issue)
            end
          end
        end
        
        save_cache()
      end
      
      -- Background gosec scan
      local function background_scan()
        local current_time = os.time()
        if current_time - last_scan_time < scan_interval then
          return -- Too soon since last scan
        end
        
        last_scan_time = current_time
        
        local cmd = 'gosec -fmt=json -quiet ./...'
        vim.fn.jobstart(cmd, {
          cwd = get_project_root(),
          on_stdout = function(_, data)
            if data and #data > 0 then
              local output = table.concat(data, '\n')
              if output ~= '' and output ~= '{}' then
                local ok, decoded = pcall(vim.json.decode, output)
                if ok and decoded then
                  update_cache(decoded)
                  -- Refresh diagnostics for open Go buffers
                  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'go' then
                      vim.schedule(function()
                        if vim.api.nvim_buf_is_valid(buf) then
                          lint.try_lint('gosec', { buf = buf })
                        end
                      end)
                    end
                  end
                end
              end
            end
          end,
          on_stderr = function(_, data)
            if data and #data > 0 then
              local error_msg = table.concat(data, '\n')
              if error_msg:match('%S') then
                -- Silent background errors to avoid noise
              end
            end
          end
        })
      end
      
      -- Initialize cache
      load_cache()
      
      -- Configure gosec linter with smart caching
      lint.linters.gosec = {
        name = 'gosec',
        cmd = 'gosec',
        stdin = false,
        args = {
          '-fmt',
          'json', 
          '-quiet',
          '-no-fail',
          './...',
        },
        stream = 'stdout',
        ignore_exitcode = true,
        parser = function(output, bufnr)
          local current_file = vim.api.nvim_buf_get_name(bufnr)
          
          -- First check if we have valid cached results
          if is_cache_valid() then
            local cached_issues = get_cached_diagnostics(current_file)
            local diagnostics = {}
            
            for _, issue in ipairs(cached_issues) do
              local line = math.max((tonumber(issue.line) or 1) - 1, 0)
              local col = math.max((tonumber(issue.column) or 1) - 1, 0)

              local severity = vim.diagnostic.severity.WARN
              if issue.severity == 'HIGH' then
                severity = vim.diagnostic.severity.ERROR
              elseif issue.severity == 'LOW' then
                severity = vim.diagnostic.severity.INFO
              end

              local diagnostic = {
                lnum = line,
                col = col,
                end_lnum = line,
                end_col = col + 1,
                severity = severity,
                message = string.format('[%s] %s', issue.rule_id or 'G000', issue.details or 'Security issue detected'),
                source = 'gosec',
                code = issue.rule_id,
                user_data = {
                  confidence = issue.confidence,
                  severity = issue.severity,
                  cached = true,
                },
              }
              
              table.insert(diagnostics, diagnostic)
            end
            
            return diagnostics
          end
          
          -- No valid cache - parse fresh gosec output
          if output == '' or output == '{}' then
            return {}
          end

          local ok, decoded = pcall(vim.json.decode, output)
          if not ok then
            vim.notify('Gosec: Failed to parse JSON output', vim.log.levels.WARN)
            return {}
          end

          -- Update cache with fresh results
          update_cache(decoded)

          local diagnostics = {}
          
          if decoded.Issues then
            for _, issue in ipairs(decoded.Issues) do
              local filename = issue.file
              
              if filename then
                -- Flexible file matching
                local match = false
                if current_file == filename then
                  match = true
                elseif current_file:match(filename:gsub('./', '')) then
                  match = true  
                elseif filename:match(current_file:gsub('.+/', '')) then
                  match = true
                end
                
                if match then
                  local line = math.max((tonumber(issue.line) or 1) - 1, 0)
                  local col = math.max((tonumber(issue.column) or 1) - 1, 0)

                  local severity = vim.diagnostic.severity.WARN
                  if issue.severity == 'HIGH' then
                    severity = vim.diagnostic.severity.ERROR
                  elseif issue.severity == 'LOW' then
                    severity = vim.diagnostic.severity.INFO
                  end

                  local diagnostic = {
                    lnum = line,
                    col = col,
                    end_lnum = line,
                    end_col = col + 1,
                    severity = severity,
                    message = string.format('[%s] %s', issue.rule_id or 'G000', issue.details or 'Security issue detected'),
                    source = 'gosec',
                    code = issue.rule_id,
                    user_data = {
                      confidence = issue.confidence,
                      severity = issue.severity,
                      cached = false,
                    },
                  }
                  
                  table.insert(diagnostics, diagnostic)
                end
              end
            end
          end

          return diagnostics
        end,
      }
      
      lint.linters_by_ft = {
        go = { 'gosec' },
        --markdown = { 'markdownlint' },
      }

      -- To allow other plugins to add linters to require('lint').linters_by_ft,
      -- instead set linters_by_ft like this:
      -- lint.linters_by_ft = lint.linters_by_ft or {}
      -- lint.linters_by_ft['markdown'] = { 'markdownlint' }
      --
      -- However, note that this will enable a set of default linters,
      -- which will cause errors unless these tools are available:
      -- {
      --   clojure = { "clj-kondo" },
      --   dockerfile = { "hadolint" },
      --   inko = { "inko" },
      --   janet = { "janet" },
      --   json = { "jsonlint" },
      --   markdown = { "vale" },
      --   rst = { "vale" },
      --   ruby = { "ruby" },
      --   terraform = { "tflint" },
      --   text = { "vale" }
      -- }
      --
      -- You can disable the default linters by setting their filetypes to nil:
      -- lint.linters_by_ft['clojure'] = nil
      -- lint.linters_by_ft['dockerfile'] = nil
      -- lint.linters_by_ft['inko'] = nil
      -- lint.linters_by_ft['janet'] = nil
      -- lint.linters_by_ft['json'] = nil
      -- lint.linters_by_ft['markdown'] = nil
      -- lint.linters_by_ft['rst'] = nil
      -- lint.linters_by_ft['ruby'] = nil
      -- lint.linters_by_ft['terraform'] = nil
      -- lint.linters_by_ft['text'] = nil

      -- Create autocommand which carries out the actual linting
      -- on the specified events.
      local lint_augroup = vim.api.nvim_create_augroup('lint', { clear = true })
      vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'InsertLeave' }, {
        group = lint_augroup,
        callback = function()
          -- Only run the linter in buffers that you can modify in order to
          -- avoid superfluous noise, notably within the handy LSP pop-ups that
          -- describe the hovered symbol using Markdown.
          if vim.bo.modifiable then
            lint.try_lint()
          end
        end,
      })

      -- Enhanced autocmd for Go files with smart caching
      vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufEnter' }, {
        group = lint_augroup,
        pattern = '*.go',
        callback = function()
          if vim.g.gosec_auto_enabled ~= false and vim.fn.executable('gosec') == 1 and vim.bo.modifiable then
            vim.defer_fn(function()
              if vim.api.nvim_buf_is_valid(0) and vim.bo.filetype == 'go' then
                -- Check cache first, then apply directly
                if is_cache_valid() then
                  local current_file = vim.api.nvim_buf_get_name(0)
                  local cached_issues = get_cached_diagnostics(current_file)
                  
                  -- Apply cached diagnostics directly
                  local diagnostics = {}
                  for _, issue in ipairs(cached_issues) do
                    local line = math.max((tonumber(issue.line) or 1) - 1, 0)
                    local col = math.max((tonumber(issue.column) or 1) - 1, 0)

                    local severity = vim.diagnostic.severity.WARN
                    if issue.severity == 'HIGH' then
                      severity = vim.diagnostic.severity.ERROR
                    elseif issue.severity == 'LOW' then
                      severity = vim.diagnostic.severity.INFO
                    end

                    local diagnostic = {
                      lnum = line,
                      col = col,
                      end_lnum = line,
                      end_col = col + 1,
                      severity = severity,
                      message = string.format('[%s] %s', issue.rule_id or 'G000', issue.details or 'Security issue detected'),
                      source = 'gosec',
                      code = issue.rule_id,
                      user_data = {
                        confidence = issue.confidence,
                        severity = issue.severity,
                        cached = true,
                      },
                    }
                    
                    table.insert(diagnostics, diagnostic)
                  end
                  
                  -- Set diagnostics directly
                  vim.diagnostic.set(vim.api.nvim_create_namespace('gosec'), 0, diagnostics)
                else
                  -- Cache invalid - run fresh scan
                  lint.try_lint('gosec')
                end
              end
            end, 100) -- Small delay to ensure buffer is ready
          end
        end,
      })
      
      -- Save autocmd - invalidate cache and refresh  
      vim.api.nvim_create_autocmd('BufWritePost', {
        group = lint_augroup,
        pattern = '*.go',
        callback = function()
          if vim.g.gosec_auto_enabled ~= false and vim.fn.executable('gosec') == 1 then
            -- Invalidate cache since file was modified
            local project_root = get_project_root()
            local cache_key = project_root
            if gosec_cache[cache_key] then
              gosec_cache[cache_key].scan_time = 0
            end
            
            -- Re-run gosec on save with fresh data
            vim.defer_fn(function()
              if vim.api.nvim_buf_is_valid(0) and vim.bo.filetype == 'go' then
                lint.try_lint('gosec')
              end
            end, 100)
          end
        end,
      })

      -- Manual gosec scan (bypasses cache)
      local function manual_gosec_scan()
        local cmd = 'gosec -fmt=json -quiet ./...'
        vim.notify('Gosec: Running security scan...', vim.log.levels.INFO)
        
        vim.fn.jobstart(cmd, {
          cwd = get_project_root(),
          on_stdout = function(_, data)
            if data and #data > 0 then
              local output = table.concat(data, '\n')
              if output ~= '' and output ~= '{}' then
                local ok, decoded = pcall(vim.json.decode, output)
                if ok and decoded then
                  update_cache(decoded)
                  vim.notify('Gosec: Scan complete, cache updated', vim.log.levels.INFO)
                  
                  -- Refresh all Go buffers
                  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
                    if vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].filetype == 'go' then
                      vim.schedule(function()
                        if vim.api.nvim_buf_is_valid(buf) then
                          lint.try_lint('gosec', { buf = buf })
                        end
                      end)
                    end
                  end
                else
                  vim.notify('Gosec: No security issues found', vim.log.levels.INFO)
                end
              else
                vim.notify('Gosec: No security issues found', vim.log.levels.INFO)
              end
            end
          end,
          on_stderr = function(_, data)
            if data and #data > 0 then
              local error_msg = table.concat(data, '\n')
              if error_msg:match('%S') then
                vim.notify('Gosec error: ' .. error_msg, vim.log.levels.ERROR)
              end
            end
          end
        })
      end

      -- Gosec-specific commands
      vim.api.nvim_create_user_command('GosecLint', function()
        if vim.bo.filetype ~= 'go' then
          vim.notify('Gosec: Not a Go file', vim.log.levels.WARN)
          return
        end
        
        -- Check if we can use cached results
        if is_cache_valid() then
          local current_file = vim.api.nvim_buf_get_name(0)
          local cached_issues = get_cached_diagnostics(current_file)
          
          if #cached_issues > 0 then
            vim.notify('Gosec: Using cached results (' .. #cached_issues .. ' issues)', vim.log.levels.INFO)
          end
          
          -- Apply cached diagnostics directly
          local diagnostics = {}
          for _, issue in ipairs(cached_issues) do
            local line = math.max((tonumber(issue.line) or 1) - 1, 0)
            local col = math.max((tonumber(issue.column) or 1) - 1, 0)

            local severity = vim.diagnostic.severity.WARN
            if issue.severity == 'HIGH' then
              severity = vim.diagnostic.severity.ERROR
            elseif issue.severity == 'LOW' then
              severity = vim.diagnostic.severity.INFO
            end

            local diagnostic = {
              lnum = line,
              col = col,
              end_lnum = line,
              end_col = col + 1,
              severity = severity,
              message = string.format('[%s] %s', issue.rule_id or 'G000', issue.details or 'Security issue detected'),
              source = 'gosec',
              code = issue.rule_id,
              user_data = {
                confidence = issue.confidence,
                severity = issue.severity,
                cached = true,
              },
            }
            
            table.insert(diagnostics, diagnostic)
          end
          
          -- Set diagnostics directly
          vim.diagnostic.set(vim.api.nvim_create_namespace('gosec'), 0, diagnostics)
        else
          vim.notify('Gosec: Running fresh scan...', vim.log.levels.INFO)
          lint.try_lint 'gosec'
        end
      end, { desc = 'Run gosec linter on current Go file' })
      
      vim.api.nvim_create_user_command('GosecScan', function()
        manual_gosec_scan()
      end, { desc = 'Force fresh gosec scan (bypass cache)' })
      
      vim.api.nvim_create_user_command('GosecCache', function(opts)
        local arg = opts.args:lower()
        
        if arg == 'clear' then
          gosec_cache = {}
          save_cache()
          vim.notify('Gosec: Cache cleared', vim.log.levels.INFO)
        elseif arg == 'status' then
          local project_root = get_project_root()
          local cache_key = project_root
          
          if gosec_cache[cache_key] then
            local cached_data = gosec_cache[cache_key]
            local scan_time = os.date('%Y-%m-%d %H:%M:%S', cached_data.scan_time)
            local issue_count = 0
            for _, issues in pairs(cached_data.issues) do
              issue_count = issue_count + #issues
            end
            
            vim.notify('Gosec Cache Status:', vim.log.levels.INFO)
            vim.notify('  Project: ' .. project_root, vim.log.levels.INFO)
            vim.notify('  Last scan: ' .. scan_time, vim.log.levels.INFO)
            vim.notify('  Total issues: ' .. issue_count, vim.log.levels.INFO)
            vim.notify('  Cache valid: ' .. (is_cache_valid() and 'Yes' or 'No'), vim.log.levels.INFO)
          else
            vim.notify('Gosec: No cache data for current project', vim.log.levels.INFO)
          end
        else
          vim.notify('Usage: :GosecCache {clear|status}', vim.log.levels.INFO)
        end
      end, { 
        desc = 'Manage gosec cache',
        nargs = 1,
        complete = function() return { 'clear', 'status' } end
      })
      
      -- Telescope picker for gosec issues
      vim.api.nvim_create_user_command('GosecTelescope', function()
        local project_root = get_project_root()
        local cache_key = project_root
        
        if not gosec_cache[cache_key] then
          vim.notify('Gosec: No cache data. Run :GosecScan first', vim.log.levels.WARN)
          return
        end
        
        local cached_data = gosec_cache[cache_key]
        local entries = {}
        
        -- Build entries for telescope
        for file_path, issues in pairs(cached_data.issues) do
          if #issues > 0 then
            -- Count issues by severity
            local high_count = 0
            local medium_count = 0
            local low_count = 0
            local rule_summary = {}
            
            for _, issue in ipairs(issues) do
              if issue.severity == 'HIGH' then
                high_count = high_count + 1
              elseif issue.severity == 'MEDIUM' then
                medium_count = medium_count + 1
              else
                low_count = low_count + 1
              end
              
              -- Collect unique rule IDs
              if issue.rule_id and not rule_summary[issue.rule_id] then
                rule_summary[issue.rule_id] = true
              end
            end
            
            -- Create display text
            local severity_text = ''
            if high_count > 0 then severity_text = severity_text .. 'H:' .. high_count .. ' ' end
            if medium_count > 0 then severity_text = severity_text .. 'M:' .. medium_count .. ' ' end
            if low_count > 0 then severity_text = severity_text .. 'L:' .. low_count .. ' ' end
            
            local rules_text = table.concat(vim.tbl_keys(rule_summary), ', ')
            if #rules_text > 50 then
              rules_text = rules_text:sub(1, 47) .. '...'
            end
            
            table.insert(entries, {
              value = file_path,
              display = string.format("%-50s %s %s", file_path, severity_text, rules_text),
              ordinal = file_path .. ' ' .. rules_text,
              path = project_root .. '/' .. file_path,
              issues = issues,
            })
          end
        end
        
        if #entries == 0 then
          vim.notify('Gosec: No security issues found in cache', vim.log.levels.INFO)
          return
        end
        
        -- Use telescope to display results
        local telescope = require('telescope')
        local pickers = require('telescope.pickers')
        local finders = require('telescope.finders')
        local conf = require('telescope.config').values
        local actions = require('telescope.actions')
        local action_state = require('telescope.actions.state')
        
        pickers.new({}, {
          prompt_title = 'Gosec Security Issues (' .. #entries .. ' files)',
          finder = finders.new_table({
            results = entries,
            entry_maker = function(entry)
              return {
                value = entry.value,
                display = entry.display,
                ordinal = entry.ordinal,
                path = entry.path,
                issues = entry.issues,
              }
            end,
          }),
          sorter = conf.generic_sorter({}),
          attach_mappings = function(prompt_bufnr, map)
            actions.select_default:replace(function()
              actions.close(prompt_bufnr)
              local selection = action_state.get_selected_entry()
              if selection then
                -- Open the file
                vim.cmd('edit ' .. selection.path)
                
                -- Show issue count
                if #selection.issues > 0 then
                  vim.notify('Gosec: Opened file with ' .. #selection.issues .. ' security issues', vim.log.levels.INFO)
                end
                
                -- Trigger gosec to show diagnostics
                vim.defer_fn(function()
                  vim.cmd('GosecLint')
                end, 100)
              end
            end)
            
            -- Add preview of issues with <C-p>
            map('i', '<C-p>', function()
              local selection = action_state.get_selected_entry()
              if selection and selection.issues then
                local lines = { 'Gosec Issues in ' .. selection.value .. ':' }
                table.insert(lines, '')
                
                for i, issue in ipairs(selection.issues) do
                  local severity_text = '[' .. (issue.severity or 'UNKNOWN') .. ']'
                  table.insert(lines, string.format('%d. %s [%s] Line %s', 
                    i, severity_text, issue.rule_id or 'G000', issue.line or '?'))
                  table.insert(lines, '   ' .. (issue.details or 'Security issue detected'))
                  if i < #selection.issues then table.insert(lines, '') end
                end
                
                -- Create preview buffer
                local buf = vim.api.nvim_create_buf(false, true)
                vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
                vim.bo[buf].filetype = 'markdown'
                vim.bo[buf].modifiable = false
                
                -- Show in split
                vim.cmd('split')
                vim.api.nvim_win_set_buf(0, buf)
                vim.cmd('resize 15')
              end
            end)
            
            return true
          end,
        }):find()
      end, { desc = 'Show gosec issues in Telescope' })
      
      vim.api.nvim_create_user_command('GosecDebug', function()
        if vim.bo.filetype ~= 'go' then
          vim.notify('Gosec: Not a Go file', vim.log.levels.WARN)
          return
        end
        
        local current_file = vim.api.nvim_buf_get_name(0)
        vim.notify('Gosec Debug Info:', vim.log.levels.INFO)
        vim.notify('  Current file: ' .. current_file, vim.log.levels.INFO)
        vim.notify('  Working directory: ' .. vim.fn.getcwd(), vim.log.levels.INFO)
        vim.notify('  Project root: ' .. get_project_root(), vim.log.levels.INFO)
        vim.notify('  Buffer filetype: ' .. vim.bo.filetype, vim.log.levels.INFO)
        vim.notify('  Gosec executable: ' .. tostring(vim.fn.executable('gosec') == 1), vim.log.levels.INFO)
        vim.notify('  Cache valid: ' .. tostring(is_cache_valid()), vim.log.levels.INFO)
        vim.notify('  Auto-run enabled: ' .. tostring(vim.g.gosec_auto_enabled ~= false), vim.log.levels.INFO)
        
        -- Show current diagnostics
        local diagnostics = vim.diagnostic.get(0, { source = 'gosec' })
        vim.notify('  Current gosec diagnostics: ' .. #diagnostics, vim.log.levels.INFO)
        
        -- Test manual lint
        vim.notify('  Running manual lint test...', vim.log.levels.INFO)
        lint.try_lint('gosec')
        
        -- Show diagnostics after lint
        vim.defer_fn(function()
          local after_diagnostics = vim.diagnostic.get(0, { source = 'gosec' })
          vim.notify('  Diagnostics after lint: ' .. #after_diagnostics, vim.log.levels.INFO)
        end, 1000)
        
      end, { desc = 'Debug gosec integration' })
      
      vim.api.nvim_create_user_command('GosecToggleAuto', function()
        if vim.g.gosec_auto_enabled == false then
          vim.g.gosec_auto_enabled = true
          vim.notify('Gosec: Auto-run enabled', vim.log.levels.INFO)
        else
          vim.g.gosec_auto_enabled = false
          vim.notify('Gosec: Auto-run disabled', vim.log.levels.INFO)
        end
      end, { desc = 'Toggle gosec auto-run on file open' })

      vim.api.nvim_create_user_command('GosecCheck', function()
        if not vim.fn.executable 'gosec' then
          vim.notify('Gosec: gosec not found in PATH', vim.log.levels.ERROR)
          return
        end

        vim.notify('Gosec: Running security scan...', vim.log.levels.INFO)

        local cmd = 'gosec -fmt=json -quiet ./...'
        vim.fn.jobstart(cmd, {
          cwd = vim.fn.getcwd(),
          on_stdout = function(_, data)
            if data and #data > 0 then
              local output = table.concat(data, '\n')
              if output ~= '' and output ~= '{}' then
                local ok, decoded = pcall(vim.json.decode, output)
                if ok and decoded.Issues then
                  local issue_count = #decoded.Issues
                  vim.notify(string.format('Gosec: Found %d security issue(s)', issue_count), issue_count > 0 and vim.log.levels.WARN or vim.log.levels.INFO)
                  lint.try_lint 'gosec'
                else
                  vim.notify('Gosec: No issues found', vim.log.levels.INFO)
                end
              else
                vim.notify('Gosec: No issues found', vim.log.levels.INFO)
              end
            end
          end,
          on_stderr = function(_, data)
            if data and #data > 0 then
              local error_msg = table.concat(data, '\n')
              if error_msg:match '%S' then -- Non-empty error
                vim.notify('Gosec error: ' .. error_msg, vim.log.levels.ERROR)
              end
            end
          end,
        })
      end, { desc = 'Run gosec scan on entire project' })

      vim.api.nvim_create_user_command('GosecRules', function()
        local rules_info = {
          'Available Gosec Rules:',
          '',
          'G101 - Look for hard coded credentials',
          'G102 - Bind to all interfaces',
          'G103 - Audit the use of unsafe block',
          'G104 - Audit errors not checked',
          'G105 - Audit the use of math/big.Int.Exp',
          'G106 - Audit the use of ssh.InsecureIgnoreHostKey',
          'G107 - Url provided to HTTP request as taint input',
          'G108 - Profiling endpoint automatically exposed',
          'G109 - Potential Integer overflow made by strconv.Atoi result conversion',
          'G110 - Potential DoS vulnerability via decompression bomb',
          'G201 - SQL query construction using format string',
          'G202 - SQL query construction using string concatenation',
          'G203 - Use of unescaped data in HTML templates',
          'G204 - Audit use of command execution',
          'G301 - Poor file permissions used when creating a directory',
          'G302 - Poor file permissions used with chmod',
          'G303 - Creating tempfile using a predictable path',
          'G304 - File path provided as taint input',
          'G305 - File traversal when extracting zip/tar archive',
          'G306 - Poor file permissions used when writing to a new file',
          'G307 - Deferring a method which returns an error',
          'G401 - Detect the usage of DES, RC4, MD5 or SHA1',
          'G402 - Look for bad TLS connection settings',
          'G403 - Ensure minimum RSA key length of 2048 bits',
          'G404 - Insecure random number source (rand)',
          'G501 - Import blocklist: crypto/md5',
          'G502 - Import blocklist: crypto/des',
          'G503 - Import blocklist: crypto/rc4',
          'G504 - Import blocklist: net/http/cgi',
          'G505 - Import blocklist: crypto/sha1',
          'G601 - Implicit memory aliasing of items from a range statement',
        }

        vim.cmd 'split'
        local buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, rules_info)
        vim.bo[buf].filetype = 'text'
        vim.bo[buf].modifiable = false
        vim.api.nvim_win_set_buf(0, buf)
      end, { desc = 'Show gosec rules reference' })

      -- Keybindings for Go files only
      vim.api.nvim_create_autocmd('FileType', {
        group = lint_augroup,
        pattern = 'go',
        callback = function()
          local opts = { buffer = true, silent = true }

          vim.keymap.set('n', '<leader>gs', function()
            vim.cmd 'GosecLint'
          end, vim.tbl_extend('force', opts, { desc = 'Run gosec on current file' }))

          vim.keymap.set('n', '<leader>gr', function()
            vim.cmd 'GosecRules'
          end, vim.tbl_extend('force', opts, { desc = 'Show gosec rules' }))
          
          -- Show only gosec diagnostics
          vim.keymap.set('n', '<leader>gd', function()
            vim.diagnostic.setqflist({ severity = nil, source = 'gosec' })
          end, vim.tbl_extend('force', opts, { desc = 'Show gosec diagnostics' }))
          
          -- Debug: show all current diagnostics
          vim.keymap.set('n', '<leader>gD', function()
            local diagnostics = vim.diagnostic.get(0)
            vim.notify('Total diagnostics in buffer: ' .. #diagnostics, vim.log.levels.INFO)
            for _, diag in ipairs(diagnostics) do
              vim.notify('Diagnostic: ' .. (diag.source or 'unknown') .. ' - ' .. diag.message, vim.log.levels.INFO)
            end
          end, vim.tbl_extend('force', opts, { desc = 'Debug all diagnostics' }))
          
          -- Toggle gosec auto-run
          vim.keymap.set('n', '<leader>gt', function()
            vim.cmd 'GosecToggleAuto'
          end, vim.tbl_extend('force', opts, { desc = 'Toggle gosec auto-run' }))
          
          -- Force fresh scan (bypass cache)
          vim.keymap.set('n', '<leader>gS', function()
            vim.cmd 'GosecScan'
          end, vim.tbl_extend('force', opts, { desc = 'Force fresh gosec scan' }))
          
          -- Cache management
          vim.keymap.set('n', '<leader>gc', function()
            vim.cmd 'GosecCache status'
          end, vim.tbl_extend('force', opts, { desc = 'Show gosec cache status' }))
          
          -- Telescope picker for all gosec issues
          vim.keymap.set('n', '<leader>gf', function()
            vim.cmd 'GosecTelescope'
          end, vim.tbl_extend('force', opts, { desc = 'Find files with gosec issues' }))
        end,
      })

      -- Initialize gosec auto-run (enabled by default)
      if vim.g.gosec_auto_enabled == nil then
        vim.g.gosec_auto_enabled = true
      end

      -- Check if gosec is installed and show cache info
      if vim.fn.executable 'gosec' == 0 then
        vim.notify('Gosec: gosec not found. Install with: go install github.com/securego/gosec/v2/cmd/gosec@latest', vim.log.levels.WARN)
      else
        local cache_info = ''
        if load_cache() then
          local total_projects = 0
          for _ in pairs(gosec_cache) do
            total_projects = total_projects + 1
          end
          cache_info = ' (Cache: ' .. total_projects .. ' projects)'
        else
          cache_info = ' (Cache: empty)'
        end
        
        vim.notify('Gosec: Security scanner loaded' .. cache_info, vim.log.levels.INFO)
      end
    end,
  },
}

