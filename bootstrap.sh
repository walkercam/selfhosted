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
	"KEYS"	 "Add new SSH public keys" OFF \
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
DO_KEYS=false
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
[[ $RESULTS == *'"KEYS"'* ]]   && DO_KEYS=true
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
echo "Add SSH Keys:       $DO_KEYS"
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
	if ! NEW_USER=$(whiptail --inputbox "Enter new username:" 10 60 "$NEW_USER" 3>&1 1>&2 2>&3); then
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
				whiptail --msgbox "Password cannot be empty. Try again." 8 40
				continue
			fi

			if [ ${#PASSWORD1} -lt 8 ]; then
				whiptail --msgbox "Password must be at least 8 characters long. Try again." 8 50
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

        # Prepare .ssh directory
        mkdir -p /home/"$NEW_USER"/.ssh
		
        # --- NEW: SSH Key Transfer Logic ---
        # Identify who is running sudo to find their keys
        REAL_USER=${SUDO_USER:-$(whoami)}
        AUTH_KEYS_FILE="/home/$REAL_USER/.ssh/authorized_keys"

        if [ -f "$AUTH_KEYS_FILE" ]; then
            # Extract key info for the dialog box (Type and Comment/Email)
            # This handles multiple keys by taking the first one found
            KEY_INFO=$(awk '{print $1, $3}' "$AUTH_KEYS_FILE" | head -n 1)
            
            if whiptail --title "Transfer SSH Keys" --yesno "Found existing key for $REAL_USER:\n\n$KEY_INFO\n\nTransfer this to $NEW_USER?" 12 60; then
                cp "$AUTH_KEYS_FILE" /home/"$NEW_USER"/.ssh/authorized_keys
                echo "SSH keys transferred from $REAL_USER."
            fi
        fi
		
        # Fix ownership and permissions
        # Doing this AFTER the SSH transfer ensures the new keys have correct ownership
        chown -R "$NEW_USER:$NEW_USER" /home/"$NEW_USER"
        chmod 700 /home/"$NEW_USER"
        chmod 700 /home/"$NEW_USER"/.ssh
		[ -f /home/"$NEW_USER"/.ssh/authorized_keys ] && chmod 600 /home/"$NEW_USER"/.ssh/authorized_keys

        echo "User $NEW_USER has been successfully created and configured."
    fi
fi

if [ "$DO_KEYS" = true ]; then
    echo "Starting SSH key configuration..."

    while true; do
        # 1. Build the target user list
        USER_OPTIONS=()
        while IFS=: read -r username _ uid _ _ _ _; do
            if [ "$uid" -ge 1000 ] && [ "$username" != "nobody" ]; then
                USER_OPTIONS+=("$username" "System User")
            fi
        done < /etc/passwd
        USER_OPTIONS+=("DONE" "Finish & Move to Next Section")

        # Select User
		if ! TARGET_USER=$(whiptail --title "Select User" --menu "Select a user to modify keys, or 'DONE' to continue." 15 60 6 "${USER_OPTIONS[@]}" 3>&1 1>&2 2>&3); then
			echo "SSH Key addition cancelled. Stopping script here."
			exit 0
		fi
	
        if [ "$TARGET_USER" = "DONE" ]; then
            break
        fi

        # 2. Identify Paths
        USER_HOME=$(eval echo "~$TARGET_USER")
        SSH_DIR="$USER_HOME/.ssh"
        AUTH_KEYS="$SSH_DIR/authorized_keys"
        mkdir -p "$SSH_DIR"
        touch "$AUTH_KEYS"
        chmod 700 "$SSH_DIR"
        chmod 600 "$AUTH_KEYS"
		
        # 3. Handle Deletion of Existing Keys
        if [ -s "$AUTH_KEYS" ]; then
            CHECKLIST_ITEMS=()
            # Read keys into a numbered list for the checklist
            # We use the line number as the tag
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                KEY_INFO=$(echo "$line" | awk '{print $1, $3}')
                CHECKLIST_ITEMS+=("$line" "$KEY_INFO" "ON")
            done < "$AUTH_KEYS"

            # Pop up checkbox: Selected keys will be REMAINING
            SELECTED_KEYS=$(whiptail --title "Manage Existing Keys" --separate-output --checklist \
            "Uncheck keys to DELETE them. Press Space to toggle, Enter to confirm." 15 70 6 "${CHECKLIST_ITEMS[@]}" 3>&1 1>&2 2>&3)

            if [ $? -eq 0 ]; then
                echo "$SELECTED_KEYS" > "$AUTH_KEYS"
                echo "Keys updated for $TARGET_USER."
            fi
        fi

        # 4. Display Current Status
        if [ -s "$AUTH_KEYS" ]; then
            KEY_SUMMARY=$(awk '{print "Type: " $1 " | Comment: " $3}' "$AUTH_KEYS")
            whiptail --title "Existing Keys for $TARGET_USER" --msgbox "Current active keys:\n\n$KEY_SUMMARY" 15 70
        else
            whiptail --title "Keys Status" --msgbox "No keys currently exist for $TARGET_USER." 8 50
        fi

        # 5. Key Addition Loop
        while true; do
            if ! whiptail --title "Add New Key" --yesno "Would you like to ADD a new SSH key for $TARGET_USER?" 8 50; then
                break
            fi

            PASTED_KEY=$(whiptail --title "Add SSH Key" --inputbox "Paste public key (ssh-rsa, ed25519, etc.):" 10 70 3>&1 1>&2 2>&3)
            
            if [ -n "$PASTED_KEY" ]; then
                TEMP_KEY=$(mktemp)
                echo "$PASTED_KEY" > "$TEMP_KEY"
                if ssh-keygen -l -f "$TEMP_KEY" >/dev/null 2>&1; then
                    echo "$PASTED_KEY" >> "$AUTH_KEYS"
                    whiptail --msgbox "Key added successfully!" 8 40
                else
                    whiptail --msgbox "Invalid key format. Skipping." 8 40
                fi
                rm -f "$TEMP_KEY"
            fi
        done

        # Final ownership enforcement for this user's loop
        chown -R "$TARGET_USER:$TARGET_USER" "$SSH_DIR"
        chmod 600 "$AUTH_KEYS"
    done
    echo "SSH Key Management section complete."
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
fi

# --- Safety Check Logic ---
# This checks if any of the 'danger' sections were run
if [ "$DO_USER" = true ] || [ "$DO_KEYS" = true ] || [ "$DO_SSH" = true ]; then
    
    # Define the warning message
    WARNING_MSG="WARNING: SSH settings or users have been modified.\n\n"
    WARNING_MSG+="Please start another INDEPENDENT SSH session now and ensure you can still log in.\n\n"
    WARNING_MSG+="DO NOT terminate this current session until you are 100% confident that your new users, keys, and hardening settings are functioning.\n\n"
    WARNING_MSG+="If you are locked out, you can still use this open window to fix permissions or revert changes.\n\n"
    WARNING_MSG+="Press YES to continue with remaining bootstrap tasks, or NO to abort the script immediately."

    # Display the Whiptail Warning
    if whiptail --title "Warning: SSH Settings Modified" \
                --yesno "$WARNING_MSG" 20 150; then
        echo "User acknowledged SSH changes. Continuing with bootstrap..."
    else
        echo "Bootstrap aborted by user to verify SSH connectivity."
        exit 1
    fi
fi
	

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
	# Whiptail boxes to enter user data?
	apt install git
	# echo git installed version xxxx
fi

whiptail --title "Success" --msgbox "Bootstrap Complete!\n\nNext Steps:\n1. sudo tailscale up\n2. Deploy stacks to /opt/stacks" 12 60
echo "--- Bootstrap Complete! ---"

unset NEWT_COLORS



