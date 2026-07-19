# List available commands.
default:
    @just --list

# Bootstrap this Neovim configuration, then verify it.
setup: tools-install lsp-install plugins-install hooks-install check

# Run every check expected to pass before committing.
check: format-check test

# Format every Lua file.
format:
    @mise exec -- stylua .

# Verify that every Lua file is formatted without changing files.
format-check:
    @mise exec -- stylua --check .

# Run the complete test suite.
test:
    @nvim --headless --noplugin -u tests/init.lua -c "lua MiniTest.run()"

# Run one test file, for example: just test-file tests/test_nav.lua
test-file file:
    @nvim --headless --noplugin -u tests/init.lua -c "lua MiniTest.run_file('{{file}}')"

# Configure Git to use this repository's version-controlled hooks.
hooks-install:
    @git config core.hooksPath .githooks
    @echo "Git hooks installed. Commits will run: just check"

# Install the configuration-owned StyLua and LuaLS versions.
tools-install:
    @mise install

# Install Node-based language servers and formatters from tools/lsp.
lsp-install:
    @npm --prefix tools/lsp ci

# Install plugins at the revisions in nvim-pack-lock.json.
plugins-install:
    @config_home="$(mktemp -d)"; trap 'rm -rf "$config_home"' 0; ln -s "{{justfile_directory()}}" "$config_home/nvim"; XDG_CONFIG_HOME="$config_home" nvim --headless -u "$config_home/nvim/init.lua" -c "qa"

# Update Node-based language servers and formatters.
lsp-update:
    @npm --prefix tools/lsp update

# Print the directory containing the installed language-server binaries.
lsp-bin:
    @echo "{{justfile_directory()}}/tools/lsp/node_modules/.bin"

# Delete Neovim's local data and cache directories.
reset:
    @rm -rf $XDG_DATA_HOME/nvim
    @rm -rf $XDG_CACHE_HOME/nvim
