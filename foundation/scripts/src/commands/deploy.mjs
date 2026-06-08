import { lamacloudDatabase, resolveVmName, rootDir } from '../context.mjs'
import { x } from '../utils.mjs'

const GOALS = new Set(['switch', 'boot', 'test', 'dry-activate', 'build', 'push'])

async function ensureColmena() {
  const probe = await x`command -v colmena`

  if (probe.exitCode != 0) {
    throw new Error([
      "'colmena' binary not found in PATH.",
      "Install via 'nix profile install nixpkgs#colmena' or run inside",
      "'nix shell nixpkgs#colmena'.",
    ].join(' '))
  }
}

function logBanner(message) {
  console.log(`\n==> ${message}`)
}

function logInfo(message) {
  console.log(`[deploy] ${message}`)
}

function failWith(stage, reason) {
  console.error(`[FAIL] deploy/${stage}: ${reason}`)
  process.exitCode = 1
}

async function runColmena(args, env = {}) {
  logInfo(`colmena ${args.join(' ')}`)

  const result = await $({
    stdio: 'inherit',
    cwd: rootDir,
    env: { ...process.env, ...env },
  })`colmena ${args}`

  return result.exitCode ?? 0
}

function resolveSelector(opts, hostName) {
  if (opts.on) {
    return opts.on
  }

  if (hostName) {
    return hostName
  }

  return null
}

function validateGoal(goal) {
  if (!GOALS.has(goal)) {
    throw new Error(`Unknown deployment goal '${goal}'. Allowed: ${[...GOALS].join(', ')}`)
  }
}

function describeTarget(name) {
  const remote = lamacloudDatabase.remotes?.[name]

  if (!remote) {
    return `${name} (no entry in lamacloud.json; will fall back to hostname)`
  }

  const user = remote.user || 'sayo'
  const port = remote.port || 22

  return `${name} -> ${user}@${remote.host}:${port}`
}

export function registerDeploy(program) {
  program.command('deploy')
    .description('Deploy host(s) via Colmena (build + push + activate)')
    .argument('[host]', 'Managed host name (defaults to current directory or prompts)')
    .option('-g, --goal <goal>', `Activation goal: ${[...GOALS].join(' | ')}`, 'switch')
    .option('-o, --on <selector>', "Colmena --on selector (e.g. '@tag-a', 'host-*')")
    .option('--build-on-target', 'Build on the remote rather than the local machine', false)
    .option('--reboot', 'Reboot nodes after activation', false)
    .option('--show-trace', 'Pass --show-trace to nix evaluation', false)
    .option('--ssh-config <path>', 'Path to a ssh_config file', null)
    .action(async (host, opts) => {
      logBanner('Validating environment')
      validateGoal(opts.goal)
      await ensureColmena()

      const name = opts.on ? null : await resolveVmName(host)
      const selector = resolveSelector(opts, name)

      if (!selector) {
        return failWith('selector', 'No host or --on selector provided')
      }

      logBanner('Deployment plan')

      if (name) {
        logInfo(`Target host: ${describeTarget(name)}`)
      } else {
        logInfo(`Selector: ${selector}`)
      }

      logInfo(`Goal: ${opts.goal}`)
      logInfo(`Build-on-target: ${opts.buildOnTarget ? 'yes' : 'no'}`)
      logInfo(`Reboot after activation: ${opts.reboot ? 'yes' : 'no'}`)

      logBanner('Invoking Colmena')

      const args = ['apply', opts.goal, '--on', selector]

      if (opts.buildOnTarget) args.push('--build-on-target')
      if (opts.reboot) args.push('--reboot')
      if (opts.showTrace) args.push('--show-trace')

      const env = opts.sshConfig ? { SSH_CONFIG_FILE: opts.sshConfig } : {}
      const code = await runColmena(args, env)

      if (code != 0) {
        return failWith('colmena', `colmena exited with code ${code}`)
      }

      logBanner('Deployment complete')
    })

  program.command('hive-build')
    .description('Build the full Colmena hive without pushing or activating')
    .option('-o, --on <selector>', 'Restrict to selector')
    .option('--show-trace', 'Pass --show-trace to nix evaluation', false)
    .action(async (opts) => {
      logBanner('Validating environment')
      await ensureColmena()

      const args = ['build']

      if (opts.on) args.push('--on', opts.on)
      if (opts.showTrace) args.push('--show-trace')

      logBanner('Invoking Colmena build')
      const code = await runColmena(args)

      if (code != 0) {
        return failWith('colmena-build', `colmena build exited with code ${code}`)
      }

      logBanner('Hive build complete')
    })
}
