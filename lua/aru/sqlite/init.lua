---@module "aru.sqlite"
---Public commands and mappings for the SQLite scratchpad.

local scope = require("aru.sqlite.scope")
local session = require("aru.sqlite.session")

local M = {}

---@param db_path string
---@return boolean
local function confirm_replacement(db_path)
    local active = session.current()
    if not active or not vim.api.nvim_buf_is_valid(active.query_buf) then return true end

    local lines = vim.api.nvim_buf_get_lines(active.query_buf, 0, -1, false)
    if not table.concat(lines, "\n"):find("%S") then return true end

    local choice = vim.fn.confirm(
        ("Discard the active query draft and open %s?"):format(db_path),
        "&Cancel\n&Discard and open",
        1,
        "Warning"
    )
    return choice == 2
end

local function open(path)
    if vim.fn.executable("sqlite3") ~= 1 then
        vim.notify("SQLiteOpen requires the sqlite3 executable", vim.log.levels.ERROR)
        return
    end

    local expanded = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
    local db_path = vim.fs.normalize(expanded)
    if not confirm_replacement(db_path) then return end

    local query_buf = session.open(db_path)
    local options = { buffer = query_buf, silent = true }

    vim.keymap.set(
        "n",
        "<leader>rr",
        function() session.execute(scope.buffer(query_buf)) end,
        vim.tbl_extend("force", options, {
            desc = "Execute SQLite buffer",
        })
    )
    vim.keymap.set(
        "x",
        "<leader>rr",
        function()
            session.execute(scope.region(vim.fn.getpos("v"), vim.fn.getpos("."), vim.fn.mode()))
        end,
        vim.tbl_extend("force", options, {
            desc = "Execute SQLite selection",
        })
    )
    vim.keymap.set(
        "n",
        "<leader>rl",
        function()
            local line = vim.api.nvim_win_get_cursor(0)[1]
            session.execute(scope.line(query_buf, line))
        end,
        vim.tbl_extend("force", options, {
            desc = "Execute SQLite line",
        })
    )
    vim.keymap.set(
        "n",
        "[r",
        function() session.navigate(-1) end,
        vim.tbl_extend("force", options, {
            desc = "Previous SQLite result",
        })
    )
    vim.keymap.set(
        "n",
        "]r",
        function() session.navigate(1) end,
        vim.tbl_extend("force", options, {
            desc = "Next SQLite result",
        })
    )
    vim.keymap.set(
        "n",
        "<leader>rd",
        session.delete_current,
        vim.tbl_extend("force", options, {
            desc = "Delete current SQLite result",
        })
    )
    vim.keymap.set(
        "n",
        "<leader>rs",
        session.toggle_sql_preview,
        vim.tbl_extend("force", options, {
            desc = "Toggle SQLite execution SQL",
        })
    )
end

function M.setup()
    vim.api.nvim_create_user_command("SQLiteOpen", function(command) open(command.args) end, {
        nargs = 1,
        complete = "file",
        desc = "Open a SQLite scratchpad",
        force = true,
    })
    vim.api.nvim_create_user_command("SQLiteClose", session.close, {
        desc = "Close the SQLite scratchpad",
        force = true,
    })
    vim.api.nvim_create_user_command("SQLiteExport", function(command)
        local expanded = vim.fn.fnamemodify(vim.fn.expand(command.args), ":p")
        session.export(vim.fs.normalize(expanded), command.bang)
    end, {
        nargs = 1,
        bang = true,
        complete = "file",
        desc = "Rerun the selected SQLite result and export it as CSV",
        force = true,
    })
end

return M
