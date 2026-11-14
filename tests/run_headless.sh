#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
XDG_STATE_HOME="${XDG_STATE_HOME:-/tmp/nvimtex-headless-state}"
export XDG_STATE_HOME
nvim --headless -u NONE -i NONE -l tests/headless/util_spec.lua
sh tests/run_conceal.sh
nvim --headless -u NONE -i NONE -l tests/headless/textobject_spec.lua
nvim --headless -u NONE -i NONE -l tests/headless/textobject_integrations_spec.lua
nvim --headless -u NONE -i NONE -l tests/headless/textobject_keys_spec.lua
nvim --headless -u NONE -i NONE -l tests/headless/markdown_conditions_spec.lua
nvim --headless -u NONE -i NONE -l tests/headless/surround_spec.lua
nvim --headless -u NONE -i NONE -l tests/headless/smart_spec.lua
nvim --headless -u NONE -i NONE -l tests/headless/compile_spec.lua
nvim --headless -u NONE -i NONE -l tests/headless/compile_real_spec.lua
