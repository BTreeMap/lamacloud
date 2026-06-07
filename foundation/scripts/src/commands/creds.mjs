import fs from 'fs'
import path from 'path'
import os from 'os'
import crypto from 'crypto'
import prompts from 'prompts'
import { file, hostFile, resolveVmName } from '../context.mjs'
import { clearInteractiveScreen, enterInteractiveMode, x } from '../utils.mjs'

function writeJSON(target, value) {
  fs.writeFileSync(target, `${JSON.stringify(value, null, 2)}\n`)
}

function readJSON(target) {
  return JSON.parse(fs.readFileSync(target, 'utf8'))
}

function authorizedKeys(publicKey) {
  return { keys: [publicKey] }
}

function publicKeyText(value) {
  if (typeof value == 'string') {
    return value
  }

  return value?.keys?.join('\n')
}

function commandOutput(result, command) {
  if (result.exitCode != 0) {
    throw new Error(`${command} failed: ${result.stderr.trim()}`)
  }

  return result.stdout.trim()
}

async function hashPassword(password) {
  return commandOutput(await x`printf '%s\n' '${password}' | openssl passwd -6 -stdin`, 'openssl passwd')
}

async function generateKeyPair(password, comment = '') {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'lamacloud-'))
  const privatePath = path.join(directory, 'key')
  const publicPath = `${privatePath}.pub`

  try {
    commandOutput(await x`ssh-keygen -q -t ed25519 -N '${password}' -f '${privatePath}' -C '${comment}'`, 'ssh-keygen')

    return {
      publicKey: fs.readFileSync(publicPath, 'utf8').trim(),
      privateKey: fs.readFileSync(privatePath, 'utf8').trim(),
    }
  } finally {
    fs.rmSync(directory, { recursive: true, force: true })
  }
}

async function generatePasswordCreds() {
  const password = crypto.randomUUID()

  return {
    password,
    hashedPassword: await hashPassword(password),
  }
}

async function generatePublicCreds(comment = '') {
  const password = crypto.randomUUID()

  return {
    ...(await generateKeyPair(password, comment)),
    keyPassword: password,
  }
}

export async function generateCreds(comment = '') {
  return {
    ...(await generatePublicCreds(comment)),
    ...(await generatePasswordCreds()),
  }
}

function nixUserCreds(creds) {
  return {
    hashedPassword: creds.hashedPassword,
    publicKey: authorizedKeys(creds.publicKey),
  }
}

function normalizeOptions(opts) {
  const passwordOnly = Boolean(opts.password)
  const publicOnly = Boolean(opts.public)

  return {
    sayoOnly: Boolean(opts.sayo),
    password: !passwordOnly && !publicOnly ? true : passwordOnly,
    public: !passwordOnly && !publicOnly ? true : publicOnly,
  }
}

async function promptConfirm(message, initial = false) {
  const { confirmed } = await prompts({
    type: 'confirm',
    name: 'confirmed',
    message,
    initial,
  })
  clearInteractiveScreen()

  return Boolean(confirmed)
}

async function promptReplace(target, label) {
  if (!fs.existsSync(target)) {
    return true
  }

  return promptConfirm(`${label} already exists. Replace it?`, false)
}

async function promptStorageChoices() {
  const { privateKeyStorage } = await prompts({
    type: 'select',
    name: 'privateKeyStorage',
    message: 'Where should elaina private key be stored?',
    choices: [
      { title: 'Save locally as elaina.key', value: 'local' },
      { title: 'Upload to 1Password', value: '1password' },
    ],
  })
  clearInteractiveScreen()

  if (!privateKeyStorage) {
    throw new Error('Private key storage choice required')
  }

  return privateKeyStorage
}

async function promptPasswordUpload(user) {
  return promptConfirm(`Upload ${user} cleartext password to 1Password?`, false)
}

function setPassword(creds, generated) {
  creds.hashedPassword = generated.hashedPassword
  return generated.password
}

function setPublicKey(creds, generated) {
  creds.publicKey = authorizedKeys(generated.publicKey)
}

function updateSayoJSON(existing, generated, options) {
  const result = existing || {}
  const output = { result }

  if (options.password) {
    output.password = setPassword(result, generated.password)
  }

  if (options.public) {
    setPublicKey(result, generated.public)
  }

  if (!result.control) {
    result.control = crypto.randomUUID()
  }

  return output
}

function updateHostJSON(existing, generated, options) {
  const result = existing || {}
  result.elaina ||= {}
  const output = { result }

  if (options.password) {
    output.password = setPassword(result.elaina, generated.password)
  }

  if (options.public) {
    setPublicKey(result.elaina, generated.public)
  }

  return output
}

function formatGeneratedSummary(items) {
  return items.flatMap((item) => [
    item.title,
    '',
    ...item.lines,
    '',
  ]).join('\n').trimEnd()
}

async function generateRequestedParts(comment, options) {
  return {
    password: options.password ? await generatePasswordCreds() : null,
    public: options.public ? await generatePublicCreds(comment) : null,
  }
}

async function generateSayo(options) {
  const output = file('sayo.json')
  const keyPath = file('sayo.key')
  const shouldWriteJSON = await promptReplace(output, 'sayo.json')

  if (!shouldWriteJSON) {
    return { title: 'sayo credentials skipped', lines: [`Kept existing ${output}`] }
  }

  const existing = fs.existsSync(output) ? readJSON(output) : null
  const generated = await generateRequestedParts('sayo', options)
  const updated = updateSayoJSON(existing, generated, options)
  const lines = [`sayo.json: ${output}`]

  writeJSON(output, updated.result)

  if (options.public) {
    fs.writeFileSync(keyPath, `${generated.public.privateKey}\n`, { mode: 0o600 })
    lines.push(`sayo private key: ${keyPath}`)
    lines.push('', 'sayo public key', generated.public.publicKey)
  }

  if (options.password) {
    const uploadPassword = await promptPasswordUpload('sayo')

    if (uploadPassword) {
      //todo 1p integration
    }

    lines.push('', 'sayo password', updated.password)
    lines.push(`sayo password 1Password upload: ${uploadPassword ? 'requested' : 'skipped'}`)
  }

  return { title: 'sayo credentials updated', lines }
}

async function ensureSayoCreds() {
  const output = file('sayo.json')

  if (fs.existsSync(output)) {
    return { output, created: false, creds: readJSON(output) }
  }

  const generated = await generateRequestedParts('sayo', { password: true, public: true })
  const updated = updateSayoJSON(null, generated, { password: true, public: true })

  writeJSON(output, updated.result)
  fs.writeFileSync(file('sayo.key'), `${generated.public.privateKey}\n`, { mode: 0o600 })

  return { output, created: true, creds: updated.result }
}

async function generateHost(host, options) {
  const name = await resolveVmName(host)
  const credsPath = hostFile(name, 'creds.json')
  const shouldWriteJSON = await promptReplace(credsPath, 'creds.json')

  if (!shouldWriteJSON) {
    return { title: `${name} credentials skipped`, lines: [`Kept existing ${credsPath}`] }
  }

  const existing = fs.existsSync(credsPath) ? readJSON(credsPath) : null
  const sayo = await ensureSayoCreds()
  const generated = await generateRequestedParts(`elaina@${name}`, options)
  const updated = updateHostJSON(existing, generated, options)
  const lines = [
    `creds.json: ${credsPath}`,
    `sayo credentials: ${sayo.output}${sayo.created ? ' (created)' : ' (already existed)'}`,
  ]

  writeJSON(credsPath, updated.result)

  if (options.public) {
    const privateKeyStorage = await promptStorageChoices()

    if (privateKeyStorage == 'local') {
      fs.writeFileSync(hostFile(name, 'elaina.key'), `${generated.public.privateKey}\n`, { mode: 0o600 })
    } else {
      //todo 1p integration
    }

    lines.push(`elaina private key: ${privateKeyStorage == 'local' ? hostFile(name, 'elaina.key') : '1Password upload requested'}`)
    lines.push('', 'elaina public key', generated.public.publicKey)
  }

  if (options.password) {
    const uploadPassword = await promptPasswordUpload('elaina')

    if (uploadPassword) {
      //todo 1p integration
    }

    lines.push('', 'elaina password', updated.password)
    lines.push(`elaina password 1Password upload: ${uploadPassword ? 'requested' : 'skipped'}`)
  }

  return { title: `Credentials updated for ${name}`, lines }
}

async function createCreds(host, opts) {
  return enterInteractiveMode(async () => {
    const options = normalizeOptions(opts)
    const result = options.sayoOnly
      ? await generateSayo(options)
      : await generateHost(host, options)

    return formatGeneratedSummary([result])
  })
}

async function showHostPublicKey(host) {
  const name = await resolveVmName(host)
  const credsPath = hostFile(name, 'creds.json')

  if (!fs.existsSync(credsPath)) {
    throw new Error(`Missing credentials for ${name}. Generate with 'lamacloud creds new ${name}'`)
  }

  const creds = readJSON(credsPath)
  const publicKey = publicKeyText(creds.elaina?.publicKey)

  if (!publicKey) {
    throw new Error(`No elaina public key found in ${credsPath}`)
  }

  return [`Public key for ${name}`, '', publicKey].join('\n')
}

export async function generateAllCreds(host) {
  const elaina = await generateCreds(host ? `elaina@${host}` : 'elaina')
  const sayo = await ensureSayoCreds()

  return {
    elaina: nixUserCreds(elaina),
    sayo,
  }
}

export function registerCreds(program) {
  const command = program.command('creds')
    .description('Manage host credentials')

  command.command('new')
    .description('Generate credentials for a host')
    .argument('[host]', 'Managed host name')
    .option('-s, --sayo', 'Generate sayo credentials only')
    .option('-p, --password', 'Regenerate password only')
    .option('-u, --public', 'Regenerate public key only')
    .action(async (host, opts) => {
      console.log(await createCreds(host, opts))
    })

  command.command('public')
    .description('Show host elaina public key')
    .argument('[host]', 'Managed host name')
    .action(async (host) => {
      console.log(await showHostPublicKey(host))
    })
}
