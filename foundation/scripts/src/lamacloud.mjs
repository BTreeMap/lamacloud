#!/usr/bin/env zx

import { program } from 'commander'
import './utils.mjs'
import { registerDeploy } from './commands/deploy.mjs'
import { registerDiverge } from './commands/diverge.mjs'
import { registerManage } from './commands/manage.mjs'
import { registerPartition } from './commands/partition.mjs'
import { registerProbe } from './commands/probe.mjs'
import { registerCreds } from './commands/creds.mjs'
import { registerNixDebug } from './commands/nix-debug.mjs'
import { registerBuild } from './commands/build.mjs'

program.name("lamacloud")
  .description("lamacloud host os management helper")
  .version("1.0")
  .action(async () => {
    program.help()
  })

registerManage(program)
registerPartition(program)
registerCreds(program)
registerDiverge(program)
registerDeploy(program)
registerProbe(program)
registerNixDebug(program)
registerBuild(program)

const argv = process.argv
const scriptIndex = argv.findLastIndex((arg) => /(^|\/)lamacloud(\.mjs)?$/.test(arg))

program.parse(argv.slice(scriptIndex + 1), { from: "user" })
