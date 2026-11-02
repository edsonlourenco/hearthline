# Troubleshooting

## The unit never becomes active

```bash
systemctl status hearthline-ministack.service
journalctl -u hearthline-ministack.service -n 80 --no-pager
```

`ExecStartPost` fails the start when `/_ministack/health` is still down after the retries. The usual causes are a slow first pull, a port that is already taken, or a volume that the container cannot write.

SELinux on Fedora is the volume case. Hearthline adds `:Z` when `/sys/fs/selinux/enforce` exists, which gives the container a private label. If you copied data in by hand, relabel it:

```bash
sudo restorecon -Rv /var/lib/hearthline
```

## Port 4566 or 8080 is already in use

A previous manual container is the common reason. The installer stops containers named `ministack` and `stackport` and moves their Quadlet files aside, but only for `SUDO_USER`. If some other process owns the port, stop that process or pass `--ministack-port` and `--stackport-port`.

```bash
sudo ss -ltnp | grep -E ':4566|:8080'
```

## The server can connect, and laptops cannot

Confirm the process listens on all interfaces:

```bash
sudo ss -ltn | grep -E ':4566|:8080'
```

`127.0.0.1:8080` only, or `127.0.0.1:4566` only, means the publish address is wrong. Hearthline's units use `-p 4566:4566` and `--network host` for StackPort, which should show `0.0.0.0`.

If the listen address is already `0.0.0.0` and a laptop still times out, the host firewall is dropping the packets. On Fedora:

```bash
sudo firewall-cmd --zone=FedoraServer --list-rich-rules
```

Use the zone of your interface if it is not `FedoraServer`. You should see the subnet and ports `4566` and `8080`. Re-run `sudo ./install.sh` to add the rules, or inspect `/etc/hearthline/firewall.rules`.

## The console shows 127.0.0.1 in queue URLs

StackPort stored an old endpoint. The file is `/var/lib/hearthline/stackport/endpoints.json`. A fresh `sudo ./install.sh` rewrites it to the LAN address and restarts the console. Avoid pointing `AWS_ENDPOINT_URL` at `127.0.0.1` if people on other computers will read those URLs.

## AWS CLI calls the real AWS account

The default profile was not empty, so Hearthline left it alone. Use `--profile hearthline`, or `source /etc/hearthline/env.sh`, which sets `AWS_PROFILE`.

`s3 mb` failing with a redirect or `PermanentRedirect` is almost always virtual-hosted addressing. The profile needs:

```ini
s3 =
    addressing_style = path
```

## Boot does not start the lab

For a system install:

```bash
systemctl is-enabled hearthline-ministack.service
```

The answer must be `enabled`. If you used `--user`, check linger:

```bash
loginctl show-user "$USER" -p Linger
```

`Linger=no` means the user manager never starts at boot. Enable it with `sudo loginctl enable-linger "$USER"`, or reinstall without `--user`.

## sudo has no password in this session

`install.sh` re-executes itself under sudo when it has a terminal. A session without a terminal cannot type the password. Run the script in a real SSH session:

```bash
cd ~/Sources/hearthline   # or wherever you cloned it
sudo ./install.sh
```

## Health is fine, then StackPort is empty

The console probes MiniStack with the endpoint in `endpoints.json`. If that file and the unit disagree, the health URL of StackPort can still be `ok` while resource pages fail. Compare:

```bash
curl -fsS http://127.0.0.1:8080/api/health
grep AWS_ENDPOINT_URL /etc/systemd/system/hearthline-stackport.service
```

The two URLs should match, and both should use the LAN address.
