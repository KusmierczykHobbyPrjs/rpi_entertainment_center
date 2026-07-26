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
this module. Free hostnames need confirming every 30 days.

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

**I locked myself out with ufw**

Get to the Pi's physical console, or over Meshnet, and:

```bash
sudo ufw allow OpenSSH
sudo ufw status
```

Always allow SSH *before* enabling the firewall — the installer does this in
the right order.
