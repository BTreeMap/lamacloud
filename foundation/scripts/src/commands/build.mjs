import fs from 'fs'
import { file, resolveVmName, rootDir } from '../context.mjs'
import { x } from '../utils.mjs'

export function registerBuild(program) {
  program.command('build')
    .description('Build a host NixOS system')
    .argument('[host]', 'Host directory name')
    .action(async (host) => {
      const name = host || await resolveVmName()

      if (!fs.existsSync(file(`hosts/${name}/configuration.nix`))) {
        throw new Error(`Host configuration not found: ${name}`)
      }

      const result = await x`nixos-rebuild build --flake 'path:${rootDir}#${name}'`

      if (result.exitCode != 0) {
        process.stderr.write(result.stderr)
        process.exitCode = result.exitCode
        return
      }

      process.stdout.write(result.stdout)
    })
}
