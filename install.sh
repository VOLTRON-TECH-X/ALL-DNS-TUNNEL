#!/bin/bash

# ========== VOLTRON TECH X INSTALLER v1.0 ==========
# Description: One-click installer for VOLTRON TECH X
# Author: Voltron Tech
# Repository: https://github.com/VOLTRON-TECH-X/ALL-DNS-TUNNEL

# ========== COLOR CODES ==========
C_RESET='\033[0m'
C_RED='\033[91m'
C_GREEN='\033[92m'
C_YELLOW='\033[93m'
C_BLUE='\033[94m'
C_PURPLE='\033[95m'
C_CYAN='\033[96m'

# ========== CHECK ROOT ==========
if [[ $EUID -ne 0 ]]; then
   echo -e "${C_RED}❌ Error: This script must be run as root.${C_RESET}"
   echo -e "${C_YELLOW}👉 Try: sudo bash $0${C_RESET}"
   exit 1
fi

# ========== BANNER ==========
clear
echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_PURPLE}           🔥 VOLTRON TECH X INSTALLER 🔥                      ${C_RESET}"
echo -e "${C_PURPLE}           📡 DNSTT • SLIPSTREAM • VAYDNS • NOIZDNS            ${C_RESET}"
echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
echo ""

# ========== DETECT PACKAGE MANAGER ==========
echo -e "${C_YELLOW}🔍 Detecting system...${C_RESET}"
if command -v apt &>/dev/null; then
    PKG_MANAGER="apt"
    UPDATE_CMD="apt update"
    INSTALL_CMD="apt install -y"
    echo -e "${C_GREEN}✅ Detected: apt (Debian/Ubuntu)${C_RESET}"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
    UPDATE_CMD="dnf check-update"
    INSTALL_CMD="dnf install -y"
    echo -e "${C_GREEN}✅ Detected: dnf (Fedora/RHEL)${C_RESET}"
elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
    UPDATE_CMD="yum check-update"
    INSTALL_CMD="yum install -y"
    echo -e "${C_GREEN}✅ Detected: yum (CentOS)${C_RESET}"
else
    echo -e "${C_RED}❌ No supported package manager found!${C_RESET}"
    exit 1
fi

# ========== INSTALL DEPENDENCIES ==========
echo -e "${C_YELLOW}📦 Installing dependencies (curl, wget, bc)...${C_RESET}"
$UPDATE_CMD > /dev/null 2>&1
$INSTALL_CMD curl wget bc > /dev/null 2>&1

# Check if dependencies installed successfully
if ! command -v curl &>/dev/null; then
    echo -e "${C_RED}❌ Failed to install curl. Please install manually.${C_RESET}"
    exit 1
fi

echo -e "${C_GREEN}✅ Dependencies installed${C_RESET}"

# ========== DOWNLOAD MAIN SCRIPT ==========
MAIN_SCRIPT_URL="https://raw.githubusercontent.com/VOLTRON-TECH-X/ALL-DNS-TUNNEL/refs/heads/main/main.sh"
INSTALL_PATH="/usr/local/bin/voltron"

echo -e "${C_YELLOW}⬇️ Downloading VOLTRON TECH X main script...${C_RESET}"

if command -v wget &>/dev/null; then
    wget -q --show-progress -O "$INSTALL_PATH" "$MAIN_SCRIPT_URL"
elif command -v curl &>/dev/null; then
    curl -s -L -o "$INSTALL_PATH" "$MAIN_SCRIPT_URL"
else
    echo -e "${C_RED}❌ Neither wget nor curl found!${C_RESET}"
    exit 1
fi

if [ $? -ne 0 ] || [ ! -s "$INSTALL_PATH" ]; then
    echo -e "${C_RED}❌ Download failed! Check your internet connection.${C_RESET}"
    exit 1
fi

chmod +x "$INSTALL_PATH"
echo -e "${C_GREEN}✅ Main script downloaded to $INSTALL_PATH${C_RESET}"

# ========== CREATE MENU COMMAND ==========
ln -sf "$INSTALL_PATH" /usr/local/bin/menu 2>/dev/null
echo -e "${C_GREEN}✅ Created command: 'voltron' and 'menu'${C_RESET}"

# ========== RUN INITIAL SETUP ==========
echo -e "${C_YELLOW}⚙️ Running initial setup...${C_RESET}"
"$INSTALL_PATH" --install-setup

# ========== SHOW COMPLETION ==========
clear
echo -e "${C_GREEN}═══════════════════════════════════════════════════════════════${C_RESET}"
echo -e "${C_GREEN}           ✅ VOLTRON TECH X INSTALLED SUCCESSFULLY!          ${C_RESET}"
echo -e "${C_GREEN}═══════════════════════════════════════════════════════════════${C_RESET}"
echo ""
echo -e "  ${C_CYAN}📌 To start, type:${C_RESET}"
echo -e "     ${C_YELLOW}voltron${C_RESET}  or  ${C_YELLOW}menu${C_RESET}"
echo ""
echo -e "  ${C_CYAN}📌 Quick commands:${C_RESET}"
echo -e "     ${C_YELLOW}[1]${C_RESET} Tunnel     - Add/List DNS tunnels"
echo -e "     ${C_YELLOW}[2]${C_RESET} SOCKS5 Mgmt - Manage SOCKS5 users"
echo -e "     ${C_YELLOW}[3]${C_RESET} SSH Mgmt    - Manage SSH users"
echo -e "     ${C_YELLOW}[10]${C_RESET} Speed Booster - Optimize DNSTT speed"
echo ""
echo -e "  ${C_CYAN}📌 Support:${C_RESET}"
echo -e "     ${C_GREEN}GitHub: https://github.com/VOLTRON-TECH-X/ALL-DNS-TUNNEL${C_RESET}"
echo ""
echo -e "${C_GREEN}═══════════════════════════════════════════════════════════════${C_RESET}"
