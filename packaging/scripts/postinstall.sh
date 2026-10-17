#!/bin/sh
# antimatter-push-proxy package: runs after the files are installed or upgraded (deb postinst,
# rpm %post). Creates the antimatter-push-proxy system user and lets it read the settings, then
# enables the service without starting it.
set -e

# deb: "configure" [<previous version>]; rpm: 1 (install) or 2 (upgrade).
first=
case "$1" in
    configure) [ -n "$2" ] || first=1 ;;
    1) first=1 ;;
    2) ;;
    *) exit 0 ;;
esac

user=antimatter-push-proxy
etc=/etc/antimatter-push-proxy
nologin=/usr/sbin/nologin
[ -x "$nologin" ] || nologin=/sbin/nologin
getent group "$user" >/dev/null 2>&1 || groupadd --system "$user"
getent passwd "$user" >/dev/null 2>&1 ||
    useradd --system --gid "$user" --home-dir /var/lib/antimatter-push-proxy --no-create-home \
        --shell "$nologin" --comment "Antimatter push proxy" "$user"

install -d -o "$user" -g "$user" -m 0750 /var/lib/antimatter-push-proxy
# root owns the settings and the credentials; the service's group reads them.
install -d -o root -g "$user" -m 0750 "$etc" "$etc/certs"
chgrp "$user" "$etc/antimatter-push-proxy.json" && chmod 0640 "$etc/antimatter-push-proxy.json"

if [ -d /run/systemd/system ]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
    if [ -n "$first" ]; then
        systemctl enable antimatter-push-proxy.service >/dev/null 2>&1 || true
    fi
fi

if [ -n "$first" ]; then
    cat <<MSG

The Antimatter push proxy is installed and enabled, but not started. Next steps:
  1. Copy the APNs key (.p8) and the Firebase service account (.json) into $etc/certs,
     readable by the service's group:
     sudo install -o root -g $user -m 0640 AuthKey_X.p8 firebase-service-account.json $etc/certs/
  2. Fill in $etc/antimatter-push-proxy.json, e.g. "AppleAuthKeyFile": "./certs/AuthKey_X.p8".
  3. Start it: sudo systemctl start antimatter-push-proxy   (logs: journalctl -u antimatter-push-proxy)
  4. Point Antimatter at it: System Console > Environment > Push Notification Server,
     http://<this host>:8066. The proxy listens on all addresses and doesn't authenticate
     servers: keep port 8066 on a private network or behind a reverse proxy.
MSG
else
    echo "The push proxy was upgraded; restart it to use the new version: sudo systemctl restart antimatter-push-proxy"
fi
exit 0
