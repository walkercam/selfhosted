#!/bin/bash
# ==============================================================================
# Cam's Interactive VPS Bootstrap
# Uses whiptail for that "Proxmox-style" feel.
# ==============================================================================

# 1. Welcome Message
whiptail --title "Cam's VPS Bootstrap" --msgbox "This script will prepare a fresh linux instance.\n\nTarget: Any Debian or Ubunutu Instance" 12 60

# 2. Interactive Menu
# We swap file descriptors 3 and 1 to capture the result of the menu
CHOICE=$(whiptail --title "Setup Options" --menu "Choose your configuration:" 15 60 4 \
"1" "Standard OCI (No UFW, Safe for Boot Volumes)" \
"2" "Generic VPS (Enables UFW - NOT FOR OCI)" \
"3" "Minimal (No Firewall/Tailscale)" \
"4" "Exit" 3>&1 1>&2 2>&3)

exit_status=$?
if [ $exit_status -ne 0 ]; then
    echo "Setup cancelled."
    exit 1
fi

# 3. Logic based on selection
case $CHOICE in
    1)
        USE_UFW=false
        INSTALL_TAILSCALE=true
        ;;
    2)
        USE_UFW=true
        INSTALL_TAILSCALE=true
        ;;
    3)
        USE_UFW=false
        INSTALL_TAILSCALE=false
        ;;
    4)
        exit 0
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
export DEBIAN_FRONTEND=noninteractive
apt-get update && apt-get upgrade -y

# [Add the rest of your logic here...]