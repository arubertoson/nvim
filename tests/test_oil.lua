pcall(vim.cmd, "packadd mini.nvim")
pcall(vim.cmd, "packadd oil.nvim")

local MiniTest = _G.MiniTest or require("mini.test")
if not _G.MiniTest then MiniTest.setup({ silent = true }) end

local T = MiniTest.new_set({
    hooks = {
        post_case = function() vim.cmd("silent! %bwipeout!") end,
    },
})

local function git(args, cwd)
    local result = vim.system(vim.list_extend({ "git" }, args), { cwd = cwd, text = true }):wait()
    if result.code ~= 0 then error(result.stderr) end
end

T["Oil asynchronously hides Git-ignored entries"] = function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    git({ "init", "-q" }, root)
    vim.fn.writefile({ "ignored.txt" }, vim.fs.joinpath(root, ".gitignore"))
    vim.fn.writefile({}, vim.fs.joinpath(root, "ignored.txt"))
    vim.fn.writefile({}, vim.fs.joinpath(root, "visible.txt"))

    require("aru.workspace.files").setup()
    require("oil").open(root)

    local hidden = vim.wait(3000, function()
        local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
        return text:find("visible.txt", 1, true) ~= nil
            and text:find("ignored.txt", 1, true) == nil
    end, 20)

    MiniTest.expect.equality(hidden, true)
end

return T
