# lamacloud-infra

The new infrastructure for LamaCloud based on NixOS.

[![996.icu](https://img.shields.io/badge/link-996.icu-red.svg)](https://996.icu)
[![LICENSE](https://img.shields.io/badge/license-Anti%20996-blue.svg)](https://github.com/996icu/996.ICU/blob/master/LICENSE)

---


This repository is only intended to collaborate with server users
because this project has used many wrapper functions that are not well documented.
It may not be a good source to learn about NixOS. 
However, you are welcome to use wrappers and scripts in this project.
Technical questions regarding project details can be discussed in Issues area.

## LamaCloud Users Guideline

To customize a remote server, please submit a pull-request.
You do not need to explain your changes in details, as they will be discussed in chat group.
You must not change anything outside host's corresponding data folder.
You must not change `creds.json`, `partition.json`, `lamacloud.json`, and `sayo.json` without prior notice to the owner, lamadaemon, in chat group.
If you found a bug or want to improve current code base, you are welcome to do so, and 
in this case, you are allowed to have changes to all files in this repository.
However, you must not mix your personal changes with the codebase changes. (E.g. adding a new package to a server while giving an update to setup.sh)

Automation will be configured later, and all PRs must pass at least build check before they get merged into master,
as in the future, master will be synced to production environment periodically.


## Usage

### File Structure

- `foundation` - The foundation of this project, including default configs, scripts, and server templates.
- `sayo.json` - The credentials for CI server to do system upgrade.
- `lamacloud.json` - Server ssh connection information
- `packages` - Custom packages, including proprietary softwares wrappers.
- `hosts` - All LamaCloud managed hosts goes here.

### Setup
To setup required environment, execute the following command

```
$ source setup.sh
```

### Building a server locally

```
$ lamacloud build <name>
```

### Add a new server

First create a new server from template

```
$ lamacloud diverge
```

Then, add ssh connection string

```
$ lamacloud manage <name> <URL>
```

URL does not need to start with `ssh://`
