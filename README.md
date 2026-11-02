# Hearthline

Hearthline turns a Fedora or Ubuntu machine into a small AWS lab and keeps that lab lit. When the server boots, MiniStack is already listening, and StackPort is ready in the browser. The same installer understands Podman and Docker, and it aims the AWS CLI at the lab without touching a real AWS profile that is already in use.

The project is maintained by **Edson Lourenço**.

## What you get

| Piece | Role | Default |
| --- | --- | --- |
| [MiniStack](https://github.com/ministackorg/ministack) `full` | Local AWS API, 60+ services, one port | `http://<lan-address>:4566` |
| [StackPort](https://github.com/DaviReisVieira/stackport) | Web console for that API | `http://<lan-address>:8080` |
| AWS CLI profile `hearthline` | Same endpoint, path-style S3 | key `test` / secret `test` |
| systemd | Starts both services at boot and restarts them if they exit | system units |

State survives a container restart. Service metadata is stored under the data directory, and S3 object bytes are stored beside it. The account id for the key `test` is `000000000000`. The default region is `us-east-1`.

Other computers on the same subnet can call the API and open the console. The firewall change, when firewalld or UFW is active, allows only that subnet.

## Requirements

- Fedora, RHEL and its close clones, Ubuntu, or Debian
- Root, for the boot path: `sudo ./install.sh`
- Podman or Docker. If neither is present, the installer installs Podman
- A working DNS path to Docker Hub, or images that are already local

A rootless install is available with `--user`. It starts at login. It starts at boot only after linger is enabled for that user.

## Install

```bash
git clone https://github.com/edsonlourenco/hearthline.git
cd hearthline
sudo ./install.sh
```

The script is idempotent. Run it again when the LAN address changes, or when you want a newer image pull.

Check the decisions first:

```bash
./install.sh --print-plan
```

On a typical Fedora server the plan looks like this: Podman, a system service, firewalld, and the host's current IPv4 address.

### Useful flags

| Flag | Effect |
| --- | --- |
| `--runtime podman` or `--runtime docker` | Force the engine |
| `--lan-ip` and `--subnet` | Override detection |
| `--skip-stackport` | MiniStack only |
| `--skip-awscli` | Leave the AWS CLI alone |
| `--skip-firewall` | Do not touch firewalld or UFW |
| `--real-infra` | Mount the engine socket so MiniStack can start sidecar containers for RDS, ECS, and similar services |
| `--user` | Rootless units under your own systemd |
| `--prefix DIR` | Data directory. The default is `/var/lib/hearthline` |

`--real-infra` is off by default. Lambda runs inside the MiniStack container (`LAMBDA_EXECUTOR=local`), which is the safer lab setting.

## Use the lab

From any machine that can reach the host:

```bash
aws configure set aws_access_key_id test --profile hearthline
aws configure set aws_secret_access_key test --profile hearthline
aws configure set region us-east-1 --profile hearthline
aws configure set endpoint_url http://192.168.11.254:4566 --profile hearthline
aws configure set s3.addressing_style path --profile hearthline

aws --profile hearthline s3 ls
aws --profile hearthline sts get-caller-identity
```

Replace the address with the one `hearthline endpoint` prints. On the server itself, the installer writes this profile for the user who ran it. If that user has no real default key, `default` is pointed at the lab as well. A default key other than `test` is left alone.

Open StackPort at `http://<lan-address>:8080`. Resource URLs, such as SQS queue URLs, use that same LAN address, so a link copied from the console still works on another computer.

Shells can pick up the variables without editing a profile:

```bash
source /etc/hearthline/env.sh
```

## Operate

```bash
hearthline status
hearthline logs
hearthline restart
hearthline endpoint
```

Persistence lives in `/var/lib/hearthline`:

- `ministack/state` maps to MiniStack's `STATE_DIR`
- `ministack/s3` maps to `S3_DATA_DIR`
- `stackport` holds the console's saved endpoint

Wipe the emulated account without deleting the containers:

```bash
curl -X POST http://127.0.0.1:4566/_ministack/reset
```

Remove the services and keep the data:

```bash
sudo ./uninstall.sh
```

`sudo ./uninstall.sh --purge` also deletes `/var/lib/hearthline`.

## How the installer chooses

1. It reads `/etc/os-release` and accepts the Fedora family or the Debian family.
2. It prefers Podman when both engines exist. `--runtime` overrides that.
3. It takes the source address of the default IPv4 route and the prefix of that interface. A `/24` becomes the firewall scope.
4. It publishes MiniStack on `0.0.0.0:4566`.
5. It runs StackPort on the host network and sets `AWS_ENDPOINT_URL` to the LAN address. That is what makes console links usable from the rest of the network.
6. If firewalld is active, it adds a rich rule for the subnet. If UFW is active, it adds an allow rule for the same subnet. An inactive firewall is left inactive, so an install cannot lock you out of SSH.
7. It writes systemd units that run the containers in the foreground. `enable --now` ties them to `multi-user.target`, which is what brings the lab back after a reboot.

On a later run, an older user-level MiniStack or StackPort container from a manual Podman setup is stopped, its Quadlet files are moved aside, and existing state is copied into `/var/lib/hearthline` when that directory is still empty.

## Layout

```text
install.sh            entry point
uninstall.sh          stop, disable, and optionally purge
hearthline            status, logs, restart, endpoint
lib/detect.sh         distro, engine, LAN address
lib/firewall.sh       firewalld and UFW
lib/aws.sh            AWS CLI v2 and the lab profile
lib/systemd.sh        units, env files, and the StackPort endpoint file
wiki/                 pages published to the GitHub wiki
```

## Documentation

The longer notes live in the [wiki](https://github.com/edsonlourenco/hearthline/wiki): installation, boot, networking, the AWS CLI, daily operations, and troubleshooting. The same pages are in the `wiki/` directory of this repository.

## License

MIT. Copyright (c) 2026 Edson Lourenço. MiniStack and StackPort remain under their own licenses. Hearthline only installs and wires them.
