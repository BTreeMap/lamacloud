import fs from 'fs'
import path from 'path'
import prompts from 'prompts'
import { parseSSHConnectionString } from './utils.mjs'

function lookupRootDir(search) {
  const resolved = path.resolve(search)

  if (resolved == "/") {
    throw new Error("Root project not found!")
  }

  const items = fs.readdirSync(search)

  if (items.includes("flake.nix")) {
    return path.resolve(search)
  }

  return lookupRootDir(path.resolve(search, ".."))
}

export const rootDir = lookupRootDir(".")

export function file(name) {
  return path.join(rootDir, name)
}

if (!fs.existsSync(file("lamacloud.json"))) {
  fs.writeFileSync(file("lamacloud.json"), JSON.stringify({ remotes: {} }))
}

export const lamacloudDatabase = JSON.parse(fs.readFileSync(file("lamacloud.json")))

export function saveDatabase() {
  fs.writeFileSync(file("lamacloud.json"), JSON.stringify(lamacloudDatabase))
}

export function hostFile(name, filename) {
  return file(`hosts/${name}/${filename}`)
}

export function managedRemote(remote) {
  const item = lamacloudDatabase.remotes?.[remote]

  if (!item) {
    const url = parseSSHConnectionString(remote)

    if (!url) {
      throw new Error(`Managed remote not found: ${remote}`)
    }

    return [url.username ? `${url.username}@${url.hostname}` : url.hostname, ...(url.port ? ["-p", url.port] : [])]
  }

  return [item.user ? `${item.user}@${item.host}` : item.host, ...(item.port ? ["-p", String(item.port)] : [])]
}

export async function resolveVmName(remote) {
  if (remote && lamacloudDatabase.remotes?.[remote]) {
    return remote
  }

  for (let current = path.resolve(process.cwd()); current.startsWith(rootDir); current = path.dirname(current)) {
    if (path.dirname(current) == current) {
      break
    }

    if (path.dirname(current) == file("hosts")) {
      return path.basename(current)
    }
  }

  const choices = fs.readdirSync(file("hosts"), { withFileTypes: true })
    .filter((item) => item.isDirectory())
    .map((item) => ({ title: item.name, value: item.name }))
  const { name } = await prompts({ type: "select", name: "name", message: "Select VM", choices })

  if (!name) {
    throw new Error("VM name required")
  }

  return name
}
