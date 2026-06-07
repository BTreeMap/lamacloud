export function registerDeploy(program) {
  program.command("deploy")
    .description("Deploy remote machine")
    .argument("[remote]", "Managed name")
    .option("-i, --init", "Initial deployment")
    .action(async (opts) => {})
}
