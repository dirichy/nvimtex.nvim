#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
XDG_STATE_HOME="${XDG_STATE_HOME:-/tmp/nvimtex-headless-state}"
export XDG_STATE_HOME

# -l propagates Lua assertion failures to the shell exit status.
for spec in parser parser_nodes render_tree renderer command_program conceal conceal_incremental renderer_entry conceal_commands conceal_lifecycle; do
	nvim --headless -u NONE -i NONE -l "tests/headless/${spec}_spec.lua"
done
