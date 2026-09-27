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

function M.new()
    -- TATR owns creation and its interactive flags; open a real terminal for its CLI.
    local project = root() or vim.fn.getcwd()
    vim.cmd('botright 12split')
    vim.fn.termopen({ 'tatr', 'new' }, { cwd = project, on_exit = function(_, code)
        vim.schedule(function()
            if code == 0 then vim.notify('TATR: task created. Run :Tatr to view.', vim.log.levels.INFO) end
        end)
    end })
    vim.cmd('startinsert')
end

function M.setup(opts)
    opts = opts or {}
    if opts.keymap then
        vim.keymap.set('n', opts.keymap, M.list, { desc = 'TATR: list tasks' })
    end
end

return M
