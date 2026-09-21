#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
nvim --headless -u NONE -i NONE -S tests/headless/util_spec.lua -c 'qa'
nvim --headless -u NONE -i NONE -S tests/headless/parser_spec.lua -c 'qa'
nvim --headless -u NONE -i NONE -S tests/headless/surround_spec.lua -c 'qa'
nvim --headless -u NONE -i NONE -S tests/headless/smart_spec.lua -c 'qa'
nvim --headless -u NONE -i NONE -S tests/headless/compile_spec.lua -c 'qa'
nvim --headless -u NONE -i NONE -S tests/headless/compile_real_spec.lua -c 'qa'
