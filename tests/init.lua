vim.cmd([[let &runtimepath.=','.getcwd()]])
pcall(vim.cmd, "packadd mini.nvim")

vim.g.aru_test = true

if #vim.api.nvim_list_uis() == 0 then
    require("mini.test").setup()
end
