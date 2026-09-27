if vim.g.loaded_tatr_nvim then return end
vim.g.loaded_tatr_nvim = true
vim.api.nvim_create_user_command('Tatr', function() require('tatr').list() end, { desc = 'Browse TATR tasks' })
vim.api.nvim_create_user_command('TatrNew', function() require('tatr').new() end, { desc = 'Create TATR task' })
vim.api.nvim_create_user_command('TatrInit', function() require('tatr').init() end, { desc = 'Initialize TATR in current directory' })
