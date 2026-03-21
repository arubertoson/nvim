local log = require("aru.log")

local harpoon = require("harpoon")

-- We are setting a custom key to ensure that each harpoon list is unique across
-- git branches as well as projects. This gives us the flexibility to jave
-- multiple harpoon lists per project.
harpoon:setup({
    settings = {
        -- TODO: This method needs to be more robust. We've got the find root thing, let's use
        -- it to create a better key. cwd will be replaced by root, and branch...
        key = function()
            local cwd = vim.uv.cwd()
            local branch = vim.fn
                .system("git rev-parse --abbrev-ref HEAD 2> /dev/null")
                :gsub("\n", "")
            if branch == "" then
                return cwd or "" -- fallback
            end

            return cwd .. ":" .. branch
        end,
        save_on_toggle = true,
        sync_on_ui_close = true,
    },
})

local function refresh_harpoon_state()
    vim.api.nvim_exec_autocmds(
        "User",
        { pattern = "HarpoonStateUpdated", data = nil, modeline = false }
    )
end

-- We extend harpoon with some custom functionality, mainly to redraw the statusline
-- on updates, as we have our custom widget there.
harpoon:extend({
    ADD = refresh_harpoon_state,
    SELECT = refresh_harpoon_state,
    REORDER = refresh_harpoon_state,
    LIST_CHANGE = refresh_harpoon_state,
    -- On remove we also delete the buffer from the session, the session should always
    -- be lean and focused on what matters. A huge buffer list is a curse that needs to
    -- be cleansed.
    REMOVE = function(list_item)
        log:debug(("removing %s"):format(vim.inspect(list_item)))
        local buf = vim.api.nvim_get_current_buf()
        if vim.api.nvim_buf_is_loaded(buf) then
            vim.api.nvim_buf_delete(buf, { force = true })
        end

        refresh_harpoon_state()
    end,
})

local group = vim.api.nvim_create_augroup("harpoon", { clear = true })

-- Vim Schedule is a weak solution, currently this is in place to prevent a
-- crash in the harpoon plugin. Autocmds are executed in order and a second
-- solution could be to add this autocmd to the harpoon plugin config.
vim.api.nvim_create_autocmd({ "BufHidden" }, {
    desc = "Delete any buffers that are not in the harpoon list.",
    group = group,
    pattern = { "*" },
    callback = function(ev)
        vim.schedule(function()
            local ok, harpoon = pcall(require, "harpoon")
            if not ok then
                log:debug(
                    "harpoon is not avialable, defaulting to no buf cleanup."
                )
                return
            end

            if not vim.api.nvim_buf_is_valid(ev.buf) then
                log:debug(
                    "Trying to remove an invalid buffer, buffer already deleted?"
                )
                return
            end

            -- this should be added to the harpoon check to protect against
            -- buffers that have been deleted.
            local buf_name = vim.api.nvim_buf_get_name(ev.buf)
            if buf_name == "" then
                log:debug("Unnamed buffer; checking protection only.")
            else
                local root = vim.uv.cwd() or ""
                local rel_path = vim.fs.relpath(root, buf_name)

                local item, _ = harpoon:list():get_by_value(rel_path)
                if item then
                    log:debug(
                        "Buffer "
                            .. buf_name
                            .. " is not elegible for deletion, skipping"
                    )
                    return
                end
            end

            local ok, protected =
                pcall(vim.api.nvim_buf_get_var, ev.buf, "__bufdel_protected")
            if ok and protected then
                log:debug(
                    "Buffer "
                        .. buf_name
                        .. " is protected through __bufdel_protected, skipping"
                )
                return
            end

            log:debug(
                "Deleting buffer " .. buf_name .. ", not in harpoon list."
            )
            vim.api.nvim_buf_delete(ev.buf, { force = false })
        end)
    end,
})

-- Delay the draw of the HarpoonStateUpdated event, otherwise the statusline won't
-- update until the first buffer switch. Harpoon can give useful information on the
-- first screen though.
-- XXX: Might remove this when we get sessions going.

vim.api.nvim_exec_autocmds(
    "User",
    { modeline = false, pattern = "HarpoonStateUpdated" }
)
