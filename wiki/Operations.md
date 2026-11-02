# Operations

## Daily commands

```bash
hearthline status
hearthline endpoint
hearthline logs
hearthline restart
hearthline stop
hearthline start
```

`status` prints the engine, the boot method, the systemd active state, and a live probe of the LAN URLs. `logs` follows the journal for both units. On a system install that command may ask for sudo, because the system journal is not always readable by a normal user.

`hearthline env` prints the path of the shell file, usually `/etc/hearthline/env.sh`.

## Persistence

MiniStack keeps two layers, and Hearthline turns both on:

| Variable | Container path | Host path |
| --- | --- | --- |
| `PERSIST_STATE=1` | `/tmp/ministack-state` | `/var/lib/hearthline/ministack/state` |
| `S3_PERSIST=1` | `/tmp/ministack-data/s3` | `/var/lib/hearthline/ministack/s3` |

Metadata is written on a clean shutdown. `systemctl restart hearthline-ministack` is a clean shutdown: the unit calls `podman stop` or `docker stop` and waits up to 20 seconds. Pulling the power cord can lose the last moments. The S3 bytes are written as objects arrive, so a bucket's files are less fragile than the JSON state.

Reset the emulated account between exercises:

```bash
curl -X POST http://127.0.0.1:4566/_ministack/reset
```

The reset does not remove the containers or the systemd units. Add `?init=1` if you later place init scripts in MiniStack's init directory and want them to run again. Hearthline does not install init scripts.

## Images and updates

```bash
sudo ./install.sh
```

The script pulls `ministackorg/ministack:full` and `davireis/stackport:latest`, rewrites the units, and restarts. Pin a different image by editing `MINISTACK_IMAGE` in `install.sh` before you run it, or by changing the unit and running `systemctl daemon-reload`. A future flag may expose the image name. Today the variables at the top of `install.sh` are the switch.

## Real infrastructure

`--real-infra` bind-mounts the Podman or Docker socket into MiniStack. RDS, ElastiCache, and ECS can then start real sidecar containers. That socket is a powerful interface: code inside the lab can start and stop containers as the engine's user. Leave the flag off unless the exercise needs those services. Lambda stays on `LAMBDA_EXECUTOR=local` either way, so Python and Node functions run inside the MiniStack container.

The Podman socket is not a perfect stand-in for the Docker API. If a sidecar fails, try the same lab on Docker before you treat it as a MiniStack bug.

## Uninstall

```bash
sudo ./uninstall.sh
sudo ./uninstall.sh --purge
```

Without `--purge`, the data directory stays. The firewall rules recorded at install time are removed in both cases. The AWS CLI package and your `~/.aws` profiles are not removed. Delete the `hearthline` profile by hand if you want it gone.
