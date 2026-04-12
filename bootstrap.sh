#!/bin/bash 

# ==============================================================================
# Cam's Interactive VPS Bootstrap
# Uses whiptail for that "Proxmox-style" feel.
# Run this by running the command below in the shell:
# sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/walkercam/selfhosted/refs/heads/main/bootstrap.sh)"
# ==============================================================================

#TODO:
#Add logging
#Add dry run mode

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
NEW_USER="cam"

#Check that we have sudo 
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root (use sudo)."
    exit 1
fi

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

# --- 4. Sanity Check (Echo the list) ---
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
    echo "User aborted."
    exit 1
fi

# --- Execution Starts Here ---
export DEBIAN_FRONTEND=noninteractive

if [ "$DO_UPDATE" = true ]; then
	echo "--- Starting System Updates ---"
	apt-get update && apt-get upgrade -y && apt autoremove -y
	# Install must have software
	# curl and wget are core linux functionality
	# tmux for SSH session persistence (need to figure out how to use it!)
	echo "--- Installing required software curl and wget ---"
	apt-get install -y curl wget sudo
	# add reboot if required
fi

if [ "$DO_TIME" = true ]; then
	#Set time and date
	echo "--- Setting timezone ---"
	timedatectl set-timezone "$TIMEZONE"
fi

if [ "$DO_AUTO" = true ]; then
	echo "--- Starting Auto Update configuration ---"
	echo "--- Installing required update software unattended-upgrades and needrestart ---"
	apt-get install -y unattended-upgrades needrestart
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

	# Configure needrestart for automatic mode	
	sed -i "s/#\$nrconf{restart} = 'i';/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
fi

if [ "$DO_HOST" = true ]; then
	# set hostname
	# hostnamectl set-hostname your-server-name
	# nano /etc/hosts
	# Add: 127.0.1.1 your-server-name to that file
	
	HOSTNAME=$(whiptail --inputbox "Enter hostname:" 10 60 "$NEW_USER" 3>&1 1>&2 2>&3)
fi

if [ "$DO_USER" = true ]; then
    echo "Creating new user..."

    # Prompt for username (with default)
    NEW_USER=$(whiptail --inputbox "Enter new username:" 10 60 "$NEW_USER" 3>&1 1>&2 2>&3)

    if [ $? -ne 0 ]; then
        echo "User creation cancelled."
        exit 0
    fi

    if id "$NEW_USER" >/dev/null 2>&1; then
        echo "User $NEW_USER already exists, skipping creation."
    else
        useradd -m -s /bin/bash -c "Created with Cam's bootstrap script" "$NEW_USER"

        # --- Password input + validation loop ---
		while true; do
			if ! PASSWORD1=$(whiptail --passwordbox "Enter password for $NEW_USER (min 8 chars):" 10 60 3>&1 1>&2 2>&3); then
				echo "User creation cancelled."
				exit 0
			fi

			if ! PASSWORD2=$(whiptail --passwordbox "Confirm password:" 10 60 3>&1 1>&2 2>&3); then
				echo "User creation cancelled."
				exit 0
			fi

			if [ -z "$PASSWORD1" ]; then
				whiptail --msgbox "Password cannot be empty." 8 40
				continue
			fi

			if [ ${#PASSWORD1} -lt 8 ]; then
				whiptail --msgbox "Password must be at least 8 characters long." 8 50
				continue
			fi

			if [ "$PASSWORD1" != "$PASSWORD2" ]; then
				whiptail --msgbox "Passwords do not match. Try again." 8 50
				continue
			fi

			break
		done

        echo "$NEW_USER:$PASSWORD1" | chpasswd
		unset PASSWORD1 PASSWORD2 # Remove plain text passwords from memory

        # Add to sudo group
        usermod -aG sudo "$NEW_USER"

        # Fix ownership and permissions
        chown -R "$NEW_USER:$NEW_USER" /home/"$NEW_USER"
        chmod 700 /home/"$NEW_USER"

        # Prepare .ssh directory
        mkdir -p /home/"$NEW_USER"/.ssh
        chmod 700 /home/"$NEW_USER"/.ssh
        chown "$NEW_USER:$NEW_USER" /home/"$NEW_USER"/.ssh

        echo "User $NEW_USER has been successfully created and configured."
    fi
fi

# SSH Hardening
if [ "$DO_SSH" = true ]; then
	echo "--- Installing Tmux for persistent SSH sessions ---"
	apt-get install -y tmux
	install -d -m 755 /etc/ssh/sshd_config.d
	cat <<EOF > /etc/ssh/sshd_config.d/99-hardening.conf
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
PermitEmptyPasswords no
KbdInteractiveAuthentication no
X11Forwarding no
AuthenticationMethods publickey
EOF
	systemctl reload ssh #reload keeps current connections alive, restart will kill them if there's a syntax error in the new settings
	
	# add a whiptail popup here that halts installation and asks the user to check ssh login before proceeding
	# only proceed if they say it works otherwise exit and echo to the user that they need to fix ssh before
	# running this script again (and to not log out of this session)
fi

	# Todo:
	# 👉 Make sure you already have SSH keys working before submitting this change otherwise you can lock yourself out
	# detect if keys exist first?
	# warn the user via whiptail?
	# auto-install their public key? Add a dialog where it can be pasted in?
	

# Don't use UFW because OCI sets the defaults up with iptables and iptables-persistent we can just leave it as is
if [ "$DO_UFW" = true ]; then
    echo "Installing UFW and setting default rules..."
    apt-get install -y ufw
	ufw default deny incoming
	ufw default allow outbound
	ufw allow 22/tcp
    ufw allow in on tailscale0 # Allow all traffic over Tailscale
    ufw --force enable	
fi

if [ "$DO_TS" = true ]; then
	echo "--- Installing Tailscale ---"
	curl -fsSL https://tailscale.com/install.sh | sh
	tailscale up --authkey="$TS_AUTHKEY" 
	# tailscale set --ssh	# Enable tailscale SSH - need to check if this breaks normal ssh?
fi

if [ "$DO_DOCKER" = true ]; then
	echo "--- Installing Docker ---"
	curl -fsSL https://get.docker.com | sh
	# Make a home for docker stacks -p create parent directories and will not error is this directory already exists
	mkdir -p "$STACK_DIR"
fi

if [ "$DO_GIT" = true ]; then
	# Add optional install for git (for downloaded/version controlling docker compose files)
	apt install git
	# echo git installed version xxxx
fi

whiptail --title "Success" --msgbox "Bootstrap Complete!\n\nNext Steps:\n1. sudo tailscale up\n2. Deploy stacks to /opt/stacks" 12 60

unset NEWT_COLORS



