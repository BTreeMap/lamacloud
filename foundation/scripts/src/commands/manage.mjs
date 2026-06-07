import { lamacloudDatabase, saveDatabase } from '../context.mjs'
import { parseSSHConnectionString, x } from '../utils.mjs'

export function registerManage(program) {
  program.command("manage")
    .description("Put a remote machine into management")
    .argument("<name>", "The name of the remote machine, must matching the name used in hosts folder")
    .argument("<remote>", "The remote connection string")
    .argument("[description]", "The description of the remote machine")
    .action(async (name, remote, desc, opts) => {
      const url = parseSSHConnectionString(remote)

      if (!url) {
        throw new Error("Failed to parse given url string! User@DomainOrIP:Port")
      }

      const conn = await x`ssh ${url.hostname} ${url.port ? "-p " + url.port : ""} ${url.username ? "-l " + url.username : ""} exit`

      if (conn.exitCode != 0) {
        console.log(`ssh ${url.hostname} ${url.port ? "-p " + url.port : ""} ${url.username ? "-l " + url.username : ""} exit`)
        return console.log(`Failed to connect to remote ${url.toString()}`)
      }

      lamacloudDatabase.remotes[name] = {
        host: url.hostname,
        port: url.port,
        user: url.username,
        description: desc,
      }

      console.log(`Added ${name} into database`)
      saveDatabase()
    })
}
