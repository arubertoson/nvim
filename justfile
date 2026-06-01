
# Nuke this as a reset
# $XDG_DATA_HOME/nvim/site/pack

test:
    nvim --headless --noplugin -u tests/init.lua -c "lua MiniTest.run()"

test-file file:
    nvim --headless --noplugin -u tests/init.lua -c "lua MiniTest.run_file('{{file}}')"

test-jump:
    nvim --headless --noplugin -u tests/init.lua -c "lua MiniTest.run_file('tests/test_jump.lua')"
