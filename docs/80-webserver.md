# 80-webserver — a public web server on the Pi

Apache and PHP, a No-IP hostname so a changing home IP still resolves, a Let's
Encrypt certificate, and the hardening a machine on the open internet needs.

```bash
./install.sh 80-webserver
```

**Prerequisites:** `00-base`, a free [No-IP](https://www.noip.com/) account,
and the ability to configure port forwarding on your router.

---

> ## Read this first
>
> **This is the only module that exposes the Pi to the public internet.**
> Everything else in this project stays private.
>
> If you only want to reach the Pi *yourself* from elsewhere, use **Meshnet**
> (module [70-nordvpn](70-nordvpn.md)) instead. It needs no open ports, no
> certificates and no hardening, and it is the better answer to that problem.
>
> Use this module when you genuinely want other people to reach a site you
> host.

---

## What it does

1. Installs Apache, PHP and `libapache2-mod-php`.
2. Enables **unattended security upgrades** — mandatory for anything
   internet-facing.
3. Hardens Apache: no directory listings, no version disclosure.
4. Builds and installs the **No-IP Dynamic Update Client** from source, with a
   systemd unit.
5. Requests a **Let's Encrypt certificate** via Certbot and enables automatic
   renewal.
6. Optionally enables `ufw`.
7. Removes the temporary `phpinfo()` page it created for testing.

---

## The three pieces

### Dynamic DNS (No-IP)

Home connections get a new public IP periodically. No-IP maps a fixed hostname
(`something.ddns.net`) to whatever your current address is; the update client
on the Pi reports changes.

Create a free account and a hostname at <https://www.noip.com/> before running
this module. The client itself is documented at
<https://my.noip.com/dynamic-dns/duc>. Free hostnames need confirming every 30 days.

**No-IP's own one-line installer does not work on Raspberry Pi OS** — it
assumes x86 packages. That is why this module builds the client from source,
which is architecture independent and works on every Pi model.

During `make install` you are asked for your account email, password, which
hostname to update, and an update interval. The defaults are fine.

Configuration lives in `/usr/local/etc/no-ip2.conf`. Reconfigure with:

```bash
sudo systemctl stop noip2
sudo noip2 -C
sudo systemctl start noip2
```

### Router port forwarding — you must do this yourself

**No script can do this for you.** In your router's admin interface, forward:

| External port | To | Purpose |
|---|---|---|
| 80 | the Pi's LAN IP, port 80 | HTTP, and Certbot's validation |
| 443 | the Pi's LAN IP, port 443 | HTTPS |

Give the Pi a **static DHCP lease** first, or the forward will point at the
wrong device after a reboot.

**Do not forward port 22.** SSH exposed to the internet attracts continuous
brute-force attempts. Reach it over Meshnet instead.

### HTTPS (Let's Encrypt)

Certbot proves you control the hostname by answering a request on port 80.
Before running it, all of these must be true:

- your No-IP hostname resolves to your current public IP
- your router forwards ports 80 **and** 443 to the Pi
- your ISP does not block inbound port 80

Then:

```bash
sudo certbot --apache
```

Choose **redirect** when it offers to send HTTP to HTTPS.

Certificates land in `/etc/letsencrypt/`, and `certbot.timer` renews them
automatically. Test renewal with:

```bash
sudo certbot renew --dry-run
```

---

## Hardening

The module applies these; they are worth understanding rather than just
running.

**Automatic security updates.** The single most valuable thing for an
internet-facing machine:

```bash
sudo apt install unattended-upgrades
# /etc/apt/apt.conf.d/20auto-upgrades
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
```

**No directory listings.** Otherwise any folder without an index page exposes
its entire contents:

```bash
sudo a2dismod -f autoindex
```

**No version disclosure.** Mass scanners match banners against known-vulnerable
releases. In `/etc/apache2/conf-available/security.conf`:

```
ServerTokens Prod
ServerSignature Off
```

**Minimal open ports.** Review what is listening:

```bash
sudo ss -tlnp
```

If you only serve HTTPS, close 80 at the router once the certificate is
issued — but note that Certbot needs it again at renewal unless you switch to
DNS validation.

**No phpinfo page.** The module creates one to verify PHP works and deletes it
at the end. `doctor.sh` fails if one reappears — it lists every module,
version and path on the system.

---

## The firewall (ufw)

`ufw` ("Uncomplicated Firewall") is a readable front end to the kernel's packet
filter. It decides what may *reach* the Pi. This is the only module that turns
it on, and answering **yes** is the right choice: once the router forwards 80
and 443, the firewall is what guarantees the only thing reachable from the
internet is Apache.

That matters more than it sounds. Kodi's JSON-RPC on 8080 has no authentication
worth the name — without a firewall it is one router mistake away from being
public.

### The trap this module used to fall into

`80-webserver` is normally the *last* module installed, and a default-deny
policy that opens only 22, 80 and 443 cuts off everything installed before it:

| Port | Service | What breaks |
|---|---|---|
| 8080/tcp | Kodi web interface & JSON-RPC | Kore and Yatse stop connecting |
| 9090/tcp | Kodi JSON-RPC (raw) | remote scripting |
| 9777/udp | Kodi EventServer | `kodi-send` silently does nothing |
| 9981-9982/tcp | Tvheadend web + HTSP | TV clients |
| 1714-1764 | KDE Connect | phone pairing never completes |
| 445, 139, 137-138 | Samba | ROM copying to RetroPie |
| 5353/udp | mDNS / Avahi | `<hostname>.local` stops resolving |
| `nordlynx` | **Meshnet** | the Pi disappears from remote access |

Nothing reports an error. It reads exactly like "the Pi broke".

### What the module does now

After enabling ufw it detects what is actually installed and re-opens each
service **to the local network only** — never to the internet:

```
[ok] ufw enabled (SSH, HTTP and HTTPS allowed from anywhere)
[..] Re-opening the ports the rest of this project needs:
  [ok]   Kodi web interface - 8080/tcp from the local network
  [ok]   Kodi JSON-RPC - 9090/tcp from the local network
  [ok]   Kodi EventServer - 9777/udp from the local network
  [ok]   KDE Connect - 1714:1764/tcp from the local network
  [ok]   mDNS / Avahi discovery - 5353/udp from the local network
  [ok]   NordVPN Meshnet - everything arriving on nordlynx
```

Detection is by what is present on the machine, not by which modules you
picked, so **install order stops mattering**. Modules installed *after* ufw
(`45-kdeconnect`, `75-port-forwarding`) already open their own ports.

Your local network is read from the kernel's routing table, so any interface
name and any subnet works. Meshnet is handled as a whole-interface rule
(`allow in on nordlynx`) rather than a subnet, because `100.64.0.0/10` is
shared with every other NordVPN user — WireGuard has already authenticated the
peer before the packet reaches the firewall.

### Re-running it

Installed another module since? Re-open its ports without touching anything
else:

```bash
bash bin/firewall_refresh.sh            # re-open what is installed now
bash bin/firewall_refresh.sh --status   # show the current rules
bash bin/firewall_refresh.sh --enable   # install and enable ufw, then open
```

It is idempotent — ufw ignores rules it already has.

### SSH stays open to everywhere

Deliberately. Restricting 22 to the LAN would lock out anyone who reaches the
Pi from elsewhere, and recovering needs a keyboard and monitor attached. If you
only ever connect from home or over Meshnet, tighten it yourself:

```bash
sudo ufw delete allow OpenSSH
sudo ufw allow from 192.168.1.0/24 to any port 22 proto tcp
```

Meshnet SSH keeps working either way, via the `nordlynx` rule.

> **Never enable ufw over SSH without allowing 22 first.** Both
> `80-webserver` and `firewall_refresh.sh --enable` add that rule *before*
> `ufw enable` for exactly this reason.

---

## Serving your own content

```
/var/www/html/          document root
```

```bash
sudo chown -R $USER:www-data /var/www/html
sudo chmod -R 755 /var/www/html
```

Then copy your files in. PHP works out of the box: any `.php` file in the
document root is executed.

---

## Verify

```bash
./bin/doctor.sh web
```

Checks Apache is running, no phpinfo page is exposed, the No-IP client is
running, a certificate exists with renewal scheduled, and unattended upgrades
are enabled.

Manually:

```bash
curl -I http://localhost
curl -I https://your-hostname.ddns.net
sudo certbot certificates
systemctl status noip2 apache2
```

---

## Troubleshooting

**Certbot fails: "Timeout during connect"**

Port 80 is not reaching the Pi. In order of likelihood:

1. Router forwarding is missing or points at the wrong IP.
2. The Pi's LAN address changed — give it a static DHCP lease.
3. Your ISP blocks inbound port 80. Many residential ISPs do. Use DNS
   validation instead:

   ```bash
   sudo certbot --manual --preferred-challenges dns -d your-hostname.ddns.net
   ```

Check from outside your network — from a phone on mobile data, not from your
own LAN, since many routers do not loop back external addresses.

**The hostname resolves to the wrong IP**

```bash
systemctl status noip2
sudo journalctl -u noip2 -n 50
```

Free No-IP hostnames also expire every 30 days unless confirmed by email.

**Apache will not start**

```bash
sudo apache2ctl configtest
sudo journalctl -u apache2 -n 50
```

Usually a syntax error in a site file, or port 80 already taken.

**"Site can't be reached" from outside but fine on the LAN**

Test from mobile data, not from inside your network — router NAT loopback
often does not work.

Then check, in order: No-IP resolves correctly (`nslookup your-hostname.ddns.net`),
router forwarding, and `ufw` on the Pi (`sudo ufw status`).

**Certificate renewal fails**

```bash
sudo certbot renew --dry-run
```

Almost always port 80 no longer reaching the Pi — the same causes as the
initial issue.

**PHP shows source code instead of running**

```bash
sudo apt install libapache2-mod-php
sudo a2enmod php7.4        # match your PHP version
sudo systemctl restart apache2
```

**Kore/Yatse, `kodi-send` or Meshnet stopped working after this module**

The firewall is on and that service's port is not open — the usual cause is
that ufw was enabled by an older version of this module, which opened only 22,
80 and 443. Check and repair:

```bash
sudo ufw status verbose          # is your service listed?
bash bin/firewall_refresh.sh     # re-open everything that is installed
```

Note that `iptables -L INPUT` is **not** a reliable way to check this. On
Raspberry Pi OS ufw uses the nftables backend and its rules live in the `inet
filter` table, so `iptables -L` shows an empty `policy ACCEPT` chain on a Pi
whose firewall is fully active. Use `sudo ufw status`, or `sudo nft list
ruleset`.

Also note `ufw` is in `/usr/sbin`, which is not on a normal user's `PATH` —
`which ufw` finding nothing does not mean it is not installed.

**I locked myself out with ufw**

Get to the Pi's physical console, or over Meshnet, and:

```bash
sudo ufw allow OpenSSH
sudo ufw status
```

Always allow SSH *before* enabling the firewall — the installer does this in
the right order.
