
# Nuke this as a reset
# $XDG_DATA_HOME/nvim/site/pack

test:
    nvim --headless --noplugin -u tests/init.lua -c "lua MiniTest.run()"

test-file file:
    nvim --headless --noplugin -u tests/init.lua -c "lua MiniTest.run_file('{{file}}')"

lsp-install:
    npm --prefix tools/lsp ci

lsp-update:
    npm --prefix tools/lsp update

lsp-bin:
    @echo "{{justfile_directory()}}/tools/lsp/node_modules/.bin"

test-jump:
    nvim --headless --noplugin -u tests/init.lua -c "lua MiniTest.run_file('tests/test_jump.lua')"
