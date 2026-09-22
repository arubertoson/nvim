---@module "aru.config"
---Shared static configuration consumed by multiple features.

local M = {}

M.keys = {
    leader = ";",
    local_leader = ",",
}

M.navigation = {
    active_file_keys = { "j", "k", "l" },
}

M.ui = {
    border = "rounded",
    picker = {
        height_ratio = 0.7,
        max_width = 75,
        width_ratio = 0.8,
    },
    theme = {
        family = "kanagawa",
        variant = "dragon",
    },
}

M.icons = {
    diagnostic = {
        error = "󰅚 ",
        warn = "󰀪 ",
        hint = "󰌶 ",
        info = "󰋽 ",
    },
    kind = {
        Array = "",
        Boolean = "",
        Class = "",
        Color = "",
        Constant = "",
        Constructor = "",
        Enum = "",
        EnumMember = "",
        Event = "",
        Field = "",
        File = "",
        Folder = "",
        Function = "",
        Interface = "",
        Key = "",
        Keyword = "",
        Method = "",
        Module = "",
        Namespace = "",
        Null = "",
        Number = "",
        Object = "",
        Operator = "",
        Package = "",
        Property = "",
        Reference = "",
        Snippet = "",
        String = "",
        Struct = "",
        Text = "",
        TypeParameter = "",
        Unit = "",
        Value = "",
        Variable = "",
    },
}

return M
