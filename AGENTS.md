This repo is a fork of <https://github.com/datawranglerai/self-host-n8n-on-gcr> with my own modifications.

Always read these files at the start of conversation:

- terraform/main.tf
- terraform/variables.tf
- terraform/mise.toml
- terraform/.env
- MAINTENANCE.md
- COSTS.md
- Dockerfile
- startup.sh
- mise.toml

As coding agent, never run terraform's `apply` or `destroy`, pass it to the user

Always run `terraform fmt && terraform validate` after you reconfigure terraform.
