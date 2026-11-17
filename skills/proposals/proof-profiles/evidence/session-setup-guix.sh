#!/bin/bash
# Guix for the estate's pinned proof toolchain (Agda, Rocq, Lean via each repo's channels.scm).
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends guix
getent group guixbuild >/dev/null || groupadd --system guixbuild
for i in 01 02 03 04; do
  id "guixbuilder$i" >/dev/null 2>&1 || useradd -g guixbuild -G guixbuild -d /var/empty -s "$(command -v nologin)" -c "Guix build user $i" --system "guixbuilder$i"
done
for k in /usr/share/guix/*.pub; do guix archive --authorize < "$k"; done
# The daemon is not started here. Start it in the session, with a UTF-8 locale:
cat > /usr/local/bin/guix-daemon-up <<'EOS'
#!/bin/bash
export LC_ALL=C.UTF-8 LANG=C.UTF-8
pgrep -x guix-daemon >/dev/null && { echo "guix-daemon already running"; exit 0; }
setsid nohup guix-daemon --build-users-group=guixbuild --disable-chroot >/var/log/guix-daemon.log 2>&1 </dev/null &
sleep 3
pgrep -x guix-daemon >/dev/null && echo "guix-daemon started" || { echo "guix-daemon failed to start; see /var/log/guix-daemon.log"; exit 1; }
EOS
chmod +x /usr/local/bin/guix-daemon-up
