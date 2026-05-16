#!/bin/bash

# ============================================================================
# VOLTRON GATE v6.0 (Slipgate Official + deSEC + Speed Boosters + Full User Mgmt)
# - Inatumia Slipgate rasmi (binary zake zinafanya kazi)
# - deSEC auto domain (token yako, domain yako)
# - Speed boosters kwa DNSTT / NoizDNS (kernel tweaks)
# - SSH na SOCKS5 user managers (expiry, connection limit, bandwidth)
# - Auto SSH banner (Falcon style)
# ============================================================================

C_RESET='\033[0m'
C_RED='\033[91m'
C_GREEN='\033[92m'
C_YELLOW='\033[93m'
C_BLUE='\033[94m'
C_PURPLE='\033[95m'
C_CYAN='\033[96m'
C_WHITE='\033[97m'
C_ORANGE='\033[38;5;208m'

# ========== YOUR DESEC CREDENTIALS (from voltrontechtx.shop) ==========
DESEC_TOKEN="3WxD4Hkiu5VYBLWVizVhf1rzyKbz"
DESEC_DOMAIN="voltrontechtx.shop"

# ========== DIRECTORIES ==========
DB_DIR="/etc/voltron-gate"
SLIPGATE_DIR="/etc/slipgate"
BACKUP_DIR="$DB_DIR/backups"
BANNER_DIR="$DB_DIR/banners"
SSH_USERS_DB="$DB_DIR/ssh_users.db"
SOCKS5_USERS_DB="$DB_DIR/socks5_users.db"
BANDWIDTH_DIR="$DB_DIR/bandwidth"
PID_DIR="$BANDWIDTH_DIR/pidtrack"
LIMITER_SCRIPT="/usr/local/bin/voltron-limiter.sh"
LIMITER_SERVICE="/etc/systemd/system/voltron-limiter.service"

mkdir -p $DB_DIR $BACKUP_DIR $BANNER_DIR $BANDWIDTH_DIR $PID_DIR
touch $SSH_USERS_DB $SOCKS5_USERS_DB

# ========== PORTS ==========
SOCKS5_PORT=1080
SSH_PORT=22

# ========== HELPER FUNCTIONS ==========
get_ip() { curl -s -4 icanhazip.com; }
is_valid_ipv4() { [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; }
press_enter() { echo -e "\n${C_YELLOW}Press [Enter] to continue...${C_RESET}"; read -r; }

# ========== 1. INSTALL SLIPGATE (OFFICIAL) ==========
install_slipgate() {
    echo -e "${C_BLUE}📥 Installing official Slipgate (working binaries)...${C_RESET}"
    if command -v slipgate &>/dev/null; then
        echo -e "${C_GREEN}Slipgate already installed.${C_RESET}"
        return
    fi
    curl -fsSL https://raw.githubusercontent.com/anonvector/slipgate/main/install.sh | bash
    if [[ $? -ne 0 ]]; then
        echo -e "${C_RED}❌ Slipgate installation failed.${C_RESET}"
        exit 1
    fi
    echo -e "${C_GREEN}✅ Slipgate installed successfully.${C_RESET}"
}

# ========== 2. DESEC DOMAIN GENERATOR ==========
gen_desec_domain() {
    local prefix=$1
    local rand=$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)
    local ns="${prefix}-ns-${rand}"
    local tun="${prefix}-tun-${rand}"
    local ip=$(get_ip)
    is_valid_ipv4 "$ip" || return 1

    curl -s -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
        -H "Authorization: Token $DESEC_TOKEN" \
        -H "Content-Type: application/json" \
        --data "[{\"subname\":\"$ns\",\"type\":\"A\",\"ttl\":3600,\"records\":[\"$ip\"]}]" >/dev/null

    curl -s -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
        -H "Authorization: Token $DESEC_TOKEN" \
        -H "Content-Type: application/json" \
        --data "[{\"subname\":\"$tun\",\"type\":\"NS\",\"ttl\":3600,\"records\":[\"${ns}.${DESEC_DOMAIN}.\"]}]" >/dev/null

    echo "${tun}.${DESEC_DOMAIN}"
}

# ========== 3. ADD TUNNEL (USING SLIPGATE-CLI) ==========
add_tunnel() {
    echo -e "\n${C_CYAN}Select transport type:${C_RESET}"
    echo "  1) DNSTT"
    echo "  2) Slipstream"
    echo "  3) VayDNS"
    echo "  4) NoizDNS"
    read -p "Choice [1-4]: " t_choice
    case $t_choice in
        1) TRANSPORT="dnstt" ;;
        2) TRANSPORT="slipstream" ;;
        3) TRANSPORT="vaydns" ;;
        4) TRANSPORT="noizdns" ;;
        *) echo -e "${C_RED}Invalid${C_RESET}"; return ;;
    esac

    echo -e "\n${C_CYAN}Select backend:${C_RESET}"
    echo "  1) SSH (port 22)"
    echo "  2) SOCKS5 (port 1080)"
    read -p "Choice [1-2]: " b_choice
    if [[ $b_choice -eq 1 ]]; then
        BACKEND="ssh"
    else
        BACKEND="socks"
    fi

    echo -e "\n${C_CYAN}Domain option:${C_RESET}"
    echo "  1) Auto-generate with deSEC (using your domain)"
    echo "  2) Enter custom domain"
    read -p "Choice [1-2]: " d_choice
    if [[ $d_choice -eq 1 ]]; then
        DOMAIN=$(gen_desec_domain "${TRANSPORT}-${BACKEND}")
        if [[ -z "$DOMAIN" ]]; then
            echo -e "${C_RED}❌ Failed to generate domain${C_RESET}"
            return
        fi
        echo -e "${C_GREEN}✅ Generated domain: $DOMAIN${C_RESET}"
    else
        read -p "Enter domain: " DOMAIN
    fi

    # Use slipgate-cli to create the tunnel
    if command -v slipgate-cli &>/dev/null; then
        slipgate-cli tunnel add --transport "$TRANSPORT" --backend "$BACKEND" --domain "$DOMAIN"
        echo -e "${C_GREEN}✅ Tunnel created via slipgate-cli${C_RESET}"
    else
        echo -e "${C_RED}❌ slipgate-cli not found. Is Slipgate installed correctly?${C_RESET}"
    fi
}

# ========== 4. SPEED BOOSTER (KERNEL TWEAKS) ==========
apply_speed_booster() {
    local level=$1
    case $level in
        1)
            sysctl -w net.core.rmem_max=33554432 net.core.wmem_max=33554432
            sysctl -w net.ipv4.udp_rmem_min=524288 net.ipv4.udp_wmem_min=524288
            ;;
        2)
            sysctl -w net.core.rmem_max=67108864 net.core.wmem_max=67108864
            sysctl -w net.ipv4.udp_rmem_min=1048576 net.ipv4.udp_wmem_min=1048576
            ;;
        3)
            sysctl -w net.core.rmem_max=134217728 net.core.wmem_max=134217728
            sysctl -w net.ipv4.udp_rmem_min=2097152 net.ipv4.udp_wmem_min=2097152
            ;;
        4)
            sysctl -w net.core.rmem_max=268435456 net.core.wmem_max=268435456
            sysctl -w net.ipv4.udp_rmem_min=4194304 net.ipv4.udp_wmem_min=4194304
            ;;
        5)
            sysctl -w net.core.rmem_max=536870912 net.core.wmem_max=536870912
            sysctl -w net.ipv4.udp_rmem_min=8388608 net.ipv4.udp_wmem_min=8388608
            ;;
        6)
            sysctl -w net.core.rmem_max=805306368 net.core.wmem_max=805306368
            sysctl -w net.ipv4.udp_rmem_min=6291456 net.ipv4.udp_wmem_min=6291456
            ;;
        7)
            sysctl -w net.core.rmem_max=1073741824 net.core.wmem_max=1073741824
            sysctl -w net.ipv4.udp_rmem_min=12582912 net.ipv4.udp_wmem_min=12582912
            ;;
        *) return ;;
    esac
    sysctl -w net.core.default_qdisc=fq net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
    echo -e "${C_GREEN}✅ Speed booster level $level applied (for DNSTT / NoizDNS)${C_RESET}"
}

# ========== 5. USER MANAGERS (WITH EXPIRY, CONNECTION LIMIT, BANDWIDTH) ==========
# Function to add SSH user
add_ssh_user() {
    read -p "Username: " u
    read -p "Password (leave empty for auto): " p
    [[ -z "$p" ]] && p=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8)
    read -p "Account expiry (days) [30]: " days
    days=${days:-30}
    read -p "Connection limit [1]: " limit
    limit=${limit:-1}
    read -p "Bandwidth limit (GB) [0 = unlimited]: " bw
    bw=${bw:-0}
    expire=$(date -d "+$days days" +%Y-%m-%d)

    useradd -m -s /usr/sbin/nologin "$u" 2>/dev/null
    echo "$u:$p" | chpasswd
    chage -E "$expire" "$u"
    echo "$u:$p:$expire:$limit:$bw:0:ACTIVE" >> "$SSH_USERS_DB"
    echo -e "${C_GREEN}✅ SSH user $u added (expires $expire, max $limit conn, ${bw}GB)${C_RESET}"
}

add_socks5_user() {
    read -p "Username: " u
    read -p "Password (leave empty for auto): " p
    [[ -z "$p" ]] && p=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 8)
    read -p "Account expiry (days) [30]: " days
    days=${days:-30}
    read -p "Connection limit [1]: " limit
    limit=${limit:-1}
    read -p "Bandwidth limit (GB) [0 = unlimited]: " bw
    bw=${bw:-0}
    expire=$(date -d "+$days days" +%Y-%m-%d)

    echo "$u:$p:$expire:$limit:$bw:0:ACTIVE" >> "$SOCKS5_USERS_DB"
    # Update Dante password file
    echo "$u:$p" >> /etc/danted/socks.passwd
    systemctl restart danted
    echo -e "${C_GREEN}✅ SOCKS5 user $u added (expires $expire, max $limit conn, ${bw}GB)${C_RESET}"
}

# List users
list_users() {
    echo -e "\n${C_CYAN}SSH Users:${C_RESET}"
    [[ -f "$SSH_USERS_DB" ]] && cat "$SSH_USERS_DB" | column -t -s':'
    echo -e "\n${C_CYAN}SOCKS5 Users:${C_RESET}"
    [[ -f "$SOCKS5_USERS_DB" ]] && cat "$SOCKS5_USERS_DB" | column -t -s':'
    press_enter
}

# Bandwidth and connection limiter service (similar to Falcon)
setup_limiter() {
    cat > "$LIMITER_SCRIPT" << 'EOF'
#!/bin/bash
DB_FILE="/etc/voltron-gate/ssh_users.db"
SOCKS5_DB="/etc/voltron-gate/socks5_users.db"
BW_DIR="/etc/voltron-gate/bandwidth"
PID_DIR="$BW_DIR/pidtrack"
BANNER_DIR="/etc/voltron-gate/banners"
mkdir -p "$BW_DIR" "$PID_DIR" "$BANNER_DIR"

while true; do
    current_ts=$(date +%s)
    # Process SSH users
    if [[ -f "$DB_FILE" ]]; then
        while IFS=: read -r user pass expiry limit bw used status; do
            [[ -z "$user" ]] && continue
            # Expiry check
            expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            if [[ $expiry_ts -lt $current_ts && $expiry_ts -ne 0 ]]; then
                usermod -L "$user" &>/dev/null
                continue
            fi
            # Connection count
            online=$(pgrep -c -u "$user" sshd)
            if [[ $online -gt $limit ]]; then
                usermod -L "$user" &>/dev/null
                killall -u "$user" -9 &>/dev/null
                (sleep 120; usermod -U "$user" &>/dev/null) &
            fi
            # Bandwidth tracking via /proc
            uid=$(id -u "$user" 2>/dev/null)
            if [[ -n "$uid" && "$bw" -gt 0 ]]; then
                total=0
                for pid in $(pgrep -u "$user" sshd); do
                    if [[ -r "/proc/$pid/io" ]]; then
                        r=$(awk '/^rchar/{print $2}' "/proc/$pid/io" 2>/dev/null)
                        w=$(awk '/^wchar/{print $2}' "/proc/$pid/io" 2>/dev/null)
                        total=$((total + r + w))
                    fi
                done
                used_bytes=$(cat "$BW_DIR/${user}.usage" 2>/dev/null || echo 0)
                new_total=$((used_bytes + total))
                echo "$new_total" > "$BW_DIR/${user}.usage"
                used_gb=$(awk "BEGIN {printf \"%.2f\", $new_total / 1073741824}")
                quota_bytes=$(awk "BEGIN {printf \"%.0f\", $bw * 1073741824}")
                if [[ $new_total -ge $quota_bytes ]]; then
                    usermod -L "$user" &>/dev/null
                fi
                sed -i "s/^$user:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*/$user:$pass:$expiry:$limit:$bw:$used_gb:$status/" "$DB_FILE"
            fi
            # Auto banner (Falcon style)
            if [[ -f "/etc/voltron-gate/banners_enabled" ]]; then
                cat > "$BANNER_DIR/${user}.txt" << BANNER
<br><font color="cyan"><b>WELCOME TO VOLTRON GATE</b></font><br><br>
<font color="yellow"><b>ACCOUNT STATUS</b></font><br>
<font color="white">Username: $user</font><br>
<font color="white">Expires: $expiry</font><br>
<font color="white">Sessions: $online/$limit</font><br>
<font color="white">Bandwidth: ${used_gb:-0}/$bw GB</font><br>
BANNER
            fi
        done < "$DB_FILE"
    fi
    # Similar for SOCKS5 users (simplified: no /proc tracking, just log)
    sleep 30
done
EOF
    chmod +x "$LIMITER_SCRIPT"
    cat > "$LIMITER_SERVICE" << EOF
[Unit]
Description=Voltron Gate Limiter
After=network.target

[Service]
Type=simple
ExecStart=$LIMITER_SCRIPT
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable voltron-limiter.service
    systemctl start voltron-limiter.service
    echo -e "${C_GREEN}✅ Limiter service installed (expiry, connection, bandwidth)${C_RESET}"
}

# ========== 6. AUTO SSH BANNER ==========
setup_auto_banner() {
    mkdir -p "$BANNER_DIR"
    cat > /etc/ssh/sshd_config.d/voltron-banner.conf << 'EOF'
Match User *
    Banner /etc/voltron-gate/banners/%u.txt
EOF
    systemctl reload sshd
    touch "$DB_DIR/banners_enabled"
    echo -e "${C_GREEN}✅ Auto SSH banner enabled (Falcon style)${C_RESET}"
}

# ========== 7. DNS PROXY & FIREWALL ==========
setup_gost_and_firewall() {
    # Ensure Slipgate's own GOST is used; just restart it
    systemctl restart gost-dns 2>/dev/null || echo -e "${C_YELLOW}GOST not yet configured by Slipgate. Run 'slipgate setup' first.${C_RESET}"
    systemctl stop systemd-resolved 2>/dev/null
    iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-port 53
    iptables -I INPUT -p udp --dport 53 -j ACCEPT
    iptables -I INPUT -p tcp --dport 22 -j ACCEPT
    iptables -I INPUT -p tcp --dport 1080 -j ACCEPT
}

# ========== 8. MAIN MENU ==========
main_menu() {
    while true; do
        clear
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_PURPLE}              🔥 VOLTRON GATE (SLIPGATE CORE) 🔥${C_RESET}"
        echo -e "${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "  ${C_GREEN}[1]${C_RESET} Install Slipgate (if not already)"
        echo -e "  ${C_GREEN}[2]${C_RESET} Add New Tunnel (with deSEC auto domain)"
        echo -e "  ${C_GREEN}[3]${C_RESET} Apply Speed Booster (DNSTT/NoizDNS)"
        echo -e "  ${C_GREEN}[4]${C_RESET} Add SSH User (expiry, limit, bandwidth)"
        echo -e "  ${C_GREEN}[5]${C_RESET} Add SOCKS5 User (expiry, limit, bandwidth)"
        echo -e "  ${C_GREEN}[6]${C_RESET} List All Users"
        echo -e "  ${C_GREEN}[7]${C_RESET} Install Limiter Service (enforces limits)"
        echo -e "  ${C_GREEN}[8]${C_RESET} Enable Auto SSH Banner"
        echo -e "  ${C_GREEN}[9]${C_RESET} Setup DNS Proxy & Firewall"
        echo -e "  ${C_RED}[0]${C_RESET} Exit"
        echo ""
        read -p "👉 Select option: " opt
        case $opt in
            1) install_slipgate ;;
            2) add_tunnel ;;
            3) echo "Select speed level (1-7):"; read lvl; apply_speed_booster $lvl; press_enter ;;
            4) add_ssh_user ;;
            5) add_socks5_user ;;
            6) list_users ;;
            7) setup_limiter ;;
            8) setup_auto_banner ;;
            9) setup_gost_and_firewall ;;
            0) exit 0 ;;
            *) echo -e "${C_RED}Invalid option${C_RESET}"; sleep 1 ;;
        esac
    done
}

# ========== INITIAL SETUP ==========
if [[ $EUID -ne 0 ]]; then
    echo -e "${C_RED}❌ Must be root${C_RESET}"
    exit 1
fi

# Install dependencies first
apt update && apt install -y curl wget bc iptables net-tools dante-server

# Ensure Dante config exists
mkdir -p /etc/danted
cat > /etc/danted.conf << 'EOF'
logoutput: syslog
internal: 0.0.0.0 port=1080
external: eth0
method: username
user.privileged: root
user.notprivileged: nobody
client pass { from: 0.0.0.0/0 to: 0.0.0.0/0 log: error }
pass { from: 0.0.0.0/0 to: 0.0.0.0/0 protocol: tcp udp method: username }
EOF
systemctl restart danted 2>/dev/null
systemctl enable danted 2>/dev/null

# Create empty password file
touch /etc/danted/socks.passwd

main_menu
