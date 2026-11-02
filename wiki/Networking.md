# Networking

A lab that only answers on `127.0.0.1` is a lab for one person sitting on the server. Hearthline publishes MiniStack on every interface and then limits the firewall, when there is one, to the local subnet.

## Address detection

The installer asks the kernel for the source address of the default IPv4 route. That address is the one other computers should use. The prefix on the same interface becomes the subnet. On a typical home or office LAN this is a `/24`, for example `192.168.11.0/24` for `192.168.11.254`.

Pass `--lan-ip` and `--subnet` when the host has several addresses and the default route is not the one you want, or when the lab should be advertised on a DNS name you already control. If you pass a DNS name as `--lan-ip`, every generated URL uses that name, and the name must resolve on the other computers.

## Why StackPort joins the host network

MiniStack builds some URLs from the `Host` header of the request. An SQS queue created through a client that talks to `http://ministack:4566` comes back as `http://ministack:4566/...`. That name exists only on a container network. A laptop cannot open it.

StackPort therefore runs with `--network host` and is given:

```text
AWS_ENDPOINT_URL=http://<lan-address>:4566
```

Calls from the console hit MiniStack the same way a laptop does, and the URLs stored in the console use the LAN address. The endpoint is also written to `endpoints.json` before the first start. StackPort remembers the first endpoint it sees, so a later change of address requires a new install run, which rewrites that file.

## Firewall scope

| Backend | What Hearthline does |
| --- | --- |
| firewalld, and the service is active | Adds a rich rule: the subnet may open TCP `4566` and `8080` on the interface's zone |
| UFW, and UFW is active | `ufw allow from <subnet> to any port <port> proto tcp` |
| Either tool installed but inactive | Leaves it inactive and prints a warning |
| Neither tool | Prints a warning |

The rules are recorded in `/etc/hearthline/firewall.rules`. `uninstall.sh` removes the same rules. Hearthline will not start firewalld or UFW for you. Turning a firewall on during install is a good way to drop an SSH session.

Fedora Server's default zone allows SSH and Cockpit, and it drops everything else. On that host the rich rule is the difference between "the port is listening" and "another computer can connect". Ubuntu often has UFW installed and inactive. In that case the listening port is already reachable, and the warning is expected.

## Checks

On the server:

```bash
curl -fsS http://127.0.0.1:4566/_ministack/health
curl -fsS http://<lan-address>:8080/api/health
```

From another computer, repeat both URLs with the LAN address. If the first hop fails and the process is listening on `0.0.0.0`, the packet filter is still the thing to inspect.
