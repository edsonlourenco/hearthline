# Hearthline

Hearthline is a small installer for a local AWS lab. It provisions [MiniStack](https://github.com/ministackorg/ministack) and [StackPort](https://github.com/DaviReisVieira/stackport), opens the lab to the local subnet, and registers systemd units so the lab is already up after a reboot.

The project is maintained by **Edson Lourenço**.

## Start here

- [Installation](Installation) covers the supported hosts, the flags, and a first successful call.
- [Boot and systemd](Boot-and-systemd) explains why the containers are foreground processes, and how linger differs from a system unit.
- [Networking](Networking) explains the LAN address, the firewall scope, and why StackPort uses the host network.
- [AWS CLI](AWS-CLI) shows the profile, path-style S3, and what the installer refuses to overwrite.
- [Operations](Operations) is the short list of commands you will actually use.
- [Troubleshooting](Troubleshooting) collects the failures that showed up while the lab was first brought online.

## The shape of a lab

| Setting | Value |
| --- | --- |
| MiniStack image | `docker.io/ministackorg/ministack:full` |
| API | port `4566` on all interfaces |
| Console | StackPort on port `8080` |
| Credentials | access key `test`, secret `test` |
| Account | `000000000000` |
| Region | `us-east-1` |
| Persistence | `PERSIST_STATE=1` and `S3_PERSIST=1` |

The `full` image is the one that includes Athena's DuckDB engine and the native database drivers. The smaller default image is enough for S3 and SQS, but a lab that is meant to feel like AWS is better on `full`.

Hearthline does not replace MiniStack. It is the part that makes the emulator survive a reboot and answer on the network you actually use.
