local M = {}

local function root()
    local dir = vim.fn.getcwd()
    while true do
        if vim.fn.isdirectory(dir .. '/tasks') == 1 then return dir end
        local parent = vim.fn.fnamemodify(dir, ':h')
        if parent == dir then return nil end
        dir = parent
    end
end

local function tasks()
    local project = root()
    if not project then
        vim.notify('TATR: no tasks/ directory found (run :TatrInit)', vim.log.levels.WARN)
        return nil
    end
    local results = {}
    for name, kind in vim.fs.dir(project .. '/tasks') do
        if kind == 'directory' then
            local path = project .. '/tasks/' .. name .. '/TASK.md'
            if vim.fn.filereadable(path) == 1 then
                local lines = vim.fn.readfile(path)
                local title = (lines[1] or ''):gsub('^#%s*', '')
                local status, priority = 'UNKNOWN', '?'
                for _, line in ipairs(lines) do
                    status = line:match('^%s*%-%s*STATUS:%s*(.-)%s*$') or status
                    priority = line:match('^%s*%-%s*PRIORITY:%s*(.-)%s*$') or priority
                end
                table.insert(results, { id = name, title = title, status = status, priority = priority, path = path })
            end
        end
    end
    table.sort(results, function(a, b)
        if a.status ~= b.status then return a.status == 'OPEN' end
        local pa, pb = tonumber(a.priority), tonumber(b.priority)
        if pa and pb and pa ~= pb then return pa < pb end
        return a.id > b.id
    end)
    return results
end

function M.list()
    local entries = tasks()
    if not entries then return end
    if #entries == 0 then
        vim.notify('TATR: no tasks found', vim.log.levels.INFO)
        return
    end
    vim.ui.select(entries, {
        prompt = 'TATR tasks',
        format_item = function(task)
            return string.format('[%s] P%s %s (%s)', task.status, task.priority, task.title, task.id)
        end,
    }, function(task)
        if task then vim.cmd.edit(vim.fn.fnameescape(task.path)) end
    end)
end

local function execute(args, callback)
    local project = root() or vim.fn.getcwd()
    local cmd = vim.list_extend({ 'tatr' }, args)
    vim.system(cmd, { cwd = project, text = true }, function(result)
        vim.schedule(function()
            if result.code ~= 0 then
                vim.notify('TATR: ' .. (result.stderr ~= '' and result.stderr or result.stdout), vim.log.levels.ERROR)
            elseif callback then
                callback(result)
            end
        end)
    end)
end

function M.init()
    execute({ 'init' }, function(result)
        vim.notify(result.stdout ~= '' and result.stdout or 'TATR initialized', vim.log.levels.INFO)
    end)
end

-- TATR creates task metadata; edit the resulting TASK.md to supply its description.
function M.new()
    local project = root()
    if not project then
        vim.notify('TATR: no tasks/ directory found (run :TatrInit)', vim.log.levels.WARN)
        return
    end

    vim.ui.input({ prompt = 'TATR task title: ' }, function(title)
        if not title or not title:match('%S') then return end

        -- Capture existing task IDs so the newly created task is unambiguous.
        local before = {}
        for name, kind in vim.fs.dir(project .. '/tasks') do
            if kind == 'directory' then before[name] = true end
        end

        vim.system({ 'tatr', 'new', title }, { cwd = project, text = true }, function(result)
            vim.schedule(function()
                if result.code ~= 0 then
                    local err = (result.stderr ~= '' and result.stderr or result.stdout) or 'unknown error'
                    vim.notify('TATR: ' .. err, vim.log.levels.ERROR)
                    return
                end

                local created = {}
                for name, kind in vim.fs.dir(project .. '/tasks') do
                    if kind == 'directory' and not before[name] then
                        local path = project .. '/tasks/' .. name .. '/TASK.md'
                        if vim.fn.filereadable(path) == 1 then
                            table.insert(created, path)
                        end
                    end
                end

                if #created ~= 1 then
                    vim.notify('TATR: task created, but could not identify TASK.md; use :Tatr to open it',
                        vim.log.levels.WARN)
                    return
                end

                local path = created[1]
                vim.cmd.edit(vim.fn.fnameescape(path))
                -- Select TATR's default body so typing immediately replaces it.
                local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
                for i, line in ipairs(lines) do
                    if line == 'No description.' then
                        vim.api.nvim_win_set_cursor(0, { i, 0 })
                        vim.cmd('normal! "_dd')
                        vim.cmd('startinsert')
                        return
                    end
                end
                vim.notify('TATR: task created; edit its description in TASK.md', vim.log.levels.INFO)
            end)
        end)
    end)
end


-- Convert the current TODO comment (or a Visual line selection) into a TATR task.
local function comment_text(line)
    local s = vim.trim(line)
    local prefix, body = s:match('^(//+%s*)(.*)
    opts = opts or {}
    if opts.keymap then
        vim.keymap.set('n', opts.keymap, M.list, { desc = 'TATR: list tasks' })
    end
    if opts.comment_keymap then
        vim.keymap.set('n', opts.comment_keymap, M.from_comment, { desc = 'TATR: task from TODO comment' })
        vim.keymap.set('x', opts.comment_keymap, function()
            vim.cmd('normal! \\<Esc>')
            M.from_comment({ visual = true })
        end, { desc = 'TATR: task from selected comments' })
    end
end

return M
)
    if not prefix then prefix, body = s:match('^(#%s+)(.*)
    opts = opts or {}
    if opts.keymap then
        vim.keymap.set('n', opts.keymap, M.list, { desc = 'TATR: list tasks' })
    end
    if opts.comment_keymap then
        vim.keymap.set('n', opts.comment_keymap, M.from_comment, { desc = 'TATR: task from TODO comment' })
        vim.keymap.set('x', opts.comment_keymap, function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'nx', false)
            M.from_comment({ visual = true })
        end, { desc = 'TATR: task from selected comments' })
    end
end

return M
) end
    if not prefix then prefix, body = s:match('^(%-%-%s*)(.*)
    opts = opts or {}
    if opts.keymap then
        vim.keymap.set('n', opts.keymap, M.list, { desc = 'TATR: list tasks' })
    end
end

return M
) end
    if not prefix then prefix, body = s:match('^(/%*+%s*)(.*)
    opts = opts or {}
    if opts.keymap then
        vim.keymap.set('n', opts.keymap, M.list, { desc = 'TATR: list tasks' })
    end
end

return M
) end
    if not prefix then prefix, body = s:match('^(%*%s+)(.*)
    opts = opts or {}
    if opts.keymap then
        vim.keymap.set('n', opts.keymap, M.list, { desc = 'TATR: list tasks' })
    end
end

return M
) end
    if not prefix then prefix, body = s:match('^(<!%-%-%s*)(.*)
    opts = opts or {}
    if opts.keymap then
        vim.keymap.set('n', opts.keymap, M.list, { desc = 'TATR: list tasks' })
    end
end

return M
) end
    if not prefix then return nil end
    body = body:gsub('%s*%*/%s*
    opts = opts or {}
    if opts.keymap then
        vim.keymap.set('n', opts.keymap, M.list, { desc = 'TATR: list tasks' })
    end
end

return M
, ''):gsub('%s*%-%->%s*
    opts = opts or {}
    if opts.keymap then
        vim.keymap.set('n', opts.keymap, M.list, { desc = 'TATR: list tasks' })
    end
end

return M
, '')
    return vim.trim(body), prefix
end

function M.from_comment(opts)
    opts = opts or {}
    local project = root()
    if not project then
        vim.notify('TATR: no tasks/ directory found (run :TatrInit)', vim.log.levels.WARN)
        return
    end
    local buf = vim.api.nvim_get_current_buf()
    if not vim.bo[buf].modifiable then
        vim.notify('TATR: current buffer is not editable', vim.log.levels.WARN)
        return
    end

    local first, last
    if opts.visual then
        first = vim.fn.getpos("'<")[2]
        last = vim.fn.getpos("'>")[2]
        if first == 0 or last == 0 then return end
        if first > last then first, last = last, first end
    else
        first = vim.api.nvim_win_get_cursor(0)[1]
        last = first
        -- Collect adjacent comment lines, but only if the cursor is on a TODO.
        local current = vim.api.nvim_buf_get_lines(buf, first - 1, first, false)[1] or ''
        local text = comment_text(current)
        if not text or not text:match('^TODO[%s:(]') then
            vim.notify('TATR: place cursor on a TODO comment or select comment lines', vim.log.levels.WARN)
            return
        end
        local count = vim.api.nvim_buf_line_count(buf)
        while last < count do
            local next_line = vim.api.nvim_buf_get_lines(buf, last, last + 1, false)[1]
            local next_text = comment_text(next_line or '')
            if not next_text or next_text:match('^TODO[%s:(]') or next_text:match('^TASK%s*%(') then break end
            last = last + 1
        end
    end

    local source = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
    local parts, prefix
    parts = {}
    for _, line in ipairs(source) do
        local body, p = comment_text(line)
        if not body then
            vim.notify('TATR: selection must contain comment lines only', vim.log.levels.WARN)
            return
        end
        prefix = prefix or p
        table.insert(parts, body)
    end
    if #parts == 0 then return end
    local title = parts[1]:gsub('^TODO%s*:?%s*', ''):gsub('^TODO%([^)]*%)%s*:?%s*', '')
    if not title:match('%S') then
        vim.notify('TATR: TODO needs a title', vim.log.levels.WARN)
        return
    end
    local description = table.concat(vim.list_slice(parts, 2), '\n')
    if description == '' then description = parts[1] end

    local before = {}
    for name, kind in vim.fs.dir(project .. '/tasks') do
        if kind == 'directory' then before[name] = true end
    end
    -- An extmark follows the source location while the external command runs.
    local ns = vim.api.nvim_create_namespace('tatr_comment')
    local mark = vim.api.nvim_buf_set_extmark(buf, ns, first - 1, 0, {})
    local source_tick = vim.api.nvim_buf_get_changedtick(buf)

    vim.system({ 'tatr', 'new', title }, { cwd = project, text = true }, function(result)
        vim.schedule(function()
            if result.code ~= 0 then
                vim.notify('TATR: ' .. ((result.stderr ~= '' and result.stderr) or result.stdout or 'creation failed'),
                    vim.log.levels.ERROR)
                return
            end
            local created = {}
            for name, kind in vim.fs.dir(project .. '/tasks') do
                if kind == 'directory' and not before[name] then
                    local path = project .. '/tasks/' .. name .. '/TASK.md'
                    if vim.fn.filereadable(path) == 1 then
                        table.insert(created, { id = name, path = path })
                    end
                end
            end
            if #created ~= 1 then
                vim.notify('TATR: task created; could not identify TASK.md. Use :Tatr to find it.',
                    vim.log.levels.WARN)
                return
            end
            local task = created[1]
            local lines = vim.fn.readfile(task.path)
            local placeholder
            for i, line in ipairs(lines) do
                if line == 'No description.' then placeholder = i; break end
            end
            if not placeholder then
                vim.notify('TATR: task created; description placeholder missing. Open ' .. task.path,
                    vim.log.levels.WARN)
                return
            end
            local body = vim.split(description, '\n', { plain = true })
            table.remove(lines, placeholder)
            for i = #body, 1, -1 do table.insert(lines, placeholder, body[i]) end
            local ok, err = pcall(vim.fn.writefile, lines, task.path)
            if not ok then
                vim.notify('TATR: task created but could not save description: ' .. tostring(err),
                    vim.log.levels.ERROR)
                return
            end

            -- Never overwrite source code that changed while TATR was running.
            if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_changedtick(buf) == source_tick then
                local pos = vim.api.nvim_buf_get_extmark_by_id(buf, ns, mark, { details = true })
                if #pos > 0 and pos[1] == first - 1 then
                    local same = vim.deep_equal(vim.api.nvim_buf_get_lines(buf, first - 1, last, false), source)
                    if same then
                        local indent = source[1]:match('^%s*') or ''
                        local marker = prefix
                        if marker:match('^/%*') then marker = '/* ' end
                        if marker:match('^<!') then marker = '<!-- ' end
                        local replacement = indent .. marker .. 'TASK(' .. task.id .. '): ' .. title
                        if marker:match('^<!') then replacement = replacement .. ' -->' end
                        if marker:match('^/%*') then replacement = replacement .. ' */' end
                        vim.api.nvim_buf_set_lines(buf, first - 1, last, false, { replacement })
                    end
                end
            else
                vim.notify('TATR: source changed; original TODO left untouched', vim.log.levels.WARN)
            end
            vim.notify('TATR: created ' .. task.id, vim.log.levels.INFO)
        end)
    end)
end

function M.setup(opts)
    opts = opts or {}
    if opts.keymap then
        vim.keymap.set('n', opts.keymap, M.list, { desc = 'TATR: list tasks' })
    end
end

return M
