#!/usr/bin/env bash

# Copyright (c) 2021-2025 tteck
# Author: tteck (tteckster)
# License: MIT | https://github.com/community-scripts/ProxmoxVE/raw/main/LICENSE
# Source: https://octoprint.org/

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

read -r -p "Would you like to install HAproxy to be able to reach the web interface on port 80? (y or n) " prompt
if [[ $prompt == "y" ]]; then
  HAPROXY="true"
else
  HAPROXY="false"
fi

msg_info "Installing Dependencies"
$STD apt-get install -y git \
  libyaml-dev \
  build-essential
msg_ok "Installed Dependencies"

if [[ $HAPROXY == "true" ]]; then
  msg_info "Installing HAproxy"
  $STD apt-get install -y haproxy
  msg_ok "Installed HAproxy"
fi

msg_info "Setup Python3"
$STD apt-get install -y \
  python3 \
  python3-dev \
  python3-pip \
  python3-venv \
  python3-setuptools
rm -rf /usr/lib/python3.*/EXTERNALLY-MANAGED
msg_ok "Setup Python3"

msg_info "Creating user octoprint"
useradd -m -s /bin/bash -p $(openssl passwd -1 octoprint) octoprint
usermod -aG sudo,tty,dialout octoprint
chown -R octoprint:octoprint /opt
echo "octoprint ALL=NOPASSWD: $(command -v systemctl) restart octoprint, $(command -v reboot), $(command -v poweroff)" >/etc/sudoers.d/octoprint
msg_ok "Created user octoprint"

msg_info "Installing OctoPrint"
$STD sudo -u octoprint bash <<EOF
mkdir /opt/octoprint
cd /opt/octoprint
python3 -m venv .
source bin/activate
pip install --upgrade pip
pip install wheel
pip install octoprint
EOF
msg_ok "Installed OctoPrint"

if [[ $HAPROXY == "true" ]]; then
  msg_info "Setup HAProxy"
  cat <<EOF >/etc/haproxy/haproxy.cfg
global
        maxconn 4096
        user haproxy
        group haproxy
        daemon
        log 127.0.0.1 local0 debug

defaults
        log     global
        mode    http
        option  httplog
        option  dontlognull
        retries 3
        option redispatch
        option http-server-close
        option forwardfor
        maxconn 2000
        timeout connect 5s
        timeout client  15min
        timeout server  15min

frontend public
        bind *:80
        use_backend webcam if { path_beg /webcam/ }
        default_backend octoprint

backend octoprint
        option forwardfor
        server octoprint1 127.0.0.1:5000

backend webcam
        http-request replace-path /webcam/(.*)   /\1
        server webcam1  127.0.0.1:8080
EOF
  msg_ok "Created HAProxy"

  msg_info "Restart HAproxy"
  systemctl restart haproxy.service
  msg_ok "Restarted HAproxy"
fi

msg_info "Creating Service"
cat <<EOF >/etc/systemd/system/octoprint.service
[Unit]
Description=The snappy web interface for your 3D printer
After=network-online.target
Wants=network-online.target

[Service]
Environment="LC_ALL=C.UTF-8"
Environment="LANG=C.UTF-8"
Type=exec
User=octoprint
ExecStart=/opt/octoprint/bin/octoprint serve

[Install]
WantedBy=multi-user.target
EOF

systemctl enable -q --now octoprint
msg_ok "Created Service"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
