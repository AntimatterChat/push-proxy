#!/bin/sh
# antimatter-push-proxy package: runs after the files are removed (deb postrm, rpm %postun). The
# credentials in /etc/antimatter-push-proxy/certs and the system user are kept.
set -e

if [ -d /run/systemd/system ]; then
    systemctl daemon-reload >/dev/null 2>&1 || true
fi
exit 0
