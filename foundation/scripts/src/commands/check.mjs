import fs from 'fs'
import path from 'path'
import { file, lamacloudDatabase, rootDir } from '../context.mjs'

function readJSONSafe(target) {
    try {
        return { ok: true, value: JSON.parse(fs.readFileSync(target, 'utf8')) }
    } catch (error) {
        return { ok: false, error: error.message }
    }
}

function listHostDirs() {
    const root = file('hosts')

    if (!fs.existsSync(root)) {
        return []
    }

    return fs.readdirSync(root, { withFileTypes: true })
        .filter((entry) => entry.isDirectory())
        .map((entry) => entry.name)
}

function checkHost(name, errors, warnings) {
    const hostDir = path.join(file('hosts'), name)
    const config = path.join(hostDir, 'configuration.nix')
    const creds = path.join(hostDir, 'creds.json')
    const partition = path.join(hostDir, 'partition.json')

    if (!fs.existsSync(config)) {
        errors.push(`hosts/${name}/configuration.nix is missing`)
        return
    }

    if (!fs.existsSync(creds)) {
        errors.push(`hosts/${name}/creds.json is missing (generate with 'lamacloud creds new ${name}')`)
    } else {
        const parsed = readJSONSafe(creds)

        if (!parsed.ok) {
            errors.push(`hosts/${name}/creds.json is not valid JSON: ${parsed.error}`)
        } else if (!parsed.value.elaina?.hashedPassword || !parsed.value.elaina?.publicKey?.keys?.length) {
            errors.push(`hosts/${name}/creds.json missing elaina.hashedPassword or elaina.publicKey.keys`)
        }
    }

    if (!fs.existsSync(partition)) {
        warnings.push(`hosts/${name}/partition.json is missing (host will skip disko configuration)`)
    } else {
        const parsed = readJSONSafe(partition)

        if (!parsed.ok) {
            errors.push(`hosts/${name}/partition.json is not valid JSON: ${parsed.error}`)
        }
    }
}

function checkSayo(errors) {
    const sayoPath = file('sayo.json')

    if (!fs.existsSync(sayoPath)) {
        errors.push("sayo.json is missing (generate with 'lamacloud creds new --sayo')")
        return
    }

    const parsed = readJSONSafe(sayoPath)

    if (!parsed.ok) {
        errors.push(`sayo.json is not valid JSON: ${parsed.error}`)
        return
    }

    if (!parsed.value.hashedPassword) {
        errors.push('sayo.json missing hashedPassword')
    }

    if (!parsed.value.publicKey?.keys?.length) {
        errors.push('sayo.json missing publicKey.keys')
    }
}

function checkDatabase(hostNames, warnings, errors) {
    const dbPath = file('lamacloud.json')

    if (!fs.existsSync(dbPath)) {
        warnings.push("lamacloud.json missing; deployments will fall back to hostname=name")
        return
    }

    const parsed = readJSONSafe(dbPath)

    if (!parsed.ok) {
        errors.push(`lamacloud.json is not valid JSON: ${parsed.error}`)
        return
    }

    const remotes = parsed.value.remotes || {}
    const hostSet = new Set(hostNames)

    for (const remoteName of Object.keys(remotes)) {
        if (!hostSet.has(remoteName)) {
            warnings.push(`lamacloud.json has remote '${remoteName}' with no matching hosts/${remoteName}/configuration.nix`)
        }

        const entry = remotes[remoteName]

        if (!entry.host) {
            errors.push(`lamacloud.json remote '${remoteName}' is missing 'host'`)
        }
    }
}

function summarize(errors, warnings) {
    console.log(`\n==> lamacloud check summary`)
    console.log(`[check] errors:   ${errors.length}`)
    console.log(`[check] warnings: ${warnings.length}`)

    for (const w of warnings) {
        console.log(`[WARN]  ${w}`)
    }

    for (const e of errors) {
        console.error(`[FAIL] check: ${e}`)
    }
}

export function registerCheck(program) {
    program.command('check')
        .description('Validate repository integrity (creds, partitions, lamacloud.json)')
        .option('--strict', 'Treat warnings as errors', false)
        .action(async (opts) => {
            const errors = []
            const warnings = []

            console.log(`==> Inspecting ${rootDir}`)
            checkSayo(errors)

            const hostNames = listHostDirs()
            console.log(`==> Discovered ${hostNames.length} host(s): ${hostNames.join(', ') || '<none>'}`)

            for (const name of hostNames) {
                checkHost(name, errors, warnings)
            }

            checkDatabase(hostNames, warnings, errors)
            summarize(errors, warnings)

            const failOnWarn = opts.strict && warnings.length > 0

            if (errors.length > 0 || failOnWarn) {
                process.exitCode = 1
                return
            }

            console.log('[check] OK')
        })
}
