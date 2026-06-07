#!/usr/bin/env bash

if [ -z "${BASH_SOURCE:-}" ] || [ "${BASH_SOURCE[0]}" = "$0" ]; then
  echo "Error: setup.sh must be loaded with source."
  echo "Run: source setup.sh"
  exit 1
fi

source_path="${BASH_SOURCE[0]}"

checkBinary() {
  local binary="$1"

  if ! command -v "$binary" >/dev/null 2>&1; then
    echo "Error: missing required binary: $binary" >&2
    return 1
  fi

  return 0
}

missing_binaries=0
declare -a checks=(openssl ssh nix git node)
for binary in "${checks[@]}"; do
  checkBinary "$binary" || missing_binaries=1
done

if [ "$missing_binaries" -ne 0 ]; then
  echo "Install the missing binaries and run: source setup.sh" >&2
  return 1
fi

export PATH="$PATH:$(realpath "$(dirname -- "$source_path")")/foundation/scripts"
unset source_path missing_binaries binary

echo "   __                   _______             __";
echo "  / /  ___ ___ _  ___ _/ ___/ /__  __ _____/ /";
echo " / /__/ _ \`/  ' \\/ _ \`/ /__/ / _ \\/ // / _  / ";
echo "/____/\\_,_/_/_/_/\\_,_/\\___/_/\\___/\\_,_/\\_,_/  ";
echo ""
echo " Type 'lamacloud --help' for help"

