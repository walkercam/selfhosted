#!/bin/bash 

# ==============================================================================
# Cam's Interactive VPS Bootstrap
# Run this by running the command below in the shell:
# sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/walkercam/selfhosted/refs/heads/main/bootstrap.sh)"
# ==============================================================================

APT_UPDATED=false
TIMEZONE="Pacific/Auckland"
STACK_DIR="/opt/stacks"
REBOOT_TIME="02:00"
NEW_USER="cam"
NEW_HOSTNAME=""
TS_AUTHKEY=""
DEBUG="0"

ensure_apt_updated() {
    if [[ "$APT_UPDATED" != true ]]; then
        echo "Updating apt package lists..."
        apt-get update
        APT_UPDATED=true
    fi
}

apt_install() {
    ensure_apt_updated

    local missing=()

    for pkg in "$@"; do
        if dpkg -s "$pkg" >/dev/null 2>&1; then
            echo "$pkg already installed"
        else
            missing+=("$pkg")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        echo "Installing: ${missing[*]}"
        apt-get install -y "${missing[@]}"
    else
        echo "All packages already installed"
    fi
}

set -euo pipefail #exit on errors - don't just try to continue

export DEBIAN_FRONTEND=noninteractive
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

# --- Whiptail Wrapper Functions ---
# These redirect UI output to /dev/tty to prevent awk from corrupting the ncurses display.
whiptail_msgbox() {
    local title="$1"
    local msg="$2"
    local h="${3:-10}"
    local w="${4:-60}"
    if [ -n "$title" ]; then
        whiptail --title "$title" --msgbox "$msg" "$h" "$w" >/dev/tty 2>/dev/tty
    else
        whiptail --msgbox "$msg" "$h" "$w" >/dev/tty 2>/dev/tty
    fi
}

whiptail_yesno() {
    local title="$1"
    local msg="$2"
    local h="${3:-10}"
    local w="${4:-60}"
    if [ -n "$title" ]; then
        whiptail --title "$title" --yesno "$msg" "$h" "$w" >/dev/tty 2>/dev/tty
    else
        whiptail --yesno "$msg" "$h" "$w" >/dev/tty 2>/dev/tty
    fi
}

whiptail_input() {
    local title="$1"
    local msg="$2"
    local h="${3:-10}"
    local w="${4:-60}"
    local default="$5"
    if [ -n "$title" ]; then
        whiptail --title "$title" --inputbox "$msg" "$h" "$w" "$default" 3>&1 1>/dev/tty 2>&3
    else
        whiptail --inputbox "$msg" "$h" "$w" "$default" 3>&1 1>/dev/tty 2>&3
    fi
}

whiptail_password() {
    local title="$1"
    local msg="$2"
    local h="${3:-10}"
    local w="${4:-60}"
    if [ -n "$title" ]; then
        whiptail --title "$title" --passwordbox "$msg" "$h" "$w" 3>&1 1>/dev/tty 2>&3
    else
        whiptail --passwordbox "$msg" "$h" "$w" 3>&1 1>/dev/tty 2>&3
    fi
}

whiptail_checklist() {
    local title="$1"
    local msg="$2"
    local h="$3"
    local w="$4"
    local lh="$5"
    shift 5
    if [ -n "$title" ]; then
        whiptail --title "$title" --checklist "$msg" "$h" "$w" "$lh" "$@" 3>&1 1>/dev/tty 2>&3
    else
        whiptail --checklist "$msg" "$h" "$w" "$lh" "$@" 3>&1 1>/dev/tty 2>&3
    fi
}

whiptail_checklist_sep() {
    local title="$1"
    local msg="$2"
    local h="$3"
    local w="$4"
    local lh="$5"
    shift 5
    if [ -n "$title" ]; then
        whiptail --title "$title" --separate-output --checklist "$msg" "$h" "$w" "$lh" "$@" 3>&1 1>/dev/tty 2>&3
    else
        whiptail --separate-output --checklist "$msg" "$h" "$w" "$lh" "$@" 3>&1 1>/dev/tty 2>&3
    fi
}

whiptail_menu() {
    local title="$1"
    local msg="$2"
    local h="$3"
    local w="$4"
    local lh="$5"
    shift 5
    if [ -n "$title" ]; then
        whiptail --title "$title" --menu "$msg" "$h" "$w" "$lh" "$@" 3>&1 1>/dev/tty 2>&3
    else
        whiptail --menu "$msg" "$h" "$w" "$lh" "$@" 3>&1 1>/dev/tty 2>&3
    fi
}
# ----------------------------------

# Check that we have sudo 
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script as root (use sudo)."
    exit 1
fi

# Generate timestamp for this run
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

LOGDIR="/var/log/bootstrap"
LOGFILE="${LOGDIR}/bootstrap-${TIMESTAMP}.log"

mkdir -p "$LOGDIR"
touch "$LOGFILE"
chmod 600 "$LOGFILE"

ln -sf "$LOGFILE" "${LOGDIR}/bootstrap-latest.log"

# Redirect all output
exec > >(awk '{ print strftime("[%Y-%m-%d %H:%M:%S]"), $0; fflush(); }' | tee -a "$LOGFILE") 2>&1

# Error + exit handling
trap 'echo "ERROR: Script failed at line $LINENO with exit code $?"' ERR
trap 'echo "===== Bootstrap finished at $(date) ====="' EXIT

# Debug tracing
if [[ "$DEBUG" == "1" ]]; then
    # The :- construct prevents "unbound variable" errors
    PS4='+ $(date "+%Y-%m-%d %H:%M:%S") [${BASH_SOURCE[0]:-stdin}:${LINENO}] '
    set -x
fi

echo "Logging to: ${LOGFILE}"
echo "===== Bootstrap started at $(date) ====="
echo "User: $(whoami)"
echo "Hostname: $(hostname)"

# Welcome Message
whiptail_msgbox "Cam's VPS Bootstrap" "This script will prepare a fresh linux instance.\n\nTarget: Any Debian or Ubunutu Instance" 15 60

# The Checklist Menu
# The syntax for checklist is: [tag] [item] [status (on/off)]
RESULTS=$(
    whiptail_checklist "Cams's Bootstrap" \
    "Spacebar to select/deselect, Enter to confirm:" 22 75 14 \
    "UPDATE"     "Update system (apt update/upgrade)" OFF \
    "TIME"       "Set timezone" OFF \
    "AUTO"       "Enable unattended-upgrades & needrestart" OFF \
    "HOST"       "Set hostname" OFF \
    "USER"       "Add non-root user" OFF \
    "KEYS"       "Add/manage SSH public keys" OFF \
    "SSH"        "Harden SSH" OFF \
    "UFW"        "Install and configure UFW (NOT FOR OCI)" OFF \
    "TS"         "Install and configure Tailscale" OFF \
    "DOCKER"     "Install Docker" OFF \
    "GIT"        "Install Git" OFF \
    "LOGS"       "Configure journald log retention" OFF \
    "SERVICES"   "Disable unneeded services" OFF \
    "CONVENIENCE" "Install useful admin tools" OFF
) || {
    echo "Setup cancelled by user."
    exit 0
}

# Initialize variables (Default to false)
DO_UPDATE=false; DO_TIME=false; DO_AUTO=false; DO_HOST=false; 
DO_USER=false; DO_KEYS=false; DO_SSH=false; DO_UFW=false; 
DO_TS=false; DO_DOCKER=false; DO_GIT=false; DO_LOGS=false; 
DO_SERVICES=false; DO_CONVENIENCE=false;

# Parse the results
# Whiptail returns a string like: "UPDATE" "TIME" "TS"
# We check if the tag exists in the RESULTS string
# Match full tokens including quotes to avoid substring bugs
[[ $RESULTS == *'"UPDATE"'* ]]      && DO_UPDATE=true
[[ $RESULTS == *'"TIME"'* ]]        && DO_TIME=true
[[ $RESULTS == *'"AUTO"'* ]]        && DO_AUTO=true
[[ $RESULTS == *'"HOST"'* ]]        && DO_HOST=true
[[ $RESULTS == *'"USER"'* ]]        && DO_USER=true
[[ $RESULTS == *'"KEYS"'* ]]        && DO_KEYS=true
[[ $RESULTS == *'"SSH"'* ]]         && DO_SSH=true
[[ $RESULTS == *'"UFW"'* ]]         && DO_UFW=true
[[ $RESULTS == *'"TS"'* ]]          && DO_TS=true
[[ $RESULTS == *'"DOCKER"'* ]]      && DO_DOCKER=true
[[ $RESULTS == *'"GIT"'* ]]         && DO_GIT=true
[[ $RESULTS == *'"LOGS"'* ]]        && DO_LOGS=true
[[ $RESULTS == *'"SERVICES"'* ]]    && DO_SERVICES=true
[[ $RESULTS == *'"CONVENIENCE"'* ]] && DO_CONVENIENCE=true

# Sanity Check (Echo the list)
echo "------------------------------------------"
echo "USER SELECTIONS:"
echo "Update System:				$DO_UPDATE"
echo "Set Timezone:					$DO_TIME"
echo "Auto Upgrades:				$DO_AUTO"
echo "Set Hostname:					$DO_HOST"
echo "Add User:						$DO_USER"
echo "Add SSH Keys:					$DO_KEYS"
echo "Harden SSH:					$DO_SSH"
echo "Install UFW:					$DO_UFW"
echo "Install Tailscale:			$DO_TS"
echo "Install Docker:				$DO_DOCKER"
echo "Install Git:					$DO_GIT"
echo "Configure logs:				$DO_LOGS"
echo "Remove services:				$DO_SERVICES"
echo "Install convenience software:	$DO_CONVENIENCE" 
echo "------------------------------------------"

# Confirmation (Yes/No Box)
if whiptail_yesno "Confirm" "Proceed with installation?" 8 45; then
    echo "Starting deployment..."
else
    echo "User aborted."
    exit 1
fi

# --- Execution Starts Here ---

if [ "$DO_UPDATE" = true ]; then
	echo "--- Starting System Updates ---"
	
	ensure_apt_updated
	
	echo "Upgrading packages"
	apt-get dist-upgrade -y

	echo "Cleaning up unused packages"
	apt-get autoremove -y
	
	echo "--- Installing core software ---"
    apt_install curl wget sudo
fi

if [ "$DO_TIME" = true ]; then
    echo "--- Setting timezone ---"

    TIMEZONE=$(
        whiptail_input "Set Timezone" \
        "Enter your desired timezone.\n\nFormat: Region/City (e.g. Pacific/Auckland, Europe/London, UTC)\n\nFull list: https://en.wikipedia.org/wiki/List_of_tz_database_time_zones" \
        12 65 "$TIMEZONE"
    ) || {
        echo "No timezone entered, using default: $TIMEZONE"
    }

    timedatectl set-timezone "$TIMEZONE"
    timedatectl set-ntp true
	
	echo "New Timezone setting:"
	timedatectl status
	
    echo "--- Timezone configuration complete ---"
fi

if [ "$DO_AUTO" = true ]; then
    echo "--- Starting Auto Update configuration ---"
    echo "--- Installing required update software: unattended-upgrades, needrestart ---"
    apt_install unattended-upgrades needrestart

    REBOOT_TIME=$(
        whiptail_input "Auto Update Reboot Time" \
        "Enter the time for automatic reboots after updates.\n\nFormat: HH:MM in 24-hour time.\n\nNote: This only applies if updates require a reboot." \
        12 60 "$REBOOT_TIME"
    ) || {
        echo "No reboot time entered, using default: $REBOOT_TIME"
		#maybe this should be changed to exit to match the rest of the script behaviour (cancel = exit immediately)?
    }

    # Using '>' ensures we overwrite any old config in this file
    cat <<EOF > /etc/apt/apt.conf.d/99-unattended-upgrades-cams-bootstrap
// Overwritten by Cam's Bootstrap Script
// Manual changes here will be lost if the bootstrap script is run again
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-WithUsers "false";
Unattended-Upgrade::Automatic-Reboot-Time "$REBOOT_TIME";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Remove-New-Unused-Dependencies "true";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
EOF

    install -d -m 755 /etc/needrestart/conf.d
    cat <<EOF > /etc/needrestart/conf.d/cams-bootstrap.conf
# Managed by Cam's Bootstrap Script
\$nrconf{restart} = 'a';
EOF

    echo "--- Auto Update configuration complete ---"
fi

if [ "$DO_HOST" = true ]; then
	echo "--- Starting Hostname configuration ---"
	
	NEW_HOSTNAME=$(hostnamectl --static 2>/dev/null || hostname) # Grab the current hostname as the 'default'
	
    while true; do
        NEW_HOSTNAME=$(whiptail_input "" "Enter hostname (current shown):" 10 60 "$NEW_HOSTNAME") || {
            echo "Hostname entry cancelled. Exiting."
            exit 1
        }

        # Check empty
        if [ -z "$NEW_HOSTNAME" ]; then
            whiptail_msgbox "" "Hostname cannot be empty." 8 40
            continue
        fi

        # Validate format (simple, safe subset)
        if ! [[ "$NEW_HOSTNAME" =~ ^[a-z0-9-]+$ ]]; then
            whiptail_msgbox "" "Invalid hostname. Use only lowercase letters, numbers, and hyphens." 8 60
            continue
        fi

        # Optional: stricter rules (recommended)
        if [[ "$NEW_HOSTNAME" =~ ^- || "$NEW_HOSTNAME" =~ -$ ]]; then
            whiptail_msgbox "" "Hostname cannot start or end with a hyphen." 8 60
            continue
        fi

        if [ ${#NEW_HOSTNAME} -gt 63 ]; then
            whiptail_msgbox "" "Hostname must be 63 characters or less." 8 60
            continue
        fi

        # If we got here, it's valid
        break
    done
	
	hostnamectl set-hostname "$NEW_HOSTNAME"	
    if grep -qE '^127\.0\.1\.1\s+' /etc/hosts; then
        sed -i -E "s/^127\.0\.1\.1\s+.*/127.0.1.1\t$NEW_HOSTNAME/" /etc/hosts
    else
        printf '127.0.1.1\t%s\n' "$NEW_HOSTNAME" >> /etc/hosts
    fi
	
	echo "Hostname set to: $NEW_HOSTNAME"
fi

# Need to compare with chatgpts suggestion
if [ "$DO_USER" = true ]; then
	echo "--- Creating new user ---"	

    # Prompt for username (with default)
	if ! NEW_USER=$(whiptail_input "" "Enter new username:" 10 60 "$NEW_USER"); then
		echo "User creation cancelled."
		exit 0
	fi

    if id "$NEW_USER" >/dev/null 2>&1; then
        echo "User $NEW_USER already exists, skipping creation."
    else
        useradd -m -s /bin/bash -c "Created with Cam's bootstrap script" "$NEW_USER"

        # --- Password input + validation loop ---
		while true; do
			if ! PASSWORD1=$(whiptail_password "" "Enter password for $NEW_USER (min 8 chars):" 10 60); then
				echo "User creation cancelled."
				exit 0
			fi

			if ! PASSWORD2=$(whiptail_password "" "Confirm password:" 10 60); then
				echo "User creation cancelled."
				exit 0
			fi

			if [ -z "$PASSWORD1" ]; then 
				whiptail_msgbox "" "Password cannot be empty. Try again." 8 40
				continue
			fi

			if [ ${#PASSWORD1} -lt 8 ]; then
				whiptail_msgbox "" "Password must be at least 8 characters long. Try again." 8 50
				continue
			fi

			if [ "$PASSWORD1" != "$PASSWORD2" ]; then
				whiptail_msgbox "" "Passwords do not match. Try again." 8 50
				continue
			fi

			break
		done

        echo "$NEW_USER:$PASSWORD1" | chpasswd
		unset PASSWORD1 PASSWORD2 # Remove plain text passwords from memory
        usermod -aG sudo "$NEW_USER" # Add to sudo group

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
            
            if whiptail_yesno "Transfer SSH Keys" "Found existing key for $REAL_USER:\n\n$KEY_INFO\n\nTransfer this to $NEW_USER?" 12 60; then
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

# Need to compare with chatgpts suggestion
if [ "$DO_KEYS" = true ]; then
    echo "--- Starting SSH key configuration ---"

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
		if ! TARGET_USER=$(whiptail_menu "Select User" "Select a user to modify keys, or 'DONE' to continue." 15 60 6 "${USER_OPTIONS[@]}"); then
			echo "SSH Key addition cancelled. Stopping script here."
			exit 0
		fi
	
		if [ "$TARGET_USER" = "DONE" ]; then break; fi

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
            SELECTED_KEYS=$(whiptail_checklist_sep "Manage Existing Keys" \
            "Uncheck keys to DELETE them. Press Space to toggle, Enter to confirm." 15 70 6 "${CHECKLIST_ITEMS[@]}")

            if [ $? -eq 0 ]; then
                echo "$SELECTED_KEYS" > "$AUTH_KEYS"
                echo "Keys updated for $TARGET_USER."
            fi
        fi

        # 4. Display Current Status
        if [ -s "$AUTH_KEYS" ]; then
            KEY_SUMMARY=$(awk '{print "Type: " $1 " | Comment: " $3}' "$AUTH_KEYS")
            whiptail_msgbox "Existing Keys for $TARGET_USER" "Current active keys:\n\n$KEY_SUMMARY" 15 70
        else
            whiptail_msgbox "Keys Status" "No keys currently exist for $TARGET_USER." 8 50
        fi

        # 5. Key Addition Loop
        while true; do
            if ! whiptail_yesno "Add New Key" "Would you like to ADD a new SSH key for $TARGET_USER?" 8 50; then
                break
            fi

            PASTED_KEY=$(whiptail_input "Add SSH Key" "Paste public key (ssh-rsa, ed25519, etc.):" 10 70 "")
            
            if [ -n "$PASTED_KEY" ]; then
                TEMP_KEY=$(mktemp)
                echo "$PASTED_KEY" > "$TEMP_KEY"
                if ssh-keygen -l -f "$TEMP_KEY" >/dev/null 2>&1; then
                    echo "$PASTED_KEY" >> "$AUTH_KEYS"
                    whiptail_msgbox "" "Key added successfully!" 8 40
                else
                    whiptail_msgbox "" "Invalid key format. Skipping." 8 40
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

# Needs work on the tmux part. Maybe that should have its own section?
# SSH Hardening
if [ "$DO_SSH" = true ]; then
	# add whiptail yes no for do you want to install Tmux for persistent SSH sessions?
	echo "--- Installing Tmux for persistent SSH sessions ---"
	apt_install tmux
	
	
	# Inject Tmux auto-attach into .bashrc safely (interactive SSH sessions only)
#    if ! grep -q "tmux attach-session" /home/"$NEW_USER"/.bashrc; then
#        cat << 'EOF' >> /home/"$NEW_USER"/.bashrc
#
# Auto-attach to tmux for interactive SSH sessions
# if [[ $- =~ i ]] && [[ -z "$TMUX" ]] && [[ -n "$SSH_TTY" ]]; then
#    tmux attach-session -t default || tmux new-session -s default
# fi
# EOF
#    fi
	
	
	
	install -d -m 755 /etc/ssh/sshd_config.d
	cat <<EOF > /etc/ssh/sshd_config.d/99-hardening-cams-bootstrap.conf
PasswordAuthentication no
PermitRootLogin no
PubkeyAuthentication yes
PermitEmptyPasswords no
KbdInteractiveAuthentication no
X11Forwarding no         # Disable GUI remoting to reduce attack surface
AuthenticationMethods publickey

# Connection Stability & Cleanup
TCPKeepAlive yes         # Detect if the remote hardware/network has physically failed
ClientAliveInterval 300  # Send encrypted 'are you there?' heartbeat every 5 mins
ClientAliveCountMax 2    # Terminate if 2 heartbeats are missed (cleans up ghost sessions)
EOF
	
	# Validate syntax before reloading
    if command -v sshd >/dev/null 2>&1 && sshd -t; then
        systemctl reload ssh 2>/dev/null
        echo "SSH hardening applied and service reloaded."
    else
        whiptail_msgbox "" "SSH configuration syntax error. SSH has not been reloaded." 10 60
        echo "SSH configuration syntax error. SSH has not been reloaded."
    fi
fi

# Safety check logic. This checks if any of the 'danger' sections were run
if [ "$DO_USER" = true ] || [ "$DO_KEYS" = true ] || [ "$DO_SSH" = true ]; then
    
    # Define the warning message
    WARNING_MSG="WARNING: SSH settings or users have been modified.\n\n"
    WARNING_MSG+="Please start another INDEPENDENT SSH session now and ensure you can still log in.\n\n"
    WARNING_MSG+="DO NOT terminate this current session until you are 100% confident that your new users, keys, and hardening settings are functioning.\n\n"
    WARNING_MSG+="If you are locked out, you can still use this open window to fix permissions or revert changes.\n\n"
    WARNING_MSG+="Press YES to continue with remaining bootstrap tasks, or NO to abort the script immediately."

    # Display the Whiptail Warning
    if whiptail_yesno "Warning: SSH Settings Modified" "$WARNING_MSG" 20 150; then
        echo "User acknowledged SSH changes. Continuing with bootstrap..."
    else
        echo "Bootstrap aborted by user to verify SSH connectivity."
        exit 1
    fi
fi

if [ "$DO_LOGS" = true ]; then
    echo "--- Configuring systemd journal log management ---"
	install -d -m 755 /etc/systemd/journald.conf.d	# create the folder if it doesn't exist
    cat <<EOF > /etc/systemd/journald.conf.d/cams-bootstrap.conf
[Journal]
# Cap total disk usage for logs
SystemMaxUse=500M
# Soft limit - start rotating before hitting the hard cap
SystemKeepFree=200M
# Max size of a single journal file before rotation
SystemMaxFileSize=50M
# Retain logs for a maximum of 4 weeks
MaxRetentionSec=4weeks
# Compress journal files
Compress=yes
EOF
    systemctl reload systemd-journald || true
    journalctl --vacuum-size=500M || true
    journalctl --vacuum-time=4weeks || true
    echo "--- Log management configuration complete ---"
fi

# Don't use UFW if on OCI because OCI sets the defaults up with iptables and iptables-persistent - we can just leave it as is
if [ "$DO_UFW" = true ]; then
    echo "Installing UFW and setting default rules..."
    apt_install ufw
	ufw default deny incoming
	ufw default allow outbound
	ufw allow 22/tcp
    ufw --force enable	
fi

if [ "$DO_TS" = true ]; then
	echo "--- Installing Tailscale ---"
	
	# 1. Capture Auth Key (Optional)
	TS_AUTHKEY=$(whiptail_password "Tailscale Auth" "Enter your Tailscale Auth Key (leave blank for manual auth link):" 10 65) || true
	TS_AUTHKEY=$(echo "$TS_AUTHKEY" | xargs) # Trim whitespace and newlines

	# 2. Run official install script	
	curl -fsSL https://tailscale.com/install.sh | sh 
	until tailscale status >/dev/null 2>&1; do
		echo "Waiting for TasilScale to be responsive. Could be a firewall issue"
		sleep 1
	done
	
	# 3. Bring Tailscale up
    if [ -n "$TS_AUTHKEY" ]; then
        tailscale up --authkey="$TS_AUTHKEY" --ssh --accept-dns=true# turning on TS SSH should always be a good thing
    else
        echo "No Auth Key provided. Please follow the link above to authenticate."
        tailscale up --ssh --accept-dns=true|| echo "WARNING: tailscale up may have failed"
    fi

    # Firewall logic removed. Tailscale can handle it's own rules for UFW or iptables
fi

if [ "$DO_DOCKER" = true ]; then
	echo "--- Installing Docker ---"
	curl -fsSL https://get.docker.com | sh
	# Make a home for docker stacks -p create parent directories and will not error is this directory already exists
	mkdir -p "$STACK_DIR" #should we be using install rather than mkdir like in do_logs section?
	echo "Docker install complete. Add your stacks to: $STACK_DIR"
fi

# Needs work
if [ "$DO_GIT" = true ]; then
	# Add optional install for git (for downloaded/version controlling docker compose files)
	# Whiptail boxes to enter user data?
	apt_install git
	# echo git installed version xxxx
fi

if [ "$DO_SERVICES" = true ]; then
    echo "Starting service hardening..."

    if ! SERVICE_CHOICES=$(whiptail_checklist "Disable Unneeded Services" \
        "Select services to disable (SPACE to toggle, ENTER to confirm):" \
        28 76 15 \
        "bluetooth"      "Bluetooth stack" ON \
        "cups"           "Printing service" ON \
        "cups-browsed"   "Network printer discovery" ON \
        "avahi-daemon"   "mDNS / Bonjour discovery" ON \
        "ModemManager"   "Mobile broadband modems" ON \
        "wpa_supplicant" "Wi-Fi auth helper" ON \
        "snapd"          "Snap package daemon" OFF \
        "multipathd"     "Disk multipath" ON \
        "apport"         "Ubuntu crash reporting" ON \
        "whoopsie"       "Ubuntu error reporting" ON \
        "motd-news"      "Fetches MOTD news" ON \
        "iscsid"         "iSCSI initiator" OFF); then

        echo "Skipping service hardening."
    else
        if [ -n "$SERVICE_CHOICES" ]; then
            mapfile -t SERVICES_TO_DISABLE < <(printf '%s\n' "$SERVICE_CHOICES" | tr -d '"')
            for service in "${SERVICES_TO_DISABLE[@]}"; do
                if systemctl is-enabled "$service" >/dev/null 2>&1; then
                    echo "Disabling: $service"
                    systemctl disable --now "$service" || true
                else
                    echo "Skipping $service (not enabled or not installed)"
                fi
            done
            echo "Service hardening complete."
        else
            echo "No services selected."
        fi
    fi
fi

if [ "$DO_CONVENIENCE" = true ]; then
    echo "Installing convenience tools..."

    if ! CONVENIENCE_CHOICES=$(whiptail_checklist "Install Convenience Tools" \
        "Select tools to install (SPACE to toggle, ENTER to confirm):" \
        28 72 12 \
        "htop"        "Interactive process viewer - better than top"              ON  \
        "ncdu"        "Disk usage analyser - find what's eating your space"       ON  \
        "curl"        "HTTP client - essential for scripts and API calls"         ON  \
        "wget"        "File downloader - complements curl"                        ON  \
        "fail2ban"    "Bans IPs with repeated failed logins"                      ON  \
        "net-tools"   "ifconfig, netstat etc - old but handy for debugging"       OFF \
        "glances"     "Richer system dashboard - heavier than htop"               OFF \
        "tree"        "Visual directory tree - small but handy"                   ON); then

        echo "Skipping convenience tools."
    else
        if [ -n "$CONVENIENCE_CHOICES" ]; then
            mapfile -t CONVENIENCE_TO_INSTALL < <(printf '%s\n' "$CONVENIENCE_CHOICES" | tr -d '"')
            if [ ${#CONVENIENCE_TO_INSTALL[@]} -gt 0 ]; then
                echo "Installing: ${CONVENIENCE_TO_INSTALL[*]}"
                apt_install "${CONVENIENCE_TO_INSTALL[@]}"
                echo "Convenience tools installation complete."
            else
                echo "No tools selected."
            fi
        else
            echo "No tools selected."
        fi
    fi
fi

whiptail_msgbox "Success" "Bootstrap Complete!" 12 60
echo "--- Bootstrap Complete! ---"

if [ -f /var/run/reboot-required ]; then
	if whiptail_yesno "Reboot Required" "Kernel or core library updates were installed.\n\nWould you like to reboot the server now?" 10 55; then
        unset NEWT_COLORS
		echo "Rebooting system..."
        reboot
    fi
	echo "Reboot pending..."
fi

unset NEWT_COLORS

exit 0