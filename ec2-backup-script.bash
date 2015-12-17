#!/bin/bash
set -ueo pipefail
script_dir="$(cd "$(dirname "$0")"; pwd)"
cd "$script_dir"
/usr/local/bin/bundle exec ruby src/main.rb "$@"
