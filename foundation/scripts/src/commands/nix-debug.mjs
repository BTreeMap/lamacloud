/*

  WARNING: This file is AI generated without any review. Use at your own's risk.

*/ 

import fs from 'fs'
import os from 'os'
import path from 'path'
import { file } from '../context.mjs'
import { x } from '../utils.mjs'

function nixString(value) {
  return JSON.stringify(value)
}

function hostConfig(host) {
  return file(`hosts/${host}/configuration.nix`)
}

function evalExpression(host) {
  return `
let
  root = ${nixString(file('.'))};
  flake = builtins.getFlake "path:\${root}";
  lamacloud = import (root + "/foundation/lamacloud.nix") {
    inherit (flake.inputs) nixpkgs disko;
  };
in
  (import (root + "/hosts/${host}/configuration.nix") { inherit lamacloud; }).config.system.build.toplevel
`
}

async function evalHost(host) {
  const config = hostConfig(host)

  if (!fs.existsSync(config)) {
    throw new Error(`Host configuration not found: ${config}`)
  }

  const temp = path.join(os.tmpdir(), `lamacloud-nix-debug-${process.pid}-${Date.now()}.nix`)

  try {
    fs.writeFileSync(temp, evalExpression(host))
    const result = await x`nix --extra-experimental-features 'nix-command flakes' eval --impure --show-trace --file '${temp}'`

    if (result.exitCode != 0) {
      process.stderr.write(result.stderr)
      process.exitCode = result.exitCode
      return
    }

    process.stdout.write(result.stdout)
  } finally {
    fs.rmSync(temp, { force: true })
  }
}

export function registerNixDebug(program) {
  const command = program.command('nix-debug')
    .description('Debug Nix host evaluation without flake outputs')

  command.command('eval')
    .description('Evaluate a host directly without flake output lookup')
    .argument('<host>', 'Host directory name')
    .action(async (host) => {
      await evalHost(host)
    })
}
