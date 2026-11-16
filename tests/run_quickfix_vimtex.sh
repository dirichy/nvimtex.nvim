#!/usr/bin/env sh
set -eu
cd "$(dirname "$0")/.."
NVIMTEX_PATH="$PWD"
VIMTEX_PATH="${VIMTEX_PATH:-$PWD/.dev/vimtex}"
XDG_STATE_HOME="${XDG_STATE_HOME:-/tmp/nvimtex-headless-state}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-/tmp/nvimtex-quickfix-cache}"
INMAKE=1
export NVIMTEX_PATH VIMTEX_PATH XDG_STATE_HOME XDG_CACHE_HOME INMAKE
for test in test-latexlog test-spaces test-beamer test-hbox; do
  case "$test" in
    test-beamer|test-hbox) QF_TEST_DIR=test-quickfix-fix-path ;;
    *) QF_TEST_DIR=test-quickfix ;;
  esac
  QF_TEST="$test.vim"
  export QF_TEST_DIR QF_TEST
  nvim --headless -u NONE -i NONE -l tests/headless/quickfix_vimtex_spec.lua
  echo "ok upstream $test"
done
