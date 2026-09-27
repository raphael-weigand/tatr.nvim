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


-- Create a task from a TODO comment or selected comment lines.
local function parse_comment(line)
    local indent, marker, text = line:match("^(%s*)(//+%s*)(.*)$")
    if not marker then indent, marker, text = line:match("^(%s*)(%-%-%s*)(.*)$") end
    if not marker then indent, marker, text = line:match("^(%s*)(#%s*)(.*)$") end
    if not marker then indent, marker, text = line:match("^(%s*)(/%*+%s*)(.*)$") end
    if not marker then indent, marker, text = line:match("^(%s*)(%*%s+)(.*)$") end
    if not marker then indent, marker, text = line:match("^(%s*)(<!%-%-%s*)(.*)$") end
    if not marker then return nil end
    text = vim.trim(text:gsub("%s*%*/%s*$", ""):gsub("%s*%-%->%s*$", ""))
    return { indent = indent, marker = marker, text = text }
end

function M.from_comment(opts)
    opts = opts or {}
    local project = root()
    if not project then
        vim.notify("TATR: run :TatrInit first", vim.log.levels.WARN)
        return
    end
    local buf = vim.api.nvim_get_current_buf()
    if not vim.bo[buf].modifiable then return end

    local first, last
    if opts.visual then
        first, last = vim.fn.getpos("'<")[2], vim.fn.getpos("'>")[2]
        if first == 0 or last == 0 then return end
        if first > last then first, last = last, first end
    else
        first = vim.api.nvim_win_get_cursor(0)[1]
        last = first
        local current = parse_comment(vim.api.nvim_buf_get_lines(buf, first - 1, first, false)[1] or "")
        if not current or not current.text:match("^TODO[%s:(]") then
            vim.notify("TATR: place cursor on a TODO comment", vim.log.levels.WARN)
            return
        end
        local count = vim.api.nvim_buf_line_count(buf)
        while last < count do
            local next_line = vim.api.nvim_buf_get_lines(buf, last, last + 1, false)[1]
            local next_comment = parse_comment(next_line or "")
            if not next_comment or next_comment.text:match("^TODO[%s:(]") or next_comment.text:match("^TASK%s*%(") then break end
            last = last + 1
        end
    end

    local original = vim.api.nvim_buf_get_lines(buf, first - 1, last, false)
    local comments = {}
    for _, line in ipairs(original) do
        local comment = parse_comment(line)
        if not comment then
            vim.notify("TATR: select comment lines only", vim.log.levels.WARN)
            return
        end
        table.insert(comments, comment)
    end
    if #comments == 0 then return end

    local title = comments[1].text:gsub("^TODO%s*:%s*", ""):gsub("^TODO%s+", ""):gsub("^TODO%([^)]*%)%s*:%s*", "")
    if not title:match("%S") then
        vim.notify("TATR: TODO has no title", vim.log.levels.WARN)
        return
    end
    local description_lines = {}
    for i = 2, #comments do table.insert(description_lines, comments[i].text) end
    if #description_lines == 0 then description_lines = { comments[1].text } end

    local before = {}
    for name, kind in vim.fs.dir(project .. "/tasks") do
        if kind == "directory" then before[name] = true end
    end
    local tick = vim.api.nvim_buf_get_changedtick(buf)

    vim.system({ "tatr", "new", title }, { cwd = project, text = true }, function(result)
        vim.schedule(function()
            if result.code ~= 0 then
                vim.notify("TATR: " .. (result.stderr ~= "" and result.stderr or result.stdout or "creation failed"), vim.log.levels.ERROR)
                return
            end
            local created = {}
            for name, kind in vim.fs.dir(project .. "/tasks") do
                if kind == "directory" and not before[name] then
                    local path = project .. "/tasks/" .. name .. "/TASK.md"
                    if vim.fn.filereadable(path) == 1 then table.insert(created, { id = name, path = path }) end
                end
            end
            if #created ~= 1 then
                vim.notify("TATR: task created, use :Tatr to find it", vim.log.levels.WARN)
                return
            end
            local task = created[1]
            local lines = vim.fn.readfile(task.path)
            local placeholder
            for i, line in ipairs(lines) do
                if line == "No description." then placeholder = i; break end
            end
            if not placeholder then
                vim.notify("TATR: task created but description placeholder was not found", vim.log.levels.WARN)
                return
            end
            table.remove(lines, placeholder)
            for i = #description_lines, 1, -1 do
                table.insert(lines, placeholder, description_lines[i])
            end
            local ok, err = pcall(vim.fn.writefile, lines, task.path)
            if not ok then
                vim.notify("TATR: could not save description: " .. tostring(err), vim.log.levels.ERROR)
                return
            end

            -- Preserve edits made while the external process was running.
            if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_changedtick(buf) == tick
                and vim.deep_equal(vim.api.nvim_buf_get_lines(buf, first - 1, last, false), original) then
                local first_comment = comments[1]
                local marker = first_comment.marker
                local suffix = ""
                if marker:match("^/%*") then marker, suffix = "/* ", " */" end
                if marker:match("^<!") then marker, suffix = "<!-- ", " -->" end
                local replacement = first_comment.indent .. marker .. "TASK(" .. task.id .. "): " .. title .. suffix
                vim.api.nvim_buf_set_lines(buf, first - 1, last, false, { replacement })
            else
                vim.notify("TATR: source changed; original TODO left untouched", vim.log.levels.WARN)
            end
            vim.notify("TATR: created " .. task.id, vim.log.levels.INFO)
        end)
    end)
end

function M.setup(opts)
    opts = opts or {}
    if opts.keymap then
        vim.keymap.set("n", opts.keymap, M.list, { desc = "TATR: list tasks" })
    end
    if opts.comment_keymap then
        vim.keymap.set("n", opts.comment_keymap, M.from_comment, { desc = "TATR: task from TODO" })
        vim.keymap.set("x", opts.comment_keymap, function()
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
            vim.schedule(function() M.from_comment({ visual = true }) end)
        end, { desc = "TATR: task from selected comments" })
    end
end

return M
