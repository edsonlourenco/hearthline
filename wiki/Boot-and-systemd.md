# Boot and systemd

The requirement that shaped Hearthline is simple: after the machine boots, MiniStack must already be listening. StackPort is started with it, because a console that comes up an hour later is not much of a lab.

## System units

The default install writes ordinary systemd units and enables them for `multi-user.target`. Each unit runs the engine in the foreground:

```text
ExecStart=/usr/bin/podman run --name hearthline-ministack --rm ...
```

There is no `-d`. systemd owns the process. If the process exits, `Restart=always` brings it back. `systemctl stop` still stops it for good, because a manual stop is not a failure.

`ExecStartPre` removes a leftover container name. `ExecStartPost` curls `/_ministack/health` and retries while the process is coming up. StackPort's unit `Requires=` MiniStack and also waits on that health URL before it starts, so the console does not cache a connection error from a cold boot.

Podman units set `Delegate=yes`, which is the cgroup setting Podman expects under systemd. Docker units leave the default.

This path does not need linger, a user session, or a login. That is the right boot behaviour for a server.

## Linger, and when it is not enough

`--user` writes the same units under `~/.config/systemd/user` and enables them for `default.target`. A user manager starts at graphical or SSH login. It does **not** start at boot unless linger is on:

```bash
sudo loginctl enable-linger "$USER"
```

Hearthline runs that command when it can. Without root it prints the command and continues. Until linger is enabled, a rootless lab stops when the last session of that user ends.

Linger is a good workstation option. It is a weaker server option: the lab is tied to one account, and a mistake in that user's units is harder to see from a recovery shell. Prefer `sudo ./install.sh` on a machine that should serve the whole network.

## Docker's daemon

Podman does not need a daemon, so enabling the MiniStack unit is enough. Docker does. When the selected runtime is Docker, the installer also enables `docker.service` or, if that unit is absent, `docker.socket`. The lab unit still runs `docker run` in the foreground, so a reboot starts the daemon first and the container second.

## What "enabled" looks like

```bash
systemctl is-enabled hearthline-ministack.service
systemctl is-active hearthline-ministack.service
hearthline status
```

`is-enabled` should print `enabled`. `hearthline status` should show the API as `ok` on the LAN address, not only on `127.0.0.1`.
