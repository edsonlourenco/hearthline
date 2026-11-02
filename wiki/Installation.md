# Installation

Hearthline supports two families:

- Fedora, and the close RHEL clones that use `dnf` and firewalld
- Ubuntu and Debian, including hosts that use UFW

The engine is Podman when `podman` is on `PATH`. Docker is used when Podman is absent, or when you pass `--runtime docker`. If neither engine exists, a root install adds the distro's Podman package. Docker is never installed for you, because the package name and the daemon setup differ too much between Fedora and Ubuntu.

## First run

```bash
git clone https://github.com/edsonlourenco/hearthline.git
cd hearthline
./install.sh --print-plan
sudo ./install.sh
```

`--print-plan` only reads the host. It is safe to run as your own user. The real install needs root so it can write `/etc/systemd/system` and enable the units for boot.

When the script finishes it prints two URLs. From another computer on the same subnet, open the StackPort URL and run:

```bash
aws --endpoint-url http://<lan-address>:4566 s3 ls
```

Use the key `test` and the secret `test` if you have not created a profile yet. The server-side profile is documented in [AWS CLI](AWS-CLI).

## Flags worth knowing

`--lan-ip` and `--subnet` override detection. Detection uses the source address of the default IPv4 route and the prefix on that interface. A `/24` is computed in the shell. Any other prefix length uses `python3`.

`--user` installs rootless units into your systemd user instance and data under `~/.local/share/hearthline`. That mode is useful on a workstation. On a server, prefer the default system install: it does not depend on someone logging in.

`--skip-stackport` leaves you with the API only. `--skip-firewall` is the right choice when the packet filter is managed somewhere else. `--real-infra` mounts the engine socket into MiniStack. Read the caveat in [Operations](Operations) before you enable it.

## What is written

| Path | Purpose |
| --- | --- |
| `/etc/systemd/system/hearthline-ministack.service` | MiniStack unit |
| `/etc/systemd/system/hearthline-stackport.service` | StackPort unit |
| `/etc/hearthline/hearthline.env` | Values the `hearthline` command reads |
| `/etc/hearthline/env.sh` | File you can `source` |
| `/etc/hearthline/firewall.rules` | Rules uninstall knows how to remove |
| `/var/lib/hearthline/` | Persistent state |
| `/usr/local/bin/hearthline` | Status, logs, restart |

A second run rewrites the units and restarts the services. It does not empty the data directory.

## Taking over an older manual lab

If a user-level container named `ministack` or `stackport` is already running, the system install stops it, moves a matching Quadlet file to `*.disabled-by-hearthline`, and copies `~/ministack/data` into `/var/lib/hearthline` when the new directories are empty. The copy happens after a graceful stop, so MiniStack can flush `PERSIST_STATE` to disk first.

Run the install from the account that owns that older lab, via `sudo`, so `SUDO_USER` points at the right home directory.
