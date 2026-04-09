#!/bin/bash 

# ==============================================================================
# Cam's Interactive VPS Bootstrap
# Uses whiptail for that "Proxmox-style" feel.
# Run this by running the command below in the shell:
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/walkercam/selfhosted/refs/heads/main/bootstrap.sh)"
# ==============================================================================

set -euo pipefail #exit on errors - don't just try to continue

#Set the newt colours so we have consistent whiptail appearance
export NEWT_COLORS='	
  root=white, blue
  border=black, lightgray
  window=black, lightgray
  shadow=white, black
  title=red, lightgray
  button=lightgray, red
  actbutton=red, lightgray
  checkbox=lightgray, blue
  actcheckbox=lightgray, red
  entry=lightgray, blue
  label=blue, lightgray
  listbox=black, lightgray
  actlistbox=lightgray, blue
  textbox=black, lightgray
  acttextbox=lightgray, red
  helpline=white, blue
  roottext=lightgray, blue
  fullscale=blue
  emptyscale=red
  disentry=blue, lightgray
  compactbutton=black, lightgray
  actsellistbox=lightgray, red
  sellistbox=black, brown
'

TIMEZONE="Pacific/Auckland"
STACK_DIR="/opt/stacks"
REBOOT_TIME="02:00"
LOG_FILE="/var/log/bootstrap.log"

# 1. Welcome Message
whiptail --title "Cam's VPS Bootstrap" --msgbox "This script will prepare a fresh linux instance.\n\nTarget: Any Debian or Ubunutu Instance" 15 60

# --- 1. The Checklist Menu ---
# The syntax for checklist is: [tag] [item] [status (on/off)]
RESULTS=$(
    whiptail --title "Mach Labs Bootstrap" --checklist \
    "Spacebar to select/deselect, Enter to confirm:" 20 75 10 \
    "UPDATE" "Update System (apt update/upgrade)" ON \
    "TIME"   "Set Timezone (UTC)" ON \
    "AUTO"   "Enable unattended-upgrades & needrestart" ON \
    "HOST"   "Set hostname" OFF \
    "USER"   "Add non-root user" OFF \
    "SSH"    "Harden SSH (Disable Password Auth)" OFF \
    "UFW"    "Install and configure UFW (NOT FOR OCI)" OFF \
    "TS"     "Install and configure Tailscale" ON \
    "DOCKER" "Install Docker" ON \
    "GIT"    "Install Git" OFF \
    3>&1 1>&2 2>&3
) || {
    echo "Setup cancelled by user."
    exit 0
}

# --- 2. Initialize Variables (Default to false) ---
DO_UPDATE=false
DO_TIME=false
DO_AUTO=false
DO_HOST=false
DO_USER=false
DO_SSH=false
DO_UFW=false
DO_TS=false
DO_DOCKER=false
DO_GIT=false

# --- 3. Parse the Results ---
# whiptail returns a string like: "UPDATE" "TIME" "TS"
# We check if the tag exists in the RESULTS string
# Match full tokens including quotes to avoid substring bugs
[[ $RESULTS == *'"UPDATE"'* ]] && DO_UPDATE=true
[[ $RESULTS == *'"TIME"'* ]]   && DO_TIME=true
[[ $RESULTS == *'"AUTO"'* ]]   && DO_AUTO=true
[[ $RESULTS == *'"HOST"'* ]]   && DO_HOST=true
[[ $RESULTS == *'"USER"'* ]]   && DO_USER=true
[[ $RESULTS == *'"SSH"'* ]]    && DO_SSH=true
[[ $RESULTS == *'"UFW"'* ]]    && DO_UFW=true
[[ $RESULTS == *'"TS"'* ]]     && DO_TS=true
[[ $RESULTS == *'"DOCKER"'* ]] && DO_DOCKER=true
[[ $RESULTS == *'"GIT"'* ]]    && DO_GIT=true

# --- 4. Sanity Check (The Echo List) ---
echo "------------------------------------------"
echo "USER SELECTIONS:"
echo "Update System:      $DO_UPDATE"
echo "Set Timezone:       $DO_TIME"
echo "Auto Upgrades:      $DO_AUTO"
echo "Set Hostname:       $DO_HOST"
echo "Add User:           $DO_USER"
echo "Harden SSH:         $DO_SSH"
echo "Install UFW:        $DO_UFW"
echo "Install Tailscale:  $DO_TS"
echo "Install Docker:     $DO_DOCKER"
echo "Install Git:        $DO_GIT"
echo "------------------------------------------"

# 4. Confirmation (Yes/No Box)
if whiptail --title "Confirm" --yesno "Proceed with installation?" 8 45; then
    echo "Starting deployment..."
else
    echo "Aborted."
    exit 1
fi

# --- Execution Starts Here ---
echo "--- Starting System Updates ---"
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y && apt autoremove -y
#add reboot if required

# Install must have software
# curl and wget are core linux functionality
# unattended-upgrades and needrestart for our auto updating process
# tmux for SSH session persistence (need to figure out how to use it!)
apt-get install -y curl wget unattended-upgrades needrestart tmux

#Set time and date
timedatectl set-timezone "$TIMEZONE"

# Using '>' ensures we overwrite any old config in this file
cat <<EOF > /etc/apt/apt.conf.d/99-unattended-upgrades-cams-custom
// Overwritten by Cams Bootstrap Script
// Any manual changes made here will be overwritten if the bootstrap script is ever run again
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "true";
Unattended-Upgrade::Automatic-Reboot-Time "$REBOOT_TIME";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
EOF

# 3. Configure needrestart for automatic mode
sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf

# add a new non root user? i think on oci this is already done with the ubuntu user but i need to research best practice
# if nothing else it would be nice to have a more realted username like homelab-ops or whatever
#add new user to sudo group

#set hostname
#hostnamectl set-hostname your-server-name
#nano /etc/hosts
#Add: 127.0.1.1 your-server-name to that file

# 4. SSH Hardening
# need to figure out some elegant way to insert a ssh key - maybe a whiptail input box?
#change port? not that keen 
mkdir -p /etc/ssh/sshd_config.d
cat <<EOF > /etc/ssh/sshd_config.d/99-hardening.conf
PasswordAuthentication no
PermitRootLogin no
EOF
#PubkeyAuthentication yes??
systemctl restart ssh

#add fail2ban

if [ "$USE_UFW" = true ]; then
    echo "Installing UFW and setting default rules..."
    apt-get install -y ufw
	ufw default deny incoming
	ufw default allow outbound
	ufw allow 22/tcp
    ufw allow in on tailscale0 # Allow all traffic over Tailscale
    ufw --force enable	
else
        echo "Running OCI Safe Setup..."
        # We don't use UFW because OCI sets the defaults up with iptables and iptables-persistent 
		# we can just leave it as is
		here to protect OCI boot volumes
fi

if [ "$INSTALL_TAILSCALE" = true ]; then
	echo "--- Installing Tailscale ---"
	curl -fsSL https://tailscale.com/install.sh | sh
	tailscale up --authkey="$TS_AUTHKEY" 
fi

if [ "$INSTALL_DOCKER" = true ]; then
	echo "--- Installing Docker ---"
	curl -fsSL https://get.docker.com | sh
	# Make a home for docker stacks -p create parent directories and will not error is this directory already exists
	mkdir -p "$STACK_DIR"
fi

#add optional install for git (for downloaded/version controlling docker compose files)

whiptail --title "Success" --msgbox "Bootstrap Complete!\n\nNext Steps:\n1. sudo tailscale up\n2. Deploy stacks to /opt/stacks" 12 60

unset NEWT_COLORS



