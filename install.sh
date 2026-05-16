#!/bin/bash

# ========== VOLTRON TECH X INSTALLER ==========
# This script downloads and installs the main script

# ========== COLOR CODES ==========
RED='\033[91m'
GREEN='\033[92m'
YELLOW='\033[93m'
BLUE='\033[94m'
CYAN='\033[96m'
NC='\033[0m'

# ========== CHECK ROOT ==========
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ Error: This script must be run as root.${NC}"
   exit 1
fi

# ========== BANNER ==========
clear
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}           🔥 VOLTRON TECH X INSTALLER 🔥                      ${NC}"
echo -e "${BLUE}═══════════════════════════════════════════════════════════════${NC}"
echo ""

# ========== DETECT PACKAGE MANAGER ==========
echo -e "${YELLOW}🔍 Detecting system...${NC}"
if command -v apt &>/dev/null; then
    PKG_MANAGER="apt"
    echo -e "${GREEN}✅ Detected: apt (Debian/Ubuntu)${NC}"
elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
    echo -e "${GREEN}✅ Detected: dnf (Fedora/RHEL)${NC}"
elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
    echo -e "${GREEN}✅ Detected: yum (CentOS)${NC}"
else
    echo -e "${RED}❌ No supported package manager found!${NC}"
    exit 1
fi

# ========== INSTALL DEPENDENCIES ==========
echo -e "${YELLOW}📦 Installing dependencies (curl, wget)...${NC}"
if [ "$PKG_MANAGER" = "apt" ]; then
    apt update
    apt install -y curl wget
elif [ "$PKG_MANAGER" = "dnf" ]; then
    dnf install -y curl wget
elif [ "$PKG_MANAGER" = "yum" ]; then
    yum install -y curl wget
fi

# ========== DOWNLOAD MAIN SCRIPT ==========
MAIN_SCRIPT_URL="https://raw.githubusercontent.com/VOLTRON-TECH-X/VOLTRON-TECH-X/refs/heads/main/main.sh"
INSTALL_PATH="/usr/local/bin/voltron"

echo -e "${YELLOW}⬇️ Downloading VOLTRON TECH X main script...${NC}"
if command -v wget &>/dev/null; then
    wget -q --show-progress -O "$INSTALL_PATH" "$MAIN_SCRIPT_URL"
elif command -v curl &>/dev/null; then
    curl -L -o "$INSTALL_PATH" "$MAIN_SCRIPT_URL"
else
    echo -e "${RED}❌ Neither wget nor curl found!${NC}"
    exit 1
fi

if [ $? -ne 0 ] || [ ! -s "$INSTALL_PATH" ]; then
    echo -e "${RED}❌ Download failed! Check your internet connection.${NC}"
    exit 1
fi

chmod +x "$INSTALL_PATH"

# ========== CREATE MENU COMMAND ==========
ln -sf "$INSTALL_PATH" /usr/local/bin/menu 2>/dev/null

# ========== RUN INITIAL SETUP ==========
echo -e "${YELLOW}⚙️ Running initial setup (installing ULTIMATE BOOSTER)...${NC}"
"$INSTALL_PATH" --install-setup

# ========== SHOW COMPLETION ==========
clear
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}           ✅ VOLTRON TECH X INSTALLED SUCCESSFULLY!          ${NC}"
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
echo ""
echo -e "  ${CYAN}➡️ Type '${YELLOW}voltron${CYAN}' or '${YELLOW}menu${CYAN}' to start${NC}"
echo -e "  ${CYAN}➡️ For MTU 1800 on slow networks, choose:${NC}"
echo -e "     ${YELLOW}Main Menu → Protocols & Panels (8) → DNSTT (1) → Install → MTU 1800${NC}"
echo ""
echo -e "${GREEN}═══════════════════════════════════════════════════════════════${NC}"
