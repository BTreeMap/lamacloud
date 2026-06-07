import 'zx/globals'

$.nothrow = true

export function x(strings, ...values) {
  let rawCommand = strings[0]

  for (let index = 0; index < values.length; index++) {
    rawCommand += values[index] + strings[index + 1]
  }

  return $({ stdio: "pipe" })([rawCommand])
}

export function clearInteractiveScreen() {
  if (process.stdout.isTTY) {
    process.stdout.write("\x1b[2J\x1b[H")
  }
}

export async function enterInteractiveMode(callback) {
  if (!process.stdin.isTTY || !process.stdout.isTTY) {
    return callback()
  }

  process.stdout.write("\x1b[?1049h")
  clearInteractiveScreen()

  try {
    return await callback()
  } finally {
    process.stdout.write("\x1b[?1049l")
  }
}

export function parseSSHConnectionString(str) {
  return URL.parse(`ssh://${str.replace(/^[a-zA-Z]+:\/\//g, '')}`)
}


export function nixSystem(arch) {
  return ({ x86_64: "x86_64-linux", aarch64: "aarch64-linux", arm64: "aarch64-linux" })[arch.trim()] || `${arch.trim()}-linux`
}
