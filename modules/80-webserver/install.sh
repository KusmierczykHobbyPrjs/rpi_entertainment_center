#!/bin/bash
# ---------------------------------------------------------------------------
# 80-webserver - a web server on the Pi, reachable worldwide.
#
# Apache + PHP, a No-IP hostname so a changing home IP address still resolves,
# a Let's Encrypt certificate, and the hardening that a machine exposed to the
# internet needs.
#
# This is the one module that puts the Pi on the public internet. Read
# docs/80-webserver.md before running it - it also needs port forwarding on
# your router, which no script can do for you.
#
# See docs/80-webserver.md.
# ---------------------------------------------------------------------------
set -uo pipefail

REC_SKIP_CONFIG=1
# shellcheck source=../../lib/install_helpers.sh
source "$(dirname "$(readlink -f "$0")")/../../lib/install_helpers.sh"

require_not_root

cat <<EOF
${REC_C_BOLD}This module exposes the Pi to the public internet.${REC_C_OFF}

It will install a web server and walk through making it reachable from
outside. That means you also have to:
  - forward ports 80 and 443 on your ROUTER to this Pi, and
  - keep the Pi patched (this module enables automatic security updates).

If you only want to reach the Pi privately, use Meshnet (module 70-nordvpn)
instead - it needs no open ports at all.

EOF
if ! confirm "Continue with the public web server?"; then
    skip "Skipped."
    exit 0
fi

# --- Apache + PHP ----------------------------------------------------------
step "Installing Apache and PHP"
apt_install apache2 php libapache2-mod-php php-curl || exit 1
sudo systemctl enable --now apache2
ok "Apache is running"

step "Adding a PHP test page"
if [[ -f /var/www/html/info.php ]]; then
    skip "/var/www/html/info.php already exists"
else
    # Deliberately temporary: phpinfo() reveals module versions and paths, so
    # it is created for the one check and removed at the end of this module.
    echo "<?php phpinfo(); ?>" | sudo tee /var/www/html/info.php >/dev/null
    ok "Created /var/www/html/info.php (removed again at the end of this module)"
fi

IP="$(hostname -I | awk '{print $1}')"
note "Check it now from another machine: http://${IP}/info.php"

# --- Automatic security updates -------------------------------------------
step "Enabling automatic security updates"
apt_install unattended-upgrades || exit 1
# The non-interactive equivalent of `dpkg-reconfigure unattended-upgrades`.
if [[ -f /etc/apt/apt.conf.d/20auto-upgrades ]] && \
   grep -q 'Unattended-Upgrade "1"' /etc/apt/apt.conf.d/20auto-upgrades; then
    skip "Automatic upgrades already enabled"
else
    sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
    ok "Enabled daily security updates"
fi

# --- Apache hardening ------------------------------------------------------
step "Hardening Apache"
# Directory listings expose every file in a folder without a index page.
sudo a2dismod -f autoindex >/dev/null 2>&1 && ok "Disabled directory listings" \
    || skip "autoindex already disabled"

# ServerTokens/ServerSignature stop Apache advertising its exact version,
# which is what mass scanners match against known-vulnerable releases.
SEC_CONF="/etc/apache2/conf-available/security.conf"
if [[ -f "$SEC_CONF" ]]; then
    backup_file "$SEC_CONF"
    sudo sed -i 's/^ServerTokens .*/ServerTokens Prod/'      "$SEC_CONF"
    sudo sed -i 's/^ServerSignature .*/ServerSignature Off/' "$SEC_CONF"
    ok "Set ServerTokens Prod / ServerSignature Off"
fi

sudo systemctl reload apache2
ok "Apache reloaded"

# --- No-IP dynamic DNS -----------------------------------------------------
step "Installing the No-IP Dynamic Update Client"
# Home connections get a new public IP periodically. No-IP maps a fixed
# hostname to whatever the current address is; the DUC is what reports it.
#
# No-IP's own "one-line install" does not work on Raspberry Pi OS (it assumes
# x86 packages), so the client is built from source - which is architecture
# independent and works on every Pi model.
if rec_has noip2 || [[ -x /usr/local/bin/noip2 ]]; then
    skip "noip2 is already installed"
else
    if confirm "Install No-IP dynamic DNS? (needs a free account at noip.com)"; then
        apt_install gcc make || exit 1
        note "Building noip2 from source"
        (
            cd /usr/local/src || exit 1
            sudo wget -q https://www.noip.com/client/linux/noip-duc-linux.tar.gz
            sudo tar xzf noip-duc-linux.tar.gz
            cd noip-*/ || exit 1
            sudo make
            # `make install` runs an interactive configuration asking for the
            # account email, password and which hostname to keep updated.
            note "You will now be asked for your No-IP email, password and hostname."
            sudo make install
        ) || { fail "noip2 build failed - see docs/80-webserver.md"; }

        if [[ -x /usr/local/bin/noip2 ]]; then
            ok "noip2 installed"

            step "Creating the noip2 service"
            sudo tee /etc/systemd/system/noip2.service >/dev/null <<'EOF'
[Unit]
Description=No-IP Dynamic DNS Update Client
After=network-online.target
Wants=network-online.target

[Service]
Type=forking
ExecStart=/usr/local/bin/noip2
ExecStop=/usr/local/bin/noip2 -K
Restart=always
RestartSec=30

[Install]
WantedBy=multi-user.target
EOF
            sudo systemctl daemon-reload
            sudo systemctl enable --now noip2
            if systemctl is-active --quiet noip2; then
                ok "noip2 is running"
            else
                fail "noip2 did not start. Check: sudo journalctl -u noip2 -n 30"
            fi
        fi
    else
        skip "Skipped No-IP"
    fi
fi

# --- HTTPS -----------------------------------------------------------------
step "Setting up HTTPS with Let's Encrypt"
cat <<EOF

  Certbot proves you control the hostname by answering a request on port 80,
  so before continuing make sure ALL of these are true:

    - your No-IP hostname resolves to your current public IP
    - your router forwards ports 80 AND 443 to this Pi ($IP)
    - your ISP does not block inbound port 80

EOF
if confirm "Request an HTTPS certificate now?"; then
    apt_install certbot python3-certbot-apache || exit 1
    note "Certbot will ask for your hostname and email; choose 'redirect' when offered."
    if sudo certbot --apache; then
        ok "Certificate installed"
        sudo systemctl enable --now certbot.timer
        ok "Automatic renewal enabled (certbot.timer)"
        note "Test renewal any time with: sudo certbot renew --dry-run"
    else
        fail "Certbot failed. The usual cause is port 80 not reaching this Pi."
        fail "See the troubleshooting section in docs/80-webserver.md."
    fi
else
    skip "Skipped HTTPS. Run it later with: sudo certbot --apache"
fi

# --- Firewall --------------------------------------------------------------
step "Configuring the firewall"
cat <<EOF

  ufw switches this Pi to "deny everything that was not asked for". Once the
  router forwards ports 80 and 443, that is what guarantees the only thing
  reachable from the internet is Apache - not Kodi's JSON-RPC, which has no
  authentication worth the name.

  The web server stays public. Everything else this project installed - Kodi
  remotes, Tvheadend, KDE Connect, Samba, Meshnet - is re-opened to your local
  network only, so nothing you already use stops working.

EOF
if confirm "Restrict incoming connections with ufw?"; then
    apt_install ufw || exit 1
    # Order matters: allow SSH before enabling, or this very SSH session dies
    # the moment the policy takes effect.
    sudo ufw allow OpenSSH >/dev/null 2>&1 || sudo ufw allow 22/tcp >/dev/null
    sudo ufw allow 80/tcp  >/dev/null
    sudo ufw allow 443/tcp >/dev/null
    sudo ufw --force enable
    ok "ufw enabled (SSH, HTTP and HTTPS allowed from anywhere)"

    # Without this, enabling ufw here quietly breaks every other module that is
    # already installed - see the comment above rec_ufw_open_project_services.
    note "Re-opening the ports the rest of this project needs:"
    rec_ufw_open_project_services

    note "Review the result with: sudo ufw status verbose"
    note "Installed another module since? Re-run: bash bin/firewall_refresh.sh"
else
    skip "Skipped firewall"
    note "Turn it on later with: bash bin/firewall_refresh.sh --enable"
fi

# --- Cleanup ---------------------------------------------------------------
step "Removing the PHP info page"
# It served its purpose; leaving it published hands scanners a version list.
sudo rm -f /var/www/html/info.php
ok "Removed /var/www/html/info.php"

echo
ok "Web server configured."
cat <<EOF

${REC_C_BOLD}Where things are${REC_C_OFF}

  Site files      /var/www/html/
  Apache config   /etc/apache2/
  Certificates    /etc/letsencrypt/
  No-IP config    /usr/local/etc/no-ip2.conf   (reconfigure: sudo noip2 -C)

${REC_C_BOLD}Keeping it safe${REC_C_OFF}

  - Security updates install themselves (unattended-upgrades).
  - Review what is listening from time to time:  sudo ss -tlnp
  - Do not expose SSH to the internet; reach it over Meshnet instead.

See docs/80-webserver.md for the full explanation of each step.
EOF
