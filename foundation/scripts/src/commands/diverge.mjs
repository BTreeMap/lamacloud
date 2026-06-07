import fs from 'fs'
import path from 'path'
import prompts from 'prompts'
import { file } from '../context.mjs'
import { nixSystem, x } from '../utils.mjs'

async function promptHostConfig() {
  const { hostname } = await prompts({
    type: 'text',
    name: 'hostname',
    message: 'NixOS hostName',
  })

  if (!hostname) {
    throw new Error('NixOS hostName required')
  }

  const { arch } = await prompts({
    type: 'text',
    name: 'arch',
    message: 'Target architecture',
    initial: 'x86_64-linux',
    format: nixSystem,
  })

  if (!arch) {
    throw new Error('Target architecture required')
  }

  return { hostname, arch }
}

function renderTemplate(config) {
  return fs.readFileSync(file('foundation/scripts/template.nix'), 'utf8')
    .replaceAll('TEMPLATE_ARCH', config.arch)
    .replaceAll('TEMPLATE_HOSTNAME', config.hostname)
}

async function createHost(config) {
  const hostDir = file(`hosts/${config.hostname}`)
  const configPath = path.join(hostDir, 'configuration.nix')

  fs.mkdirSync(hostDir, { recursive: true })
  fs.writeFileSync(configPath, renderTemplate(config))

  const result = await x`git add '${configPath}'`

  if (result.exitCode != 0) {
    process.stderr.write(result.stderr)
    throw new Error('Failed to add new host configuration to git')
  }

  return configPath
}

export function registerDiverge(program) {
  program.command('diverge')
    .description('Create a new host configuration starting from the template')
    .action(async () => {
      const config = await promptHostConfig()
      const path = await createHost(config)
      
      console.log(`Wrote ${path}`)
    })
}
