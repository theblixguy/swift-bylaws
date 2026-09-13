local repository_root = arg[1]
assert(repository_root, "The repository path is required")

local config = dofile(repository_root .. "/lsp/bylaws.lua")
assert(config.cmd[1] == "bylaws-lsp", "The client must start bylaws-lsp")
assert(config.filetypes[1] == "swift", "The client must attach to Swift files")
assert(config.root_markers[1] == "Bylaws.swift", "Bylaws.swift must be the first root marker")

local enabled_client
local enable = vim.lsp.enable
vim.lsp.enable = function(name)
  enabled_client = name
end
dofile(repository_root .. "/after/plugin/bylaws.lua")
vim.lsp.enable = enable
assert(enabled_client == "bylaws", "The client must be enabled when the plugin loads")
