import fs from 'fs'
import path from 'path'
import crypto from 'crypto'
import { hostFile, managedRemote, resolveVmName } from '../context.mjs'
import { nixSystem, x } from '../utils.mjs'

export function registerProbe(program) {
  program.command("probe")
    .description("Probe the remote device and then generate remote.json")
    .argument("[remote]", "Managed name or ssh target")
    .action(async (remote) => {
      const name = await resolveVmName(remote)
      const output = hostFile(name, "remote.json")

      fs.mkdirSync(path.dirname(output), { recursive: true })
      
      const target = managedRemote(remote || name)
      
      const remoteOutput = `/tmp/lamacloud-${crypto.randomUUID()}.json`
      const system = nixSystem((await x`ssh ${target.join(" ")} uname -m`).stdout)
      console.log("Getting required packages from nixpkgs...")
      const facter = (await x`nix build nixpkgs#legacyPackages.${system}.nixos-facter --print-out-paths --no-link`).stdout.trim()
      const closure = (await x`nix-store -qR ${facter}`).stdout.trim().split("\n").join(" ")

      console.log(`Running nixos-factor on ${name}`)
      const result = await x`tar -C / -cf - ${closure.split(" ").map((item) => item.replace(/^\//, "")).join(" ")} | ssh ${target.join(" ")} 'tar -C / -xf - && ${facter}/bin/nixos-facter --output ${remoteOutput} && cat ${remoteOutput} && rm -f ${remoteOutput}'`
      
      const probe = JSON.parse(result.stdout)

      fs.writeFileSync(output, JSON.stringify({ ...probe, "target-arch": system }, null, 2))
    })
}
