# Copilot Instructions

The project instructions for AI assistants live in [`CLAUDE.md`](../CLAUDE.md) at the repo
root — read and follow it. It covers the repo layout, validation commands, deployment rules
(merging to `main` deploys to the live cluster; one new app per push), the Helm values
workflow, placement constraints, script conventions, and which doc owns which topic.

Hard rules, repeated here in case nothing else is read:

- `/boot/firmware/cmdline.txt` must stay a **single line**.
- Always `clusterctrl off` before rebooting or unplugging the Pi 4.
- Ordered build steps live only in `bootstrap/docs/rebuild.md`.
- Run `./local_ci.sh` before committing.
