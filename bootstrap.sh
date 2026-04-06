#!/bin/bash
# ==============================================================================
# Cam's Interactive VPS Bootstrap
# Uses whiptail for that "Proxmox-style" feel.
# Run this by running the command below in the shell:
# bash -c "$(curl -fsSL https://raw.githubusercontent.com/walkercam/selfhosted/refs/heads/main/bootstrap.sh)"
# ==============================================================================

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

# 1. Welcome Message
whiptail --title "Cam's VPS Bootstrap" --msgbox "This script will prepare a fresh linux instance.\n\nTarget: Any Debian or Ubunutu Instance" 12 60

# 2. Interactive Menu
# We swap file descriptors 3 and 1 to capture the result of the menu
CHOICE=$(whiptail --title "Setup Options" --menu "Choose your configuration:" 15 60 4 \
"1" "Standard OCI (No UFW, Safe for Boot Volumes)" \
"2" "Generic VPS (Enables UFW - NOT FOR OCI)" \
"3" "Minimal (No Firewall/Tailscale)" \
"4" "Exit" 3>&1 1>&2 2>&3)

# If the user hits 'Cancel' or 'Esc', whiptail returns a non-zero exit code
if [ $? -ne 0 ] || [ "$CHOICE" = "4" ]; then
    echo "Setup cancelled by user."
    exit 0
fi

# 3. Logic based on selection
case $CHOICE in
    1)
        USE_UFW=false
        INSTALL_TAILSCALE=true
        echo "Selected: Standard OCI Mode"
        ;;
    2)
        USE_UFW=true
        INSTALL_TAILSCALE=true
        echo "Selected: Generic VPS Mode"
        ;;
    3)
        USE_UFW=false
        INSTALL_TAILSCALE=false
        echo "Selected: Minimal Mode"
        ;;
esac

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
apt-get update && apt-get upgrade -y
apt-get install -y curl jq iptables-persistent

if [ "$USE_UFW" = true ]; then
    echo "Installing UFW and setting default rules..."
    apt-get install -y ufw
	ufw allow 22/tcp
    ufw allow in on tailscale0
    ufw --force enable	
else
        echo "Running OCI Safe Setup..."
        # We don't touch UFW here to protect OCI boot volumes
        netfilter-persistent save
fi

if [ "$INSTALL_TAILSCALE" = true ]; then
	echo "--- Installing Tailscale ---"
	curl -fsSL https://tailscale.com/install.sh | sh
fi

if [ "$INSTALL_DOCKER" = true ]; then
	echo "--- Installing Docker ---"
	curl -fsSL https://get.docker.com | sh
	# Make a home for docker stacks
	mkdir -p /opt/stacks/
fi

whiptail --title "Success" --msgbox "Bootstrap Complete!\n\nNext Steps:\n1. sudo tailscale up\n2. Deploy stacks to /opt/stacks" 12 60

unset NEWT_COLORS



