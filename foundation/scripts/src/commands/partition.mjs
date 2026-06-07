import fs from 'fs'
import prompts from 'prompts'
import { hostFile, resolveVmName } from '../context.mjs'
import { clearInteractiveScreen, enterInteractiveMode } from '../utils.mjs'

function sizeFromResources(resources = []) {
  const size = resources.find((item) => item.type == "size")

  if (!size) {
    return undefined
  }

  return Number(size.value_1) * Number(size.value_2)
}

function formatSize(bytes) {
  if (!bytes) {
    return "unknown"
  }

  const units = ["B", "K", "M", "G", "T", "P"]
  let value = bytes
  let unit = 0

  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024
    unit++
  }

  return `${Number(value.toFixed(value >= 10 ? 0 : 1))}${units[unit]}`
}

function deviceNames(disk) {
  return disk.unix_device_names.filter(Boolean)
}

function preferredDevice(disk) {
  const names = deviceNames(disk)
  const byId = names.find((name) => name.startsWith("/dev/disk/by-id/"))
  const dev = names.find((name) => /^\/dev\/[^/]+$/.test(name))

  if (byId) {
    return { device: byId, warning: null }
  }

  if (dev) {
    return { device: dev, warning: `Warning: ${dev} has no /dev/disk/by-id identifier` }
  }

  return { device: names[0], warning: `Warning: ${names[0]} has no /dev/disk/by-id or /dev/XXX identifier` }
}

function probeDisks(probe) {
  const disks = probe.hardware?.disk || [] 

  return disks.map((disk) => {
    const preferred = preferredDevice(disk)

    return {
      ...disk,
      sizeBytes: sizeFromResources(disk.resources) || disk.size,
      device: preferred.device,
      warning: preferred.warning,
      names: deviceNames(disk),
    }
  }).filter((disk) => disk.device)
}

function partitionSize(type, size) {
  if (size) {
    return size
  }

  return { "swap": "2G", "vfat": "512M" }[type] ?? "100%"
}

function partitionTitle(partition) {
  return `${partition.id} ${partition.type} ${partition.size} on ${partition.device}`
}

function partitionRoleLabel(partition, roles = {}) {
  const assigned = roles[partition.id]

  if (!assigned) {
    return ""
  }

  if (assigned.role == "mount") {
    return `, role: mount, mount: ${assigned.mount}${assigned.critical ? ", critical" : ""}`
  }

  return `, role: ${assigned.role}`
}

function renderState(disks, partitions, roles = {}) {
  const devices = disks.map((disk, index) => [
    `  ${index + 1}. ${disk.device}`,
    `     size: ${formatSize(disk.sizeBytes)}`,
    ...(disk.model ? [`     name: ${disk.model}`] : []),
    ...(disk.warning ? [`     warning: ${disk.warning}`] : []),
  ].join("\n")).join("\n")
  const grouped = partitions.reduce((result, partition) => {
    result[partition.device] = [...(result[partition.device] || []), partition]
    return result
  }, {})
  const partitionTree = Object.entries(grouped).map(([device, items]) => [
    `  ${device}`,
    ...items.map((partition, index) => `    ${index == items.length - 1 ? "└─" : "├─"} ${partition.id}: ${partition.type}, ${partition.size}${partitionRoleLabel(partition, roles)}`),
  ].join("\n")).join("\n")

  return [
    "Devices",
    devices || "  none",
    "",
    "Planned partitions",
    partitionTree || "  none",
  ].join("\n")
}

async function promptAction(disks, partitions) {
  const { action } = await prompts({
    type: "select",
    name: "action",
    message: `${renderState(disks, partitions)}\n\nPartition action`,
    choices: [
      { title: "Add partition", value: "add" },
      { title: "Delete partition", value: "delete", disabled: !partitions.length },
      { title: "Finish", value: "finish" },
    ],
  })

  clearInteractiveScreen()
  return action
}

async function promptDelete(disks, partitions) {
  const { index } = await prompts({
    type: "select",
    name: "index",
    message: `${renderState(disks, partitions)}\n\nDelete partition`,
    choices: [
      { title: "Back", value: "back" },
      ...partitions.map((partition, index) => ({ title: partitionTitle(partition), value: index })),
    ],
  })

  clearInteractiveScreen()

  if (index !== "back" && index !== undefined) {
    partitions.splice(index, 1)
  }
}

async function promptDisk(disks, partitions) {
  const { disk } = await prompts({
    type: "select",
    name: "disk",
    message: `${renderState(disks, partitions)}\n\nTarget physical device`,
    choices: [
      { title: "Back", value: "back" },
      ...disks.map((disk) => ({ title: `${disk.device} ${formatSize(disk.sizeBytes)} ${disk.model || ""}`.trim(), value: disk })),
    ],
  })

  clearInteractiveScreen()
  return disk
}

async function promptType(disks, partitions) {
  const { type } = await prompts({
    type: "select",
    name: "type",
    message: `${renderState(disks, partitions)}\n\nFilesystem/type`,
    choices: ["Back", "vfat", "ext4", "xfs", "btrfs", "swap", "raw"].map((type) => ({ title: type, value: type.toLowerCase() })),
  })

  clearInteractiveScreen()
  return type
}

async function promptSize(disks, partitions, type) {
  const initial = partitionSize(type)
  const { size } = await prompts({
    type: "text",
    name: "size",
    message: `${renderState(disks, partitions)}\n\nFilesystem/type: ${type}\nSize`,
    initial,
  })

  clearInteractiveScreen()
  return size === undefined ? "back" : partitionSize(type, size)
}

async function promptNewPartition(disks, partitions) {
  let disk
  let type

  while (true) {
    disk = await promptDisk(disks, partitions)

    if (disk == "back" || !disk) {
      return null
    }

    type = await promptType(disks, partitions)

    if (type == "back") {
      continue
    }

    if (!type) {
      return null
    }

    const size = await promptSize(disks, partitions, type)

    if (size == "back") {
      continue
    }

    return { disk, type, size }
  }
}

async function promptRule(disks, partitions) {
  const action = await promptAction(disks, partitions)

  if (action == "delete") {
    await promptDelete(disks, partitions)
    return true
  }

  if (action != "add") {
    return false
  }

  const response = await promptNewPartition(disks, partitions)

  if (!response) {
    return true
  }

  partitions.push({
    id: `p${partitions.length + 1}`,
    device: response.disk.device,
    type: response.type,
    size: response.size,
  })

  return true
}

function assignedRole(partition, roles) {
  return roles[partition.id]?.role
}

function roleTitle(partition, roles) {
  const assigned = assignedRole(partition, roles)

  return `${partitionTitle(partition)}${assigned ? ` [${assigned}]` : " [unassigned]"}`
}

function sortedRolePartitions(partitions, roles) {
  return partitions.toSorted((left, right) => {
    const leftAssigned = Boolean(assignedRole(left, roles))
    const rightAssigned = Boolean(assignedRole(right, roles))

    if (leftAssigned != rightAssigned) {
      return leftAssigned ? 1 : -1
    }

    return left.id.localeCompare(right.id)
  })
}

function roleIsUsed(role, roles, exceptId) {
  return Object.entries(roles).some(([id, item]) => id != exceptId && item.role == role)
}

function roleChoices(partition, roles) {
  return [
    { title: "Back", value: "back" },
    { title: "Clear role", value: null, disabled: !assignedRole(partition, roles) },
    ...(!roleIsUsed("rootfs", roles, partition.id) ? [{ title: "rootfs", value: "rootfs" }] : []),
    ...(!roleIsUsed("boot", roles, partition.id) ? [{ title: "boot", value: "boot" }] : []),
    { title: "mount", value: "mount" },
    { title: "swap", value: "swap" },
  ]
}

async function selectRolePartition(disks, partitions, roles) {
  const { id } = await prompts({
    type: "select",
    name: "id",
    message: `${renderState(disks, partitions, roles)}\n\nSelect partition to assign/change role`,
    choices: [
      { title: "Finish role assignment", value: "finish" },
      { title: "Back to partition editing", value: "back" },
      ...sortedRolePartitions(partitions, roles).map((partition) => ({ title: roleTitle(partition, roles), value: partition.id })),
    ],
  })

  clearInteractiveScreen()
  return id
}

async function selectRoleForPartition(disks, partitions, partition, roles) {
  const { role } = await prompts({
    type: "select",
    name: "role",
    message: `${renderState(disks, partitions, roles)}\n\nRole for ${roleTitle(partition, roles)}`,
    choices: roleChoices(partition, roles),
  })

  clearInteractiveScreen()
  return role
}

async function promptMountOptions(disks, partitions, partition, roles) {
  const { mount } = await prompts({
    type: "text",
    name: "mount",
    message: `${renderState(disks, partitions, roles)}\n\nMount path for ${partitionTitle(partition)}`,
    initial: rolesMountDefault(partition),
  })

  clearInteractiveScreen()

  if (!mount) {
    throw new Error("Mount path required")
  }

  const { critical } = await prompts({
    type: "confirm",
    name: "critical",
    message: "Critical mount? Fail boot if this mount fails?",
    initial: false,
  })

  clearInteractiveScreen()
  return { mount, critical: Boolean(critical) }
}

function rolesMountDefault(partition) {
  return partition.type == "swap" ? "/mnt/swap" : "/mnt/data"
}

function requiredRolesAssigned(roles) {
  return roleIsUsed("boot", roles) && roleIsUsed("rootfs", roles)
}

async function selectRoles(disks, partitions) {
  const roles = {}

  while (true) {
    const id = await selectRolePartition(disks, partitions, roles)

    if (id == "back") {
      return null
    }

    if (id == "finish") {
      if (requiredRolesAssigned(roles)) {
        return roles
      }

      await prompts({ type: "text", name: "missing", message: "Assign both boot and rootfs before finishing. Press enter to continue", initial: "" })
      clearInteractiveScreen()
      continue
    }

    if (!id) {
      continue
    }

    const partition = partitions.find((partition) => partition.id == id)
    const role = await selectRoleForPartition(disks, partitions, partition, roles)

    if (role == "back") {
      continue
    }

    if (!role) {
      delete roles[id]
      continue
    }

    roles[id] = role == "mount"
      ? { role, ...(await promptMountOptions(disks, partitions, partition, roles)) }
      : { role }
  }
}

function summary(partitions, roles) {
  return partitions.reduce((result, partition) => {
    const assigned = roles[partition.id]
    const item = Object.fromEntries(Object.entries({
      type: partition.type,
      size: partition.size,
      role: assigned?.role,
      mount: assigned?.role == "mount" ? assigned.mount : undefined,
      critical: assigned?.role == "mount" ? assigned.critical : undefined,
    }).filter(([, value]) => value !== undefined))

    result[partition.device] ||= {}
    result[partition.device][partition.id] = item

    return result
  }, {})
}

export function registerPartition(program) {
  program.command("partition")
    .description("Manage remote machine partition configuration")
    .argument("[remote]", "Managed name")
    .argument("[device]", "Device identifier (UUID or path)")
    .action(async (remote, device, opts) => {
      const result = await enterInteractiveMode(async () => {
        const name = await resolveVmName(remote)
        const probe = JSON.parse(fs.readFileSync(hostFile(name, "remote.json"), "utf8"))
        const disks = probeDisks(probe).filter((disk) => !device || disk.device == device || disk.names.includes(device))
        const partitions = []

        if (!disks.length) {
          throw new Error("No matching disks found in remote.json")
        }

        while (true) {
          while (await promptRule(disks, partitions)) {}

          if (!partitions.length) {
            return { aborted: true, message: "No partitions planned. Aborted without writing partition.json." }
          }

          const roles = await selectRoles(disks, partitions)

          if (roles) {
            const output = hostFile(name, "partition.json")

            fs.writeFileSync(output, JSON.stringify(summary(partitions, roles), null, 2))
            return { output }
          }
        }
      })

      console.log(result.aborted ? result.message : `Wrote ${result.output}`)
    })
}
