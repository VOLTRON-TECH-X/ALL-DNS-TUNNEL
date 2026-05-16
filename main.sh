#!/bin/bash

# ============================================================================
# VOLTRON TECH TUNNEL v5.0 (NET2SHARE + FALCON STYLE)
# Description: DNSTT • SLIPSTREAM • VAYDNS • NOIZDNS • SSH • SOCKS5
# Features: Multi-Tunnel, Port 53 only, deSEC Auto Domain, Speed Boosters
#           Auto SSH Banner (Falcon Style), User Managers, Client Config
# Author: Voltron Tech
# ============================================================================

# ========== COLOR CODES ==========
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_RED='\033[91m'
C_GREEN='\033[92m'
C_YELLOW='\033[93m'
C_BLUE='\033[94m'
C_PURPLE='\033[95m'
C_CYAN='\033[96m'
C_WHITE='\033[97m'
C_ORANGE='\033[38;5;208m'

C_TITLE=$C_PURPLE
C_CHOICE=$C_GREEN
C_PROMPT=$C_BLUE
C_WARN=$C_YELLOW
C_DANGER=$C_RED
C_STATUS_A=$C_GREEN
C_STATUS_I=$C_DIM
C_ACCENT=$C_CYAN

# ========== DIRECTORY STRUCTURE ==========
DB_DIR="/etc/voltrontech"
DNSTT_KEYS_DIR="$DB_DIR/dnstt"
BACKUP_DIR="$DB_DIR/backups"
LOGS_DIR="$DB_DIR/logs"
CONFIG_DIR="$DB_DIR/config"
BANDWIDTH_DIR="$DB_DIR/bandwidth"
TRAFFIC_DIR="$DB_DIR/traffic"
SSH_BANNER_DIR="$DB_DIR/banners"
SSH_USERS_DB="$DB_DIR/ssh_users.db"
SOCKS5_USERS_DB="$DB_DIR/socks5_users.db"
SSH_TRAFFIC_DIR="$DB_DIR/ssh_traffic"
SOCKS5_TRAFFIC_DIR="$DB_DIR/socks5_traffic"
MTU_FILE="$CONFIG_DIR/mtu"
BANNER_ENABLED_FILE="$DB_DIR/banners_enabled"
SSHD_FF_CONFIG="/etc/ssh/sshd_config.d/voltron-banners.conf"

# ========== BINARY LOCATIONS ==========
DNSTT_SERVER="/usr/local/bin/dnstt-server"
SLIPSTREAM_SERVER="/usr/local/bin/slipstream-server"
VAYDNS_SERVER="/usr/local/bin/vaydns-server"
NOIZDNS_SERVER="/usr/local/bin/noizdns-server"
GOST_BIN="/usr/local/bin/gost"

# ========== SERVICE FILES ==========
GOST_SERVICE="/etc/systemd/system/gost-dns.service"
LIMITER_SERVICE="/etc/systemd/system/voltron-limiter.service"

# ========== PORTS ==========
DNS_PORT=53
DNSTT_SSH_PORT=5301
DNSTT_SOCKS_PORT=5302
SLIP_SSH_PORT=5303
SLIP_SOCKS_PORT=5304
VAY_SSH_PORT=5305
VAY_SOCKS_PORT=5306
NOIZ_SSH_PORT=5307
NOIZ_SOCKS_PORT=5308
SOCKS5_PORT=1080
SSH_PORT=22

# ========== DESEC DNS CONFIGURATION ==========
DESEC_TOKEN="3WxD4Hkiu5VYBLWVizVhf1rzyKbz"
DESEC_DOMAIN="voltrontechtx.shop"

# ========== TUNNEL TAGS AND CONFIGURATION ==========
declare -A TUNNEL_INFO=(
    ["dnstt-ssh-01"]="transport:dnstt|backend:ssh|port:$DNSTT_SSH_PORT|service:dnstt-ssh.service|domain_file:dnstt-ssh_domain.txt"
    ["dnstt-socks-01"]="transport:dnstt|backend:socks|port:$DNSTT_SOCKS_PORT|service:dnstt-socks.service|domain_file:dnstt-socks_domain.txt"
    ["slip-ssh-01"]="transport:slipstream|backend:ssh|port:$SLIP_SSH_PORT|service:slipstream-ssh.service|domain_file:slip-ssh_domain.txt"
    ["slip-socks-01"]="transport:slipstream|backend:socks|port:$SLIP_SOCKS_PORT|service:slipstream-socks.service|domain_file:slip-socks_domain.txt"
    ["vay-ssh-01"]="transport:vaydns|backend:ssh|port:$VAY_SSH_PORT|service:vaydns-ssh.service|domain_file:vay-ssh_domain.txt"
    ["vay-socks-01"]="transport:vaydns|backend:socks|port:$VAY_SOCKS_PORT|service:vaydns-socks.service|domain_file:vay-socks_domain.txt"
    ["noiz-ssh-01"]="transport:noizdns|backend:ssh|port:$NOIZ_SSH_PORT|service:noizdns-ssh.service|domain_file:noiz-ssh_domain.txt"
    ["noiz-socks-01"]="transport:noizdns|backend:socks|port:$NOIZ_SOCKS_PORT|service:noizdns-socks.service|domain_file:noiz-socks_domain.txt"
)

# ========== CACHE FILES ==========
IP_CACHE_FILE="$DB_DIR/cache/ip"
LOCATION_CACHE_FILE="$DB_DIR/cache/location"
ISP_CACHE_FILE="$DB_DIR/cache/isp"
CACHE_CRON_FILE="/etc/cron.d/voltron-cache-clean"
CACHE_SCRIPT="/usr/local/bin/voltron-cache-clean"

# ========== CREATE DIRECTORIES ==========
create_directories() {
    echo -e "${C_BLUE}📁 Creating directories...${C_RESET}"
    mkdir -p $DB_DIR $DNSTT_KEYS_DIR $BACKUP_DIR $LOGS_DIR $CONFIG_DIR
    mkdir -p $BANDWIDTH_DIR $TRAFFIC_DIR $SSH_BANNER_DIR
    mkdir -p $SSH_TRAFFIC_DIR $SOCKS5_TRAFFIC_DIR
    mkdir -p "$DB_DIR/cache" /etc/ssh/sshd_config.d
    touch $SSH_USERS_DB $SOCKS5_USERS_DB
}

# ========== GET IP, LOCATION, ISP ==========
get_ip_info() {
    if [ ! -f "$IP_CACHE_FILE" ] || [ $(( $(date +%s) - $(stat -c %Y "$IP_CACHE_FILE" 2>/dev/null || echo 0) )) -gt 3600 ]; then
        curl -s -4 icanhazip.com > "$IP_CACHE_FILE" 2>/dev/null || echo "Unknown" > "$IP_CACHE_FILE"
    fi
    IP=$(cat "$IP_CACHE_FILE")
    
    if [ ! -f "$LOCATION_CACHE_FILE" ] || [ ! -f "$ISP_CACHE_FILE" ] || [ $(( $(date +%s) - $(stat -c %Y "$LOCATION_CACHE_FILE" 2>/dev/null || echo 0) )) -gt 86400 ]; then
        local ip_info=$(curl -s "http://ip-api.com/json/$IP" 2>/dev/null)
        if [ $? -eq 0 ] && [ -n "$ip_info" ]; then
            echo "$ip_info" | grep -o '"city":"[^"]*"' | cut -d'"' -f4 2>/dev/null | tr -d '\n' > "$LOCATION_CACHE_FILE"
            echo "$ip_info" | grep -o '"country":"[^"]*"' | cut -d'"' -f4 2>/dev/null >> "$LOCATION_CACHE_FILE"
            echo "$ip_info" | grep -o '"isp":"[^"]*"' | cut -d'"' -f4 2>/dev/null > "$ISP_CACHE_FILE"
        else
            echo "Unknown" > "$LOCATION_CACHE_FILE"
            echo "Unknown" >> "$LOCATION_CACHE_FILE"
            echo "Unknown" > "$ISP_CACHE_FILE"
        fi
    fi
    
    LOCATION=$(head -1 "$LOCATION_CACHE_FILE" 2>/dev/null || echo "Unknown")
    COUNTRY=$(tail -1 "$LOCATION_CACHE_FILE" 2>/dev/null || echo "Unknown")
    ISP=$(cat "$ISP_CACHE_FILE" 2>/dev/null || echo "Unknown")
}

# ========== SHOW BANNER ==========
show_banner() {
    clear
    get_ip_info
    local current_mtu=$(cat "$MTU_FILE" 2>/dev/null || echo "512")
    
    if [[ -n "$LOCATION" && "$LOCATION" != "Unknown" && -n "$COUNTRY" && "$COUNTRY" != "Unknown" ]]; then
        LOCATION_FULL="$LOCATION, $COUNTRY"
    elif [[ -n "$COUNTRY" && "$COUNTRY" != "Unknown" ]]; then
        LOCATION_FULL="$COUNTRY"
    elif [[ -n "$LOCATION" && "$LOCATION" != "Unknown" ]]; then
        LOCATION_FULL="$LOCATION"
    else
        LOCATION_FULL="Unknown"
    fi
    
    echo -e "${C_BOLD}${C_PURPLE}╔═══════════════════════════════════════════════════════════════╗${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}║           🔥 VOLTRON TECH TUNNEL v5.0 🔥                      ║${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}║     DNSTT • SLIPSTREAM • VAYDNS • NOIZDNS • SSH • SOCKS5       ║${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}║                   NET2SHARE + FALCON STYLE                    ║${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}╠═══════════════════════════════════════════════════════════════╣${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}║  Server IP: ${C_GREEN}$IP${C_PURPLE}                                              ${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}║  Location:  ${C_GREEN}$LOCATION_FULL${C_PURPLE}                                            ${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}║  ISP:       ${C_GREEN}$ISP${C_PURPLE}                                            ${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}║  DNS Proxy: ${C_GREEN}Port $DNS_PORT (All tunnels)${C_PURPLE}                              ${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}║  Current MTU: ${C_GREEN}$current_mtu${C_PURPLE}                                           ${C_RESET}"
    
    local current_rmem=$(sysctl -n net.core.rmem_max 2>/dev/null)
    if [[ "$current_rmem" -ge 1073741824 ]]; then
        echo -e "${C_BOLD}${C_PURPLE}║  Speed Booster: ${C_GREEN}EXTREME PLUS (1GB) - 60-100 Mbps 💥💥💥💥💥${C_PURPLE}${C_RESET}"
    elif [[ "$current_rmem" -ge 805306368 ]]; then
        echo -e "${C_BOLD}${C_PURPLE}║  Speed Booster: ${C_GREEN}ULTRA PLUS (768MB) - 40-60 Mbps 🚀🚀🚀🚀${C_PURPLE}${C_RESET}"
    elif [[ "$current_rmem" -ge 536870912 ]]; then
        echo -e "${C_BOLD}${C_PURPLE}║  Speed Booster: ${C_GREEN}EXTREME (512MB) - 35-50 Mbps 💥💥💥${C_PURPLE}${C_RESET}"
    elif [[ "$current_rmem" -ge 268435456 ]]; then
        echo -e "${C_BOLD}${C_PURPLE}║  Speed Booster: ${C_GREEN}ULTRA (256MB) - 25-35 Mbps 🚀🚀🚀${C_PURPLE}${C_RESET}"
    elif [[ "$current_rmem" -ge 134217728 ]]; then
        echo -e "${C_BOLD}${C_PURPLE}║  Speed Booster: ${C_GREEN}HIGH (128MB) - 20-25 Mbps 🚀🚀${C_PURPLE}${C_RESET}"
    elif [[ "$current_rmem" -ge 67108864 ]]; then
        echo -e "${C_BOLD}${C_PURPLE}║  Speed Booster: ${C_GREEN}MEDIUM (64MB) - 15-20 Mbps 🚀${C_PURPLE}${C_RESET}"
    elif [[ "$current_rmem" -ge 33554432 ]]; then
        echo -e "${C_BOLD}${C_PURPLE}║  Speed Booster: ${C_GREEN}STANDARD (32MB) - 10-15 Mbps${C_PURPLE}${C_RESET}"
    fi
    
    if [ -f "$CACHE_CRON_FILE" ]; then
        echo -e "${C_BOLD}${C_PURPLE}║  Cache:      ${C_GREEN}AUTO CLEAN ACTIVE (12:00 AM daily)${C_PURPLE}${C_RESET}"
    else
        echo -e "${C_BOLD}${C_PURPLE}║  Cache:      ${C_YELLOW}AUTO CLEAN DISABLED${C_PURPLE}${C_RESET}"
    fi
    
    if crontab -l 2>/dev/null | grep -q "reboot"; then
        echo -e "${C_BOLD}${C_PURPLE}║  Auto Reboot: ${C_GREEN}ENABLED (Daily at 00:00)${C_PURPLE}${C_RESET}"
    else
        echo -e "${C_BOLD}${C_PURPLE}║  Auto Reboot: ${C_YELLOW}DISABLED${C_PURPLE}${C_RESET}"
    fi
    
    if [ -f "$BANNER_ENABLED_FILE" ]; then
        echo -e "${C_BOLD}${C_PURPLE}║  Auto Banner: ${C_GREEN}ENABLED (Falcon Style)${C_PURPLE}${C_RESET}"
    else
        echo -e "${C_BOLD}${C_PURPLE}║  Auto Banner: ${C_YELLOW}DISABLED${C_RESET}${C_PURPLE}${C_RESET}"
    fi
    
    echo -e "${C_BOLD}${C_PURPLE}╚═══════════════════════════════════════════════════════════════╝${C_RESET}"
    echo ""
}

# ========== INSTALL DEPENDENCIES ==========
install_dependencies() {
    echo -e "\n${C_BLUE}📦 Installing dependencies...${C_RESET}"
    
    if command -v apt &>/dev/null; then
        apt update -qq
        apt install -y curl wget bc iptables net-tools gzip dante-server
    elif command -v yum &>/dev/null; then
        yum install -y curl wget bc iptables net-tools gzip
    elif command -v dnf &>/dev/null; then
        dnf install -y curl wget bc iptables net-tools gzip
    fi
    
    echo -e "${C_GREEN}✅ Dependencies installed${C_RESET}"
}

# ========== CHECK INTERNET ==========
check_internet() {
    if ! ping -c 1 8.8.8.8 &>/dev/null; then
        echo -e "${C_RED}❌ No internet connection!${C_RESET}"
        return 1
    fi
    return 0
}

# ========== VALIDATE IPv4 ==========
_is_valid_ipv4() {
    local ip=$1
    if [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    else
        return 1
    fi
}

# ========== SAFE READ ==========
safe_read() {
    local prompt="$1"
    local var_name="$2"
    read -p "$prompt" "$var_name"
}

# ========== NET2SHARE BINARY DOWNLOAD ==========
download_net2share_binaries() {
    echo -e "\n${C_BLUE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BLUE}           📥 DOWNLOADING NET2SHARE BINARIES${C_RESET}"
    echo -e "${C_BLUE}═══════════════════════════════════════════════════════════════${C_RESET}"
    
    local arch="amd64"
    if [[ "$(uname -m)" == "aarch64" ]] || [[ "$(uname -m)" == "arm64" ]]; then
        arch="arm64"
    fi
    
    echo -e "${C_CYAN}📥 Downloading DNSTT binary for $arch...${C_RESET}"
    wget -q -O "$DNSTT_SERVER" "https://github.com/net2share/dnstt/releases/latest/download/dnstt-server-linux-${arch}"
    chmod +x "$DNSTT_SERVER"
    echo -e "${C_GREEN}✅ DNSTT binary installed${C_RESET}"
    
    echo -e "${C_CYAN}📥 Downloading Slipstream binary for $arch...${C_RESET}"
    wget -q -O "$SLIPSTREAM_SERVER" "https://github.com/net2share/slipstream-rust/releases/latest/download/slipstream-server-linux-${arch}"
    chmod +x "$SLIPSTREAM_SERVER"
    echo -e "${C_GREEN}✅ Slipstream binary installed${C_RESET}"
    
    echo -e "${C_CYAN}📥 Downloading VayDNS binary for $arch...${C_RESET}"
    wget -q -O "$VAYDNS_SERVER" "https://github.com/net2share/vaydns/releases/latest/download/vaydns-server-linux-${arch}"
    chmod +x "$VAYDNS_SERVER"
    echo -e "${C_GREEN}✅ VayDNS binary installed${C_RESET}"
    
    echo -e "${C_CYAN}📥 Downloading NoizDNS binary for $arch...${C_RESET}"
    wget -q -O "$NOIZDNS_SERVER" "https://github.com/net2share/noizdns/releases/latest/download/noizdns-server-linux-${arch}"
    chmod +x "$NOIZDNS_SERVER"
    echo -e "${C_GREEN}✅ NoizDNS binary installed${C_RESET}"
    
    echo -e "${C_CYAN}📥 Downloading GOST DNS proxy...${C_RESET}"
    wget -q -O /tmp/gost.gz "https://github.com/ginuerzh/gost/releases/latest/download/gost-linux-${arch}-2.11.5.gz"
    gunzip -f /tmp/gost.gz
    chmod +x /tmp/gost
    mv /tmp/gost "$GOST_BIN"
    echo -e "${C_GREEN}✅ GOST DNS proxy installed${C_RESET}"
}

# ========== DESEC DNS DOMAIN GENERATOR ==========
generate_desec_domain() {
    local tunnel_type=$1
    local rand=$(head /dev/urandom | tr -dc a-z0-9 | head -c 6)
    
    local ns_subdomain="${tunnel_type}-ns-${rand}"
    local tun_subdomain="${tunnel_type}-tun-${rand}"
    
    local SERVER_IPV4=$(curl -s -4 icanhazip.com)
    if ! _is_valid_ipv4 "$SERVER_IPV4"; then
        echo -e "${C_RED}❌ Could not detect valid IPv4 address${C_RESET}"
        return 1
    fi
    
    echo -e "${C_CYAN}Creating A record: ${ns_subdomain}.${DESEC_DOMAIN} → ${SERVER_IPV4}${C_RESET}"
    curl -s -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
        -H "Authorization: Token $DESEC_TOKEN" \
        -H "Content-Type: application/json" \
        --data "[{\"subname\":\"$ns_subdomain\",\"type\":\"A\",\"ttl\":3600,\"records\":[\"$SERVER_IPV4\"]}]" > /dev/null
    
    echo -e "${C_CYAN}Creating NS record: ${tun_subdomain}.${DESEC_DOMAIN} → ${ns_subdomain}.${DESEC_DOMAIN}${C_RESET}"
    curl -s -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
        -H "Authorization: Token $DESEC_TOKEN" \
        -H "Content-Type: application/json" \
        --data "[{\"subname\":\"$tun_subdomain\",\"type\":\"NS\",\"ttl\":3600,\"records\":[\"${ns_subdomain}.${DESEC_DOMAIN}.\"]}]" > /dev/null
    
    local FULL_DOMAIN="${tun_subdomain}.${DESEC_DOMAIN}"
    
    echo "$FULL_DOMAIN" > "$DB_DIR/${tunnel_type}_domain.txt"
    echo "$ns_subdomain" > "$DB_DIR/${tunnel_type}_ns.txt"
    echo "$tun_subdomain" > "$DB_DIR/${tunnel_type}_tun.txt"
    
    echo -e "${C_GREEN}✅ Domain generated: ${C_YELLOW}$FULL_DOMAIN${C_RESET}"
    echo "$FULL_DOMAIN"
}

# ========== DNSTT KEY GENERATION ==========
generate_dnstt_keys() {
    echo -e "\n${C_BLUE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BLUE}           🔑 GENERATING DNSTT KEYS${C_RESET}"
    echo -e "${C_BLUE}═══════════════════════════════════════════════════════════════${C_RESET}"
    
    mkdir -p "$DNSTT_KEYS_DIR"
    cd "$DNSTT_KEYS_DIR"
    
    $DNSTT_SERVER -gen-key -privkey server.key -pubkey server.pub
    
    chmod 600 server.key
    chmod 644 server.pub
    
    PUBLIC_KEY=$(cat server.pub)
    echo -e "${C_GREEN}✅ DNSTT keys generated${C_RESET}"
    echo -e "   • Private key: $DNSTT_KEYS_DIR/server.key"
    echo -e "   • Public key: $DNSTT_KEYS_DIR/server.pub"
}

# ========== CREATE TUNNEL SERVICE ==========
create_tunnel_service() {
    local transport=$1
    local backend=$2
    local domain=$3
    local port=$4
    local target=$5
    
    local binary=""
    local exec_start=""
    local service_name=""
    
    case $transport in
        dnstt)
            binary="$DNSTT_SERVER"
            exec_start="$binary -udp :$port -privkey $DNSTT_KEYS_DIR/server.key -domain $domain $target"
            service_name="dnstt-${backend}.service"
            ;;
        slipstream)
            binary="$SLIPSTREAM_SERVER"
            exec_start="$binary --dns-listen-port $port --domain $domain --upstream $target"
            service_name="slipstream-${backend}.service"
            ;;
        vaydns)
            binary="$VAYDNS_SERVER"
            exec_start="$binary -udp :$port -domain $domain -upstream $target"
            service_name="vaydns-${backend}.service"
            ;;
        noizdns)
            binary="$NOIZDNS_SERVER"
            exec_start="$binary -udp :$port -domain $domain -upstream $target"
            service_name="noizdns-${backend}.service"
            ;;
    esac
    
    cat > "/etc/systemd/system/${service_name}" << EOF
[Unit]
Description=${transport^^} + $backend Tunnel
After=network.target

[Service]
Type=simple
ExecStart=$exec_start
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable "${service_name}"
    
    echo -e "${C_GREEN}✅ ${transport^^} + $backend tunnel created on port $port${C_RESET}"
}

# ========== DNS PROXY (GOST) CONFIGURATION ==========
configure_dns_proxy() {
    echo -e "\n${C_BLUE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BLUE}           🔀 CONFIGURING DNS PROXY (GOST)${C_RESET}"
    echo -e "${C_BLUE}═══════════════════════════════════════════════════════════════${C_RESET}"
    
    mkdir -p "$(dirname "$GOST_CONFIG")"
    
    cat > "$GOST_CONFIG" << EOF
{
    "Debug": true,
    "Retries": 3,
    "Routes": [
        {"Domain": "*.dnstt-ssh*.${DESEC_DOMAIN}", "Target": "127.0.0.1:$DNSTT_SSH_PORT"},
        {"Domain": "*.dnstt-socks*.${DESEC_DOMAIN}", "Target": "127.0.0.1:$DNSTT_SOCKS_PORT"},
        {"Domain": "*.slip-ssh*.${DESEC_DOMAIN}", "Target": "127.0.0.1:$SLIP_SSH_PORT"},
        {"Domain": "*.slip-socks*.${DESEC_DOMAIN}", "Target": "127.0.0.1:$SLIP_SOCKS_PORT"},
        {"Domain": "*.vay-ssh*.${DESEC_DOMAIN}", "Target": "127.0.0.1:$VAY_SSH_PORT"},
        {"Domain": "*.vay-socks*.${DESEC_DOMAIN}", "Target": "127.0.0.1:$VAY_SOCKS_PORT"},
        {"Domain": "*.noiz-ssh*.${DESEC_DOMAIN}", "Target": "127.0.0.1:$NOIZ_SSH_PORT"},
        {"Domain": "*.noiz-socks*.${DESEC_DOMAIN}", "Target": "127.0.0.1:$NOIZ_SOCKS_PORT"}
    ]
}
EOF

    cat > "$GOST_SERVICE" << EOF
[Unit]
Description=GOST DNS Proxy for Multi-Tunnel
After=network.target

[Service]
Type=simple
ExecStart=$GOST_BIN -C $GOST_CONFIG -L dns://:$DNS_PORT
Restart=always
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable gost-dns.service
    
    echo -e "${C_GREEN}✅ DNS Proxy configured on port $DNS_PORT${C_RESET}"
}

# ========== FIREWALL CONFIGURATION ==========
configure_firewall() {
    echo -e "\n${C_BLUE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BLUE}           🔥 CONFIGURING FIREWALL${C_RESET}"
    echo -e "${C_BLUE}═══════════════════════════════════════════════════════════════${C_RESET}"
    
    systemctl stop systemd-resolved 2>/dev/null
    systemctl disable systemd-resolved 2>/dev/null
    
    iptables -t nat -F PREROUTING 2>/dev/null
    iptables -F 2>/dev/null
    
    iptables -t nat -I PREROUTING 1 -p udp --dport 53 -j REDIRECT --to-port 53
    
    iptables -I INPUT 1 -p udp --dport 53 -j ACCEPT
    iptables -I INPUT 2 -p tcp --dport 22 -j ACCEPT
    iptables -I INPUT 2 -p tcp --dport 1080 -j ACCEPT
    
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null
    
    echo -e "${C_GREEN}✅ Firewall configured${C_RESET}"
    echo -e "   • Port 53: Redirected to GOST DNS Proxy"
    echo -e "   • Port 22: SSH (open)"
    echo -e "   • Port 1080: SOCKS5 (open)"
}

# ========== SPEED BOOSTERS (7 LEVELS) ==========
apply_dnstt_standard() {
    modprobe tcp_bbr 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
    sysctl -w net.ipv4.udp_rmem_min=524288 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=524288 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=33554432 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=33554432 >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=100000 >/dev/null 2>&1
    sysctl -w net.netfilter.nf_conntrack_max=4000000 >/dev/null 2>&1
    ulimit -n 1048576 2>/dev/null
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_dsack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
    sysctl -w net.ipv4.ip_local_port_range="1024 65535" >/dev/null 2>&1
    echo -e "${C_GREEN}✅ Standard Booster applied! (10-15 Mbps)${C_RESET}"
}

apply_dnstt_medium() {
    modprobe tcp_bbr 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
    sysctl -w net.ipv4.udp_rmem_min=1048576 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=1048576 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=67108864 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=67108864 >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=200000 >/dev/null 2>&1
    sysctl -w net.core.somaxconn=524288 >/dev/null 2>&1
    sysctl -w net.netfilter.nf_conntrack_max=4000000 >/dev/null 2>&1
    ulimit -n 1048576 2>/dev/null
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_dsack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
    sysctl -w net.ipv4.ip_local_port_range="1024 65535" >/dev/null 2>&1
    echo -e "${C_GREEN}✅ Medium Booster applied! (15-20 Mbps) 🚀${C_RESET}"
}

apply_dnstt_high() {
    modprobe tcp_bbr 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
    sysctl -w net.ipv4.udp_rmem_min=2097152 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=2097152 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=134217728 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=134217728 >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=400000 >/dev/null 2>&1
    sysctl -w net.core.somaxconn=1048576 >/dev/null 2>&1
    sysctl -w net.netfilter.nf_conntrack_max=8000000 >/dev/null 2>&1
    ulimit -n 2097152 2>/dev/null
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_dsack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
    sysctl -w net.ipv4.ip_local_port_range="1024 65535" >/dev/null 2>&1
    echo -e "${C_GREEN}✅ High Booster applied! (20-25 Mbps) 🚀🚀${C_RESET}"
}

apply_dnstt_ultra() {
    modprobe tcp_bbr 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
    sysctl -w net.ipv4.udp_rmem_min=4194304 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=4194304 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=268435456 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=268435456 >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=600000 >/dev/null 2>&1
    sysctl -w net.core.somaxconn=2097152 >/dev/null 2>&1
    sysctl -w net.netfilter.nf_conntrack_max=16000000 >/dev/null 2>&1
    ulimit -n 4194304 2>/dev/null
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_dsack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
    sysctl -w net.ipv4.ip_local_port_range="1024 65535" >/dev/null 2>&1
    echo -e "${C_GREEN}✅ Ultra Booster applied! (25-35 Mbps) 🚀🚀🚀${C_RESET}"
}

apply_dnstt_extreme() {
    modprobe tcp_bbr 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
    sysctl -w net.ipv4.udp_rmem_min=8388608 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=8388608 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=536870912 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=536870912 >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=1000000 >/dev/null 2>&1
    sysctl -w net.core.somaxconn=4194304 >/dev/null 2>&1
    sysctl -w net.netfilter.nf_conntrack_max=32000000 >/dev/null 2>&1
    ulimit -n 8388608 2>/dev/null
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_dsack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
    sysctl -w net.ipv4.ip_local_port_range="1024 65535" >/dev/null 2>&1
    echo -e "${C_GREEN}✅ Extreme Booster applied! (35-50 Mbps) 💥💥💥${C_RESET}"
}

apply_dnstt_ultra_plus() {
    modprobe tcp_bbr 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
    sysctl -w net.ipv4.udp_rmem_min=6291456 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=6291456 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=805306368 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=805306368 >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=800000 >/dev/null 2>&1
    sysctl -w net.core.somaxconn=3145728 >/dev/null 2>&1
    sysctl -w net.netfilter.nf_conntrack_max=24000000 >/dev/null 2>&1
    ulimit -n 6291456 2>/dev/null
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_dsack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
    sysctl -w net.ipv4.ip_local_port_range="1024 65535" >/dev/null 2>&1
    echo -e "${C_GREEN}✅ Ultra Plus Booster applied! (40-60 Mbps) 🚀🚀🚀🚀${C_RESET}"
}

apply_dnstt_extreme_plus() {
    modprobe tcp_bbr 2>/dev/null
    sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
    sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
    sysctl -w net.ipv4.udp_rmem_min=12582912 >/dev/null 2>&1
    sysctl -w net.ipv4.udp_wmem_min=12582912 >/dev/null 2>&1
    sysctl -w net.core.rmem_max=1073741824 >/dev/null 2>&1
    sysctl -w net.core.wmem_max=1073741824 >/dev/null 2>&1
    sysctl -w net.core.netdev_max_backlog=1200000 >/dev/null 2>&1
    sysctl -w net.core.somaxconn=6291456 >/dev/null 2>&1
    sysctl -w net.netfilter.nf_conntrack_max=48000000 >/dev/null 2>&1
    ulimit -n 12582912 2>/dev/null
    sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_dsack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_fack=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_timestamps=1 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
    sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
    sysctl -w net.ipv4.ip_local_port_range="1024 65535" >/dev/null 2>&1
    echo -e "${C_GREEN}✅ Extreme Plus Booster applied! (60-100 Mbps) 💥💥💥💥💥${C_RESET}"
}

# ========== SPEED BOOSTER MENU ==========
speed_booster_menu() {
    while true; do
        clear
        show_banner
        echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}           ⚡ DNSTT SPEED BOOSTER MANAGER${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo ""
        echo -e "  ${C_CYAN}Select Speed Level:${C_RESET}"
        echo ""
        echo -e "  ${C_GREEN}[1]${C_RESET} Standard  (32MB)   → 10-15 Mbps"
        echo -e "  ${C_GREEN}[2]${C_RESET} Medium     (64MB)   → 15-20 Mbps  🚀"
        echo -e "  ${C_GREEN}[3]${C_RESET} High       (128MB)  → 20-25 Mbps  🚀🚀"
        echo -e "  ${C_GREEN}[4]${C_RESET} Ultra      (256MB)  → 25-35 Mbps  🚀🚀🚀"
        echo -e "  ${C_GREEN}[5]${C_RESET} Extreme    (512MB)  → 35-50 Mbps  💥💥💥"
        echo -e "  ${C_GREEN}[6]${C_RESET} Ultra Plus (768MB)  → 40-60 Mbps  🚀🚀🚀🚀"
        echo -e "  ${C_GREEN}[7]${C_RESET} Extreme Plus (1GB)  → 60-100 Mbps 💥💥💥💥💥"
        echo ""
        echo -e "  ${C_YELLOW}[8]${C_RESET} View Current Settings"
        echo -e "  ${C_RED}[9]${C_RESET} Reset to Default"
        echo -e "  ${C_RED}[0]${C_RESET} Return"
        echo ""
        
        local choice
        read -p "$(echo -e ${C_PROMPT}"👉 Select speed level: "${C_RESET})" choice
        
        case $choice in
            1) apply_dnstt_standard ;;
            2) apply_dnstt_medium ;;
            3) apply_dnstt_high ;;
            4) apply_dnstt_ultra ;;
            5) apply_dnstt_extreme ;;
            6) apply_dnstt_ultra_plus ;;
            7) apply_dnstt_extreme_plus ;;
            8)
                echo -e "\n${C_CYAN}Current System Settings:${C_RESET}"
                echo -e "  ${C_WHITE}TCP Congestion:${C_RESET} $(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)"
                echo -e "  ${C_WHITE}Network Buffer:${C_RESET} $(sysctl -n net.core.rmem_max 2>/dev/null) bytes"
                echo -e "  ${C_WHITE}UDP Buffer:${C_RESET} $(sysctl -n net.ipv4.udp_rmem_min 2>/dev/null) bytes"
                safe_read "" dummy
                ;;
            9)
                echo -e "\n${C_RED}⚠️ Reset to default?${C_RESET}"
                read -p "Confirm (y/n): " confirm
                if [[ "$confirm" == "y" ]]; then
                    sysctl -w net.core.rmem_max=212992 >/dev/null 2>&1
                    sysctl -w net.ipv4.tcp_congestion_control=cubic >/dev/null 2>&1
                    echo -e "${C_GREEN}✅ Reset to default${C_RESET}"
                fi
                safe_read "" dummy
                ;;
            0) return ;;
        esac
    done
}

# ========== ADD NEW TUNNEL WIZARD ==========
add_tunnel_wizard() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}                   ➕ ADD NEW TUNNEL${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
    
    # Step 1: Select Transport Type
    echo -e "\n${C_CYAN}[1/5] Select Transport Type:${C_RESET}"
    echo ""
    echo -e "  ${C_GREEN}[1]${C_RESET} DNSTT     - DNS tunnel (Classic, requires public key)"
    echo -e "  ${C_GREEN}[2]${C_RESET} Slipstream - DNS tunnel (QUIC, high performance)"
    echo -e "  ${C_GREEN}[3]${C_RESET} VayDNS    - Lean DNS tunnel (customizable)"
    echo -e "  ${C_GREEN}[4]${C_RESET} NoizDNS   - Stealth DNS tunnel (DPI resistant)"
    echo ""
    
    read -p "$(echo -e ${C_PROMPT}"👉 Choose transport [1-4]: "${C_RESET})" transport_choice
    
    case $transport_choice in
        1) TRANSPORT="dnstt"; TRANSPORT_NAME="DNSTT"; NEEDS_SPEED_BOOSTER=true ;;
        2) TRANSPORT="slipstream"; TRANSPORT_NAME="Slipstream"; NEEDS_SPEED_BOOSTER=false ;;
        3) TRANSPORT="vaydns"; TRANSPORT_NAME="VayDNS"; NEEDS_SPEED_BOOSTER=false ;;
        4) TRANSPORT="noizdns"; TRANSPORT_NAME="NoizDNS"; NEEDS_SPEED_BOOSTER=false ;;
        *) echo -e "${C_RED}❌ Invalid choice${C_RESET}"; return ;;
    esac
    
    echo -e "\n${C_GREEN}✅ Selected: $TRANSPORT_NAME${C_RESET}"
    
    # Step 2: Domain Configuration
    echo -e "\n${C_CYAN}[2/5] Domain Configuration:${C_RESET}"
    echo ""
    echo -e "  ${C_GREEN}[1]${C_RESET} Auto-generate with deSEC DNS"
    echo -e "  ${C_GREEN}[2]${C_RESET} Custom domain"
    echo ""
    
    read -p "$(echo -e ${C_PROMPT}"👉 Choose domain option [1-2]: "${C_RESET})" domain_choice
    
    if [[ "$domain_choice" == "1" ]]; then
        echo -e "\n${C_BLUE}🔍 Auto-generating domain with deSEC...${C_RESET}"
        
        local tunnel_tag="${TRANSPORT}-ssh"
        if [[ "$domain_choice" == "2" ]]; then
            tunnel_tag="${TRANSPORT}-socks"
        fi
        
        DOMAIN=$(generate_desec_domain "$tunnel_tag")
        if [[ -z "$DOMAIN" ]]; then
            echo -e "${C_RED}❌ Failed to generate domain${C_RESET}"
            return
        fi
        echo -e "${C_GREEN}✅ Auto-generated domain: ${C_YELLOW}$DOMAIN${C_RESET}"
    else
        read -p "$(echo -e ${C_PROMPT}"👉 Enter your domain: "${C_RESET})" DOMAIN
        if [[ -z "$DOMAIN" ]]; then
            echo -e "${C_RED}❌ Domain cannot be empty${C_RESET}"
            return
        fi
        echo -e "${C_GREEN}✅ Using custom domain: ${C_YELLOW}$DOMAIN${C_RESET}"
    fi
    
    # Step 3: Select Backend
    echo -e "\n${C_CYAN}[3/5] Select Backend:${C_RESET}"
    echo ""
    echo -e "  ${C_GREEN}[1]${C_RESET} SSH        - Direct SSH (port 22)"
    echo -e "  ${C_GREEN}[2]${C_RESET} SOCKS5     - SOCKS5 proxy (port 1080)"
    echo -e "  ${C_GREEN}[3]${C_RESET} Custom     - Custom address:port"
    echo ""
    
    read -p "$(echo -e ${C_PROMPT}"👉 Choose backend [1-3]: "${C_RESET})" backend_choice
    
    case $backend_choice in
        1) BACKEND="ssh"; BACKEND_TARGET="127.0.0.1:22"
           echo -e "${C_GREEN}✅ Backend: SSH${C_RESET}" ;;
        2) BACKEND="socks"; BACKEND_TARGET="127.0.0.1:1080"
           echo -e "${C_GREEN}✅ Backend: SOCKS5${C_RESET}"
           echo -e "${C_YELLOW}⚠️ Authentication handled by SOCKS5 Manager${C_RESET}" ;;
        3) BACKEND="custom"
           read -p "$(echo -e ${C_PROMPT}"👉 Enter custom target (ip:port): "${C_RESET})" BACKEND_TARGET
           echo -e "${C_GREEN}✅ Backend: Custom -> $BACKEND_TARGET${C_RESET}" ;;
        *) echo -e "${C_RED}❌ Invalid choice${C_RESET}"; return ;;
    esac
    
    # Step 4: Speed Booster (Only for DNSTT)
    if [[ "$NEEDS_SPEED_BOOSTER" == true ]]; then
        echo -e "\n${C_CYAN}[4/5] Speed Booster Configuration (DNSTT only):${C_RESET}"
        echo ""
        echo -e "  ${C_GREEN}[1]${C_RESET} Standard  (32MB)   → 10-15 Mbps"
        echo -e "  ${C_GREEN}[2]${C_RESET} Medium     (64MB)   → 15-20 Mbps  🚀"
        echo -e "  ${C_GREEN}[3]${C_RESET} High       (128MB)  → 20-25 Mbps  🚀🚀"
        echo -e "  ${C_GREEN}[4]${C_RESET} Ultra      (256MB)  → 25-35 Mbps  🚀🚀🚀"
        echo -e "  ${C_GREEN}[5]${C_RESET} Extreme    (512MB)  → 35-50 Mbps  💥💥💥"
        echo -e "  ${C_GREEN}[6]${C_RESET} Ultra Plus (768MB)  → 40-60 Mbps  🚀🚀🚀🚀"
        echo -e "  ${C_GREEN}[7]${C_RESET} Extreme Plus (1GB)  → 60-100 Mbps 💥💥💥💥💥"
        echo -e "  ${C_GREEN}[8]${C_RESET} Skip (No booster)"
        echo ""
        
        read -p "$(echo -e ${C_PROMPT}"👉 Choose booster level [1-8, default=3]: "${C_RESET})" booster_choice
        booster_choice=${booster_choice:-3}
        
        case $booster_choice in
            1) apply_dnstt_standard ;;
            2) apply_dnstt_medium ;;
            3) apply_dnstt_high ;;
            4) apply_dnstt_ultra ;;
            5) apply_dnstt_extreme ;;
            6) apply_dnstt_ultra_plus ;;
            7) apply_dnstt_extreme_plus ;;
            8) echo -e "${C_YELLOW}⚠️ Skipping speed booster${C_RESET}" ;;
        esac
    else
        echo -e "\n${C_CYAN}[4/5] Speed Booster:${C_RESET}"
        echo -e "  ${C_YELLOW}⚠️ Speed booster is only available for DNSTT${C_RESET}"
        echo -e "  ${C_GREEN}✅ Skipping...${C_RESET}"
    fi
    
    # Step 5: Create Tunnel
    echo -e "\n${C_CYAN}[5/5] Creating tunnel...${C_RESET}"
    
    local port=""
    local domain_file=""
    
    if [[ "$TRANSPORT" == "dnstt" ]] && [[ "$BACKEND" == "ssh" ]]; then
        port="$DNSTT_SSH_PORT"; domain_file="dnstt-ssh_domain.txt"
    elif [[ "$TRANSPORT" == "dnstt" ]] && [[ "$BACKEND" == "socks" ]]; then
        port="$DNSTT_SOCKS_PORT"; domain_file="dnstt-socks_domain.txt"
    elif [[ "$TRANSPORT" == "slipstream" ]] && [[ "$BACKEND" == "ssh" ]]; then
        port="$SLIP_SSH_PORT"; domain_file="slip-ssh_domain.txt"
    elif [[ "$TRANSPORT" == "slipstream" ]] && [[ "$BACKEND" == "socks" ]]; then
        port="$SLIP_SOCKS_PORT"; domain_file="slip-socks_domain.txt"
    elif [[ "$TRANSPORT" == "vaydns" ]] && [[ "$BACKEND" == "ssh" ]]; then
        port="$VAY_SSH_PORT"; domain_file="vay-ssh_domain.txt"
    elif [[ "$TRANSPORT" == "vaydns" ]] && [[ "$BACKEND" == "socks" ]]; then
        port="$VAY_SOCKS_PORT"; domain_file="vay-socks_domain.txt"
    elif [[ "$TRANSPORT" == "noizdns" ]] && [[ "$BACKEND" == "ssh" ]]; then
        port="$NOIZ_SSH_PORT"; domain_file="noiz-ssh_domain.txt"
    elif [[ "$TRANSPORT" == "noizdns" ]] && [[ "$BACKEND" == "socks" ]]; then
        port="$NOIZ_SOCKS_PORT"; domain_file="noiz-socks_domain.txt"
    fi
    
    # Save domain
    echo "$DOMAIN" > "$DB_DIR/$domain_file"
    
    create_tunnel_service "$TRANSPORT" "$BACKEND" "$DOMAIN" "$port" "$BACKEND_TARGET"
    
    echo -e "\n${C_GREEN}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_GREEN}           ✅ TUNNEL CREATED SUCCESSFULLY!${C_RESET}"
    echo -e "${C_GREEN}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "  ${C_YELLOW}Transport:${C_RESET}      $TRANSPORT_NAME"
    echo -e "  ${C_YELLOW}Backend:${C_RESET}        $BACKEND -> $BACKEND_TARGET"
    echo -e "  ${C_YELLOW}Domain:${C_RESET}         $DOMAIN"
    echo -e "  ${C_YELLOW}Port:${C_RESET}           $DNS_PORT (UDP)"
    
    if [[ "$TRANSPORT" == "dnstt" ]] && [[ -f "$DNSTT_KEYS_DIR/server.pub" ]]; then
        local pubkey=$(cat "$DNSTT_KEYS_DIR/server.pub" | head -c 50)
        echo -e "  ${C_YELLOW}Public Key:${C_RESET}    ${pubkey}..."
    fi
    
    echo -e "\n${C_CYAN}📌 Client can now connect using domain: $DOMAIN${C_RESET}"
    
    safe_read "" dummy
}

# ========== LIST ACTIVE TUNNELS ==========
list_active_tunnels() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}                      📡 ACTIVE TUNNELS${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    
    printf "  ${C_BOLD}┌─────┬──────────────────┬─────────────┬──────────┬──────────┬────────────┐${C_RESET}\n"
    printf "  ${C_BOLD}│  #  │ TUNNEL TAG       │ TRANSPORT   │ BACKEND  │ PORT     │ STATUS     │${C_RESET}\n"
    printf "  ${C_BOLD}├─────┼──────────────────┼─────────────┼──────────┼──────────┼────────────┤${C_RESET}\n"
    
    local count=1
    local active_count=0
    local warning_count=0
    local stopped_count=0
    
    local -a tunnel_tags=(
        "dnstt-ssh-01" "dnstt-socks-01"
        "slip-ssh-01" "slip-socks-01"
        "vay-ssh-01" "vay-socks-01"
        "noiz-ssh-01" "noiz-socks-01"
    )
    
    for tag in "${tunnel_tags[@]}"; do
        local config="${TUNNEL_INFO[$tag]}"
        local transport=$(echo "$config" | grep -oP 'transport:\K[^|]+')
        local backend=$(echo "$config" | grep -oP 'backend:\K[^|]+')
        local service=$(echo "$config" | grep -oP 'service:\K[^|]+')
        
        local status_icon="🔴"
        local status_text="STOPPED"
        if systemctl is-active --quiet "$service" 2>/dev/null; then
            status_icon="🟢"
            status_text="RUNNING"
            ((active_count++))
        elif systemctl is-failed --quiet "$service" 2>/dev/null; then
            status_icon="🟡"
            status_text="WARNING"
            ((warning_count++))
        else
            ((stopped_count++))
        fi
        
        printf "  │ ${C_WHITE}%2d${C_RESET} │ ${C_CYAN}%-16s${C_RESET} │ ${C_GREEN}%-11s${C_RESET} │ ${C_YELLOW}%-8s${C_RESET} │ ${C_WHITE}%-8s${C_RESET} │ %s %-8s │\n" \
            "$count" "$tag" "${transport^^}" "${backend^^}" "53" "$status_icon" "$status_text"
        
        count=$((count + 1))
    done
    
    printf "  ${C_BOLD}└─────┴──────────────────┴─────────────┴──────────┴──────────┴────────────┘${C_RESET}\n"
    echo ""
    echo -e "  ${C_GREEN}🟢 Running${C_RESET}  ${C_YELLOW}🟡 Warning${C_RESET}  ${C_RED}🔴 Stopped${C_RESET}"
    echo ""
    echo -e "  ${C_CYAN}Total Tunnels: $((active_count + warning_count + stopped_count)) | Active: $active_count | Stopped: $stopped_count | Warning: $warning_count${C_RESET}"
    echo ""
    
    echo -e "  ${C_GREEN}[1]${C_RESET} View Tunnel Details"
    echo -e "  ${C_GREEN}[2]${C_RESET} Start Tunnel"
    echo -e "  ${C_GREEN}[3]${C_RESET} Stop Tunnel"
    echo -e "  ${C_GREEN}[4]${C_RESET} Restart Tunnel"
    echo -e "  ${C_GREEN}[5]${C_RESET} Remove Tunnel"
    echo -e "  ${C_GREEN}[6]${C_RESET} Show Client Config"
    echo -e "  ${C_RED}[0]${C_RESET} Return"
    echo ""
    
    read -p "$(echo -e ${C_PROMPT}"👉 Select option: "${C_RESET})" action_choice
    
    case $action_choice in
        1|2|3|4|5|6)
            echo ""
            read -p "$(echo -e ${C_PROMPT}"👉 Enter Tunnel Tag or Number: "${C_RESET})" tunnel_input
            
            if [[ "$tunnel_input" =~ ^[0-9]+$ ]]; then
                local idx=$((tunnel_input - 1))
                if [[ $idx -ge 0 && $idx -lt ${#tunnel_tags[@]} ]]; then
                    selected_tag="${tunnel_tags[$idx]}"
                else
                    echo -e "${C_RED}❌ Invalid number${C_RESET}"
                    safe_read "" dummy
                    return
                fi
            else
                selected_tag="$tunnel_input"
            fi
            
            local config="${TUNNEL_INFO[$selected_tag]}"
            if [[ -z "$config" ]]; then
                echo -e "${C_RED}❌ Invalid tunnel tag: $selected_tag${C_RESET}"
                safe_read "" dummy
                return
            fi
            
            local service=$(echo "$config" | grep -oP 'service:\K[^|]+')
            local transport=$(echo "$config" | grep -oP 'transport:\K[^|]+')
            local backend=$(echo "$config" | grep -oP 'backend:\K[^|]+')
            local domain_file=$(echo "$config" | grep -oP 'domain_file:\K[^|]+')
            
            case $action_choice in
                1) 
                    echo -e "\n${C_CYAN}=== TUNNEL DETAILS: $selected_tag ===${C_RESET}"
                    echo -e "  Transport: ${transport^^}"
                    echo -e "  Backend: ${backend^^}"
                    echo -e "  Status: $(systemctl is-active "$service" 2>/dev/null)"
                    if [[ -f "$DB_DIR/$domain_file" ]]; then
                        echo -e "  Domain: $(cat "$DB_DIR/$domain_file")"
                    fi
                    if [[ "$transport" == "dnstt" && -f "$DNSTT_KEYS_DIR/server.pub" ]]; then
                        echo -e "  Public Key: $(cat "$DNSTT_KEYS_DIR/server.pub" | head -c 80)..."
                    fi
                    ;;
                2) systemctl start "$service"
                   echo -e "${C_GREEN}✅ Tunnel started${C_RESET}" ;;
                3) systemctl stop "$service"
                   echo -e "${C_YELLOW}🛑 Tunnel stopped${C_RESET}" ;;
                4) systemctl restart "$service"
                   echo -e "${C_GREEN}✅ Tunnel restarted${C_RESET}" ;;
                5) 
                    systemctl stop "$service"
                    systemctl disable "$service"
                    rm -f "/etc/systemd/system/${service}"
                    systemctl daemon-reload
                    echo -e "${C_GREEN}✅ Tunnel removed${C_RESET}"
                    ;;
                6)
                    echo -e "\n${C_CYAN}=== CLIENT CONFIG FOR $selected_tag ===${C_RESET}"
                    if [[ -f "$DB_DIR/$domain_file" ]]; then
                        local domain=$(cat "$DB_DIR/$domain_file")
                        echo -e "  Domain: $domain"
                        echo -e "  Port: $DNS_PORT"
                        if [[ "$transport" == "dnstt" && -f "$DNSTT_KEYS_DIR/server.pub" ]]; then
                            echo -e "  Public Key: $(cat "$DNSTT_KEYS_DIR/server.pub")"
                        fi
                    else
                        echo -e "  Domain: Configured via custom domain"
                    fi
                    ;;
            esac
            safe_read "" dummy
            ;;
        0) return ;;
    esac
}

# ========== SOCKS5 USER MANAGER (KAMILI) ==========
_get_socks5_user_status() {
    local username="$1"
    local line=$(grep "^$username:" "$SOCKS5_USERS_DB" 2>/dev/null)
    [[ -z "$line" ]] && echo -e "${C_RED}Not Found${C_RESET}" && return
    
    local expiry=$(echo "$line" | cut -d: -f3)
    local status=$(echo "$line" | cut -d: -f7)
    [[ -z "$status" ]] && status="ACTIVE"
    
    local current_ts=$(date +%s)
    local expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
    
    if [[ "$status" == "LOCKED" ]]; then
        echo -e "${C_YELLOW}🔒 Locked${C_RESET}"
    elif [[ $expiry_ts -lt $current_ts && $expiry_ts -ne 0 ]]; then
        echo -e "${C_RED}🗓️ Expired${C_RESET}"
    else
        echo -e "${C_GREEN}🟢 Active${C_RESET}"
    fi
}

_create_socks5_user() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ✨ Create SOCKS5 User ---${C_RESET}"
    
    read -p "👉 Enter username (or '0' to cancel): " username
    [[ "$username" == "0" ]] && return
    [[ -z "$username" ]] && echo -e "\n${C_RED}❌ Username cannot be empty${C_RESET}" && return
    
    if grep -q "^$username:" "$SOCKS5_USERS_DB" 2>/dev/null; then
        echo -e "\n${C_RED}❌ User already exists${C_RESET}" && return
    fi
    
    local password=""
    read -p "🔑 Enter password (or Enter for auto-generated): " password
    if [[ -z "$password" ]]; then
        password=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)
        echo -e "${C_GREEN}🔑 Auto-generated: ${C_YELLOW}$password${C_RESET}"
    fi
    
    read -p "🗓️ Account duration (days) [30]: " days
    days=${days:-30}
    [[ ! "$days" =~ ^[0-9]+$ ]] && echo -e "\n${C_RED}❌ Invalid number${C_RESET}" && return
    
    read -p "📶 Connection limit [1]: " limit
    limit=${limit:-1}
    [[ ! "$limit" =~ ^[0-9]+$ ]] && echo -e "\n${C_RED}❌ Invalid number${C_RESET}" && return
    
    read -p "📦 Bandwidth limit (GB, 0=unlimited) [0]: " bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    
    local expire_date=$(date -d "+$days days" +%Y-%m-%d)
    
    echo "$username:$password:$expire_date:$limit:$bandwidth_gb:0:ACTIVE" >> "$SOCKS5_USERS_DB"
    
    _update_socks5_dante_config
    
    echo -e "\n${C_GREEN}✅ SOCKS5 user '$username' created!${C_RESET}"
    echo -e "  - 👤 Username: ${C_YELLOW}$username${C_RESET}"
    echo -e "  - 🔑 Password: ${C_YELLOW}$password${C_RESET}"
    echo -e "  - 🗓️ Expires: ${C_YELLOW}$expire_date${C_RESET}"
    echo -e "  - 📶 Max Connections: ${C_YELLOW}$limit${C_RESET}"
    echo -e "  - 📦 Bandwidth: ${C_YELLOW}$([[ $bandwidth_gb -eq 0 ]] && echo "Unlimited" || echo "${bandwidth_gb} GB")${C_RESET}"
    
    safe_read "" dummy
}

_list_socks5_users() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📋 SOCKS5 Users List ---${C_RESET}"
    echo -e "${C_CYAN}=========================================================================================${C_RESET}"
    printf "${C_BOLD}${C_WHITE}%-18s | %-12s | %-10s | %-15s | %-20s${C_RESET}\n" "USERNAME" "EXPIRES" "CONNS" "BANDWIDTH" "STATUS"
    echo -e "${C_CYAN}-----------------------------------------------------------------------------------------${C_RESET}"
    
    if [[ ! -s "$SOCKS5_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No SOCKS5 users found${C_RESET}"
    else
        while IFS=: read -r user pass expiry limit bandwidth_gb traffic_used status; do
            [[ -z "$user" ]] && continue
            bandwidth_gb=${bandwidth_gb:-0}
            traffic_used=${traffic_used:-0}
            status=${status:-ACTIVE}
            
            local online_count=0
            local conn_string="$online_count / $limit"
            local bw_string="Unlimited"
            [[ "$bandwidth_gb" != "0" ]] && bw_string="${traffic_used}/${bandwidth_gb} GB"
            
            local status_text=$(_get_socks5_user_status "$user")
            
            printf "${C_WHITE}%-18s ${C_RESET}| ${C_YELLOW}%-12s ${C_RESET}| ${C_CYAN}%-10s ${C_RESET}| ${C_ORANGE}%-15s ${C_RESET}| %-20s\n" \
                "$user" "$expiry" "$conn_string" "$bw_string" "$status_text"
        done < "$SOCKS5_USERS_DB"
    fi
    
    echo -e "${C_CYAN}=========================================================================================${C_RESET}\n"
    safe_read "" dummy
}

_edit_socks5_user() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ✏️ Edit SOCKS5 User ---${C_RESET}"
    
    read -p "👉 Enter username to edit: " username
    local line=$(grep "^$username:" "$SOCKS5_USERS_DB" 2>/dev/null)
    if [[ -z "$line" ]]; then
        echo -e "\n${C_RED}❌ User not found${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    local old_pass=$(echo "$line" | cut -d: -f2)
    local old_expiry=$(echo "$line" | cut -d: -f3)
    local old_limit=$(echo "$line" | cut -d: -f4)
    local old_bw=$(echo "$line" | cut -d: -f5)
    local old_used=$(echo "$line" | cut -d: -f6)
    local old_status=$(echo "$line" | cut -d: -f7)
    
    echo -e "\n${C_CYAN}Current values:${C_RESET}"
    echo -e "  Password: ${C_YELLOW}$old_pass${C_RESET}"
    echo -e "  Expires: ${C_YELLOW}$old_expiry${C_RESET}"
    echo -e "  Connection limit: ${C_YELLOW}$old_limit${C_RESET}"
    echo -e "  Bandwidth: ${C_YELLOW}$([[ $old_bw -eq 0 ]] && echo "Unlimited" || echo "${old_bw} GB")${C_RESET}"
    echo -e "  Status: ${C_YELLOW}$old_status${C_RESET}"
    
    echo -e "\n${C_CYAN}Leave empty to keep current value${C_RESET}"
    
    read -p "🔑 New password: " new_pass
    [[ -z "$new_pass" ]] && new_pass="$old_pass"
    
    read -p "🗓️ New expiry (YYYY-MM-DD) or +days: " new_expiry
    if [[ -z "$new_expiry" ]]; then
        new_expiry="$old_expiry"
    elif [[ "$new_expiry" =~ ^\+[0-9]+$ ]]; then
        days=${new_expiry#+}
        new_expiry=$(date -d "+$days days" +%Y-%m-%d)
    fi
    
    read -p "📶 New connection limit: " new_limit
    [[ -z "$new_limit" ]] && new_limit="$old_limit"
    
    read -p "📦 New bandwidth limit (GB, 0=unlimited): " new_bw
    [[ -z "$new_bw" ]] && new_bw="$old_bw"
    
    read -p "🔒 New status (ACTIVE/LOCKED): " new_status
    [[ -z "$new_status" ]] && new_status="$old_status"
    
    sed -i "/^$username:/d" "$SOCKS5_USERS_DB"
    echo "$username:$new_pass:$new_expiry:$new_limit:$new_bw:$old_used:$new_status" >> "$SOCKS5_USERS_DB"
    
    _update_socks5_dante_config
    
    echo -e "\n${C_GREEN}✅ SOCKS5 user '$username' updated!${C_RESET}"
    safe_read "" dummy
}

_lock_socks5_user() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔒 Lock SOCKS5 User ---${C_RESET}"
    
    read -p "👉 Enter username to lock: " username
    local line=$(grep "^$username:" "$SOCKS5_USERS_DB" 2>/dev/null)
    if [[ -z "$line" ]]; then
        echo -e "\n${C_RED}❌ User not found${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    local pass=$(echo "$line" | cut -d: -f2)
    local expiry=$(echo "$line" | cut -d: -f3)
    local limit=$(echo "$line" | cut -d: -f4)
    local bw=$(echo "$line" | cut -d: -f5)
    local used=$(echo "$line" | cut -d: -f6)
    
    sed -i "/^$username:/d" "$SOCKS5_USERS_DB"
    echo "$username:$pass:$expiry:$limit:$bw:$used:LOCKED" >> "$SOCKS5_USERS_DB"
    
    _update_socks5_dante_config
    
    echo -e "\n${C_GREEN}✅ SOCKS5 user '$username' locked${C_RESET}"
    safe_read "" dummy
}

_unlock_socks5_user() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔓 Unlock SOCKS5 User ---${C_RESET}"
    
    read -p "👉 Enter username to unlock: " username
    local line=$(grep "^$username:.*LOCKED" "$SOCKS5_USERS_DB" 2>/dev/null)
    if [[ -z "$line" ]]; then
        echo -e "\n${C_YELLOW}⚠️ User not found or not locked${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    local pass=$(echo "$line" | cut -d: -f2)
    local expiry=$(echo "$line" | cut -d: -f3)
    local limit=$(echo "$line" | cut -d: -f4)
    local bw=$(echo "$line" | cut -d: -f5)
    local used=$(echo "$line" | cut -d: -f6)
    
    sed -i "/^$username:/d" "$SOCKS5_USERS_DB"
    echo "$username:$pass:$expiry:$limit:$bw:$used:ACTIVE" >> "$SOCKS5_USERS_DB"
    
    _update_socks5_dante_config
    
    echo -e "\n${C_GREEN}✅ SOCKS5 user '$username' unlocked${C_RESET}"
    safe_read "" dummy
}

_renew_socks5_user() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔄 Renew SOCKS5 User ---${C_RESET}"
    
    read -p "👉 Enter username to renew: " username
    local line=$(grep "^$username:" "$SOCKS5_USERS_DB" 2>/dev/null)
    if [[ -z "$line" ]]; then
        echo -e "\n${C_RED}❌ User not found${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    read -p "👉 Add how many days? " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "\n${C_RED}❌ Invalid number${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    local pass=$(echo "$line" | cut -d: -f2)
    local old_expiry=$(echo "$line" | cut -d: -f3)
    local limit=$(echo "$line" | cut -d: -f4)
    local bw=$(echo "$line" | cut -d: -f5)
    local used=$(echo "$line" | cut -d: -f6)
    local status=$(echo "$line" | cut -d: -f7)
    
    local new_expiry=$(date -d "$old_expiry + $days days" +%Y-%m-%d)
    
    sed -i "/^$username:/d" "$SOCKS5_USERS_DB"
    echo "$username:$pass:$new_expiry:$limit:$bw:$used:$status" >> "$SOCKS5_USERS_DB"
    
    _update_socks5_dante_config
    
    echo -e "\n${C_GREEN}✅ SOCKS5 user '$username' renewed until $new_expiry${C_RESET}"
    safe_read "" dummy
}

_delete_socks5_user() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Delete SOCKS5 User ---${C_RESET}"
    
    read -p "👉 Enter username to delete: " username
    if ! grep -q "^$username:" "$SOCKS5_USERS_DB" 2>/dev/null; then
        echo -e "\n${C_RED}❌ User not found${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    read -p "👉 Are you sure? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        sed -i "/^$username:/d" "$SOCKS5_USERS_DB"
        _update_socks5_dante_config
        echo -e "\n${C_GREEN}✅ SOCKS5 user '$username' deleted${C_RESET}"
    fi
    safe_read "" dummy
}

_view_socks5_bandwidth() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📊 SOCKS5 Bandwidth Details ---${C_RESET}"
    
    read -p "👉 Enter username: " username
    local line=$(grep "^$username:" "$SOCKS5_USERS_DB" 2>/dev/null)
    if [[ -z "$line" ]]; then
        echo -e "\n${C_RED}❌ User not found${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    local bandwidth_gb=$(echo "$line" | cut -d: -f5)
    local traffic_used=$(echo "$line" | cut -d: -f6)
    [[ -z "$bandwidth_gb" ]] && bandwidth_gb="0"
    [[ -z "$traffic_used" ]] && traffic_used="0"
    
    echo -e "\n  ${C_CYAN}Data Used:${C_RESET}        ${C_WHITE}${traffic_used} GB${C_RESET}"
    
    if [[ "$bandwidth_gb" == "0" ]]; then
        echo -e "  ${C_CYAN}Bandwidth Limit:${C_RESET}  ${C_GREEN}Unlimited${C_RESET}"
    else
        local percentage=$(echo "scale=1; $traffic_used * 100 / $bandwidth_gb" | bc 2>/dev/null || echo "0")
        echo -e "  ${C_CYAN}Bandwidth Limit:${C_RESET}  ${C_YELLOW}${bandwidth_gb} GB${C_RESET}"
        echo -e "  ${C_CYAN}Usage:${C_RESET}            ${C_WHITE}${percentage}%${C_RESET}"
    fi
    safe_read "" dummy
}

_reset_socks5_bandwidth() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔄 Reset SOCKS5 Bandwidth ---${C_RESET}"
    
    read -p "👉 Enter username: " username
    local line=$(grep "^$username:" "$SOCKS5_USERS_DB" 2>/dev/null)
    if [[ -z "$line" ]]; then
        echo -e "\n${C_RED}❌ User not found${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    read -p "👉 Are you sure? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        local pass=$(echo "$line" | cut -d: -f2)
        local expiry=$(echo "$line" | cut -d: -f3)
        local limit=$(echo "$line" | cut -d: -f4)
        local bw=$(echo "$line" | cut -d: -f5)
        local status=$(echo "$line" | cut -d: -f7)
        
        sed -i "/^$username:/d" "$SOCKS5_USERS_DB"
        echo "$username:$pass:$expiry:$limit:$bw:0:$status" >> "$SOCKS5_USERS_DB"
        
        echo -e "\n${C_GREEN}✅ Bandwidth counter reset to 0${C_RESET}"
    fi
    safe_read "" dummy
}

_generate_socks5_client_config() {
    local username=$1
    local password=$2
    
    # Get user details
    local line=$(grep "^$username:" "$SOCKS5_USERS_DB" 2>/dev/null)
    local expiry=$(echo "$line" | cut -d: -f3)
    local limit=$(echo "$line" | cut -d: -f4)
    local bandwidth_gb=$(echo "$line" | cut -d: -f5)
    
    local host_ip=$(curl -s -4 icanhazip.com)
    
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}           📱 SOCKS5 CLIENT CONNECTION CONFIGURATION${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    
    echo -e "${C_CYAN}========================================${C_RESET}"
    echo -e "${C_CYAN}👤 USER ACCOUNT DETAILS${C_RESET}"
    echo -e "${C_CYAN}========================================${C_RESET}"
    echo -e "   • Username: ${C_YELLOW}$username${C_RESET}"
    echo -e "   • Password: ${C_YELLOW}$password${C_RESET}"
    echo -e "   • Account Expiry: ${C_YELLOW}$expiry${C_RESET}"
    echo -e "   • Connection Limit: ${C_YELLOW}$limit${C_RESET}"
    echo -e "   • Bandwidth Limit: ${C_YELLOW}$([[ $bandwidth_gb -eq 0 ]] && echo "Unlimited" || echo "${bandwidth_gb} GB")${C_RESET}"
    echo -e "   • Server IP: ${C_YELLOW}$host_ip${C_RESET}"
    echo -e "${C_CYAN}========================================${C_RESET}"
    
    echo -e "\n${C_GREEN}🔹 SOCKS5 PROXY DIRECT:${C_RESET}"
    echo -e "   • Server: $host_ip"
    echo -e "   • Port: $SOCKS5_PORT"
    echo -e "   • Username: $username"
    echo -e "   • Password: $password"
    
    # DNSTT + SOCKS5
    if [[ -f "$DB_DIR/dnstt-socks_domain.txt" ]]; then
        local dnstt_domain=$(cat "$DB_DIR/dnstt-socks_domain.txt" 2>/dev/null)
        echo -e "\n${C_GREEN}🔹 DNSTT + SOCKS5 TUNNEL:${C_RESET}"
        echo -e "   • Domain: $dnstt_domain"
        echo -e "   • Port: 53 (UDP)"
        if [[ -f "$DNSTT_KEYS_DIR/server.pub" ]]; then
            local pubkey=$(cat "$DNSTT_KEYS_DIR/server.pub")
            echo -e "   • Public Key: ${pubkey:0:80}..."
        fi
        echo -e "   • SOCKS5 After Tunnel: 127.0.0.1:$SOCKS5_PORT"
        echo -e "   • Username: $username"
        echo -e "   • Password: $password"
    fi
    
    # Slipstream + SOCKS5
    if [[ -f "$DB_DIR/slip-socks_domain.txt" ]]; then
        local slip_domain=$(cat "$DB_DIR/slip-socks_domain.txt" 2>/dev/null)
        echo -e "\n${C_GREEN}🔹 SLIPSTREAM + SOCKS5 TUNNEL:${C_RESET}"
        echo -e "   • Domain: $slip_domain"
        echo -e "   • Port: 53 (UDP)"
        echo -e "   • SOCKS5 After Tunnel: 127.0.0.1:$SOCKS5_PORT"
        echo -e "   • Username: $username"
        echo -e "   • Password: $password"
    fi
    
    # VayDNS + SOCKS5
    if [[ -f "$DB_DIR/vay-socks_domain.txt" ]]; then
        local vay_domain=$(cat "$DB_DIR/vay-socks_domain.txt" 2>/dev/null)
        echo -e "\n${C_GREEN}🔹 VAYDNS + SOCKS5 TUNNEL:${C_RESET}"
        echo -e "   • Domain: $vay_domain"
        echo -e "   • Port: 53 (UDP)"
        echo -e "   • SOCKS5 After Tunnel: 127.0.0.1:$SOCKS5_PORT"
        echo -e "   • Username: $username"
        echo -e "   • Password: $password"
    fi
    
    # NoizDNS + SOCKS5
    if [[ -f "$DB_DIR/noiz-socks_domain.txt" ]]; then
        local noiz_domain=$(cat "$DB_DIR/noiz-socks_domain.txt" 2>/dev/null)
        echo -e "\n${C_GREEN}🔹 NOIZDNS + SOCKS5 TUNNEL:${C_RESET}"
        echo -e "   • Domain: $noiz_domain"
        echo -e "   • Port: 53 (UDP)"
        echo -e "   • SOCKS5 After Tunnel: 127.0.0.1:$SOCKS5_PORT"
        echo -e "   • Username: $username"
        echo -e "   • Password: $password"
    fi
    
    echo -e "\n${C_CYAN}========================================${C_RESET}"
    echo -e "${C_CYAN}📌 HOW TO USE:${C_RESET}"
    echo -e "   1. Connect to the DNS tunnel using any DNS tunneling client"
    echo -e "   2. Set your SOCKS5 proxy to 127.0.0.1:$SOCKS5_PORT"
    echo -e "   3. Use username/password above for authentication"
    echo -e "${C_CYAN}========================================${C_RESET}"
    
    safe_read "" dummy
}

_update_socks5_dante_config() {
    mkdir -p /etc/danted
    
    cat > /etc/danted/danted.conf << 'EOF'
logoutput: syslog
internal: 0.0.0.0 port=1080
external: eth0
method: username
user.privileged: root
user.notprivileged: nobody

client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    log: error
}

EOF
    
    while IFS=: read -r user pass expiry limit bw used status; do
        [[ -z "$user" ]] && continue
        if [[ "$status" != "LOCKED" ]]; then
            cat >> /etc/danted/danted.conf << EOF
pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
    protocol: tcp udp
    method: username
    user: $user
    log: error
    max_connections: $limit
}

EOF
        fi
    done < "$SOCKS5_USERS_DB"
    
    > /etc/danted/socks.passwd
    while IFS=: read -r user pass expiry limit bw used status; do
        [[ -z "$user" ]] && continue
        echo "$user:$pass" >> /etc/danted/socks.passwd
    done < "$SOCKS5_USERS_DB"
    
    if ! systemctl is-active --quiet danted 2>/dev/null; then
        systemctl start danted 2>/dev/null
        systemctl enable danted 2>/dev/null
    else
        systemctl restart danted 2>/dev/null
    fi
}

socks5_user_menu() {
    while true; do
        clear
        show_banner
        echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}              🔧 SOCKS5 USER MANAGER${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo ""
        echo -e "  SOCKS5 Proxy Status: $(systemctl is-active danted 2>/dev/null && echo "${C_GREEN}● RUNNING${C_RESET}" || echo "${C_RED}● STOPPED${C_RESET}")"
        echo ""
        echo -e "  ${C_GREEN}[1]${C_RESET} Create SOCKS5 User"
        echo -e "  ${C_GREEN}[2]${C_RESET} List SOCKS5 Users"
        echo -e "  ${C_GREEN}[3]${C_RESET} Edit SOCKS5 User"
        echo -e "  ${C_GREEN}[4]${C_RESET} Lock SOCKS5 User"
        echo -e "  ${C_GREEN}[5]${C_RESET} Unlock SOCKS5 User"
        echo -e "  ${C_GREEN}[6]${C_RESET} Renew SOCKS5 User"
        echo -e "  ${C_GREEN}[7]${C_RESET} Delete SOCKS5 User"
        echo -e "  ${C_GREEN}[8]${C_RESET} 📊 View Bandwidth Usage"
        echo -e "  ${C_GREEN}[9]${C_RESET} 🔄 Reset Bandwidth Counter"
        echo -e "  ${C_GREEN}[10]${C_RESET} 📱 Generate Client Config"
        echo -e "  ${C_RED}[0]${C_RESET} Return"
        echo ""
        
        read -p "$(echo -e ${C_PROMPT}"👉 Select option: "${C_RESET})" choice
        
        case $choice in
            1) _create_socks5_user ;;
            2) _list_socks5_users ;;
            3) _edit_socks5_user ;;
            4) _lock_socks5_user ;;
            5) _unlock_socks5_user ;;
            6) _renew_socks5_user ;;
            7) _delete_socks5_user ;;
            8) _view_socks5_bandwidth ;;
            9) _reset_socks5_bandwidth ;;
            10) 
                read -p "👉 Enter username: " u
                local pass=$(grep "^$u:" "$SOCKS5_USERS_DB" | cut -d: -f2)
                _generate_socks5_client_config "$u" "$pass"
                safe_read "" dummy ;;
            0) return ;;
            *) echo -e "\n${C_RED}❌ Invalid option${C_RESET}"; sleep 2 ;;
        esac
    done
}

# ========== SSH USER MANAGER (KAMILI) ==========
_get_ssh_user_status() {
    local username="$1"
    local line=$(grep "^$username:" "$SSH_USERS_DB" 2>/dev/null)
    [[ -z "$line" ]] && echo -e "${C_RED}Not Found${C_RESET}" && return
    
    local expiry=$(echo "$line" | cut -d: -f3)
    local status=$(echo "$line" | cut -d: -f7)
    [[ -z "$status" ]] && status="ACTIVE"
    
    local current_ts=$(date +%s)
    local expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
    
    if [[ "$status" == "LOCKED" ]]; then
        echo -e "${C_YELLOW}🔒 Locked${C_RESET}"
    elif [[ $expiry_ts -lt $current_ts && $expiry_ts -ne 0 ]]; then
        echo -e "${C_RED}🗓️ Expired${C_RESET}"
    else
        echo -e "${C_GREEN}🟢 Active${C_RESET}"
    fi
}

_get_ssh_connection_count() {
    local username="$1"
    pgrep -c -u "$username" sshd 2>/dev/null
}

_create_ssh_user() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ✨ Create SSH User ---${C_RESET}"
    
    read -p "👉 Enter username (or '0' to cancel): " username
    [[ "$username" == "0" ]] && return
    [[ -z "$username" ]] && echo -e "\n${C_RED}❌ Username cannot be empty${C_RESET}" && return
    
    if id "$username" &>/dev/null || grep -q "^$username:" "$SSH_USERS_DB" 2>/dev/null; then
        echo -e "\n${C_RED}❌ User already exists${C_RESET}" && return
    fi
    
    local password=""
    read -p "🔑 Enter password (or Enter for auto-generated): " password
    if [[ -z "$password" ]]; then
        password=$(head /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 8)
        echo -e "${C_GREEN}🔑 Auto-generated: ${C_YELLOW}$password${C_RESET}"
    fi
    
    read -p "🗓️ Account duration (days) [30]: " days
    days=${days:-30}
    [[ ! "$days" =~ ^[0-9]+$ ]] && echo -e "\n${C_RED}❌ Invalid number${C_RESET}" && return
    
    read -p "📶 Connection limit [1]: " limit
    limit=${limit:-1}
    [[ ! "$limit" =~ ^[0-9]+$ ]] && echo -e "\n${C_RED}❌ Invalid number${C_RESET}" && return
    
    read -p "📦 Bandwidth limit (GB, 0=unlimited) [0]: " bandwidth_gb
    bandwidth_gb=${bandwidth_gb:-0}
    
    local expire_date=$(date -d "+$days days" +%Y-%m-%d)
    
    useradd -m -s /usr/sbin/nologin "$username"
    echo "$username:$password" | chpasswd
    chage -E "$expire_date" "$username"
    
    echo "$username:$password:$expire_date:$limit:$bandwidth_gb:0:ACTIVE" >> "$SSH_USERS_DB"
    
    echo -e "\n${C_GREEN}✅ SSH user '$username' created!${C_RESET}"
    echo -e "  - 👤 Username: ${C_YELLOW}$username${C_RESET}"
    echo -e "  - 🔑 Password: ${C_YELLOW}$password${C_RESET}"
    echo -e "  - 🗓️ Expires: ${C_YELLOW}$expire_date${C_RESET}"
    echo -e "  - 📶 Max Connections: ${C_YELLOW}$limit${C_RESET}"
    echo -e "  - 📦 Bandwidth: ${C_YELLOW}$([[ $bandwidth_gb -eq 0 ]] && echo "Unlimited" || echo "${bandwidth_gb} GB")${C_RESET}"
    
    safe_read "" dummy
}

_list_ssh_users() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📋 SSH Users List ---${C_RESET}"
    echo -e "${C_CYAN}=========================================================================================${C_RESET}"
    printf "${C_BOLD}${C_WHITE}%-18s | %-12s | %-10s | %-15s | %-20s${C_RESET}\n" "USERNAME" "EXPIRES" "CONNS" "BANDWIDTH" "STATUS"
    echo -e "${C_CYAN}-----------------------------------------------------------------------------------------${C_RESET}"
    
    if [[ ! -s "$SSH_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No SSH users found${C_RESET}"
    else
        while IFS=: read -r user pass expiry limit bandwidth_gb traffic_used status; do
            [[ -z "$user" ]] && continue
            bandwidth_gb=${bandwidth_gb:-0}
            traffic_used=${traffic_used:-0}
            status=${status:-ACTIVE}
            
            local online_count=$(_get_ssh_connection_count "$user")
            local conn_string="$online_count / $limit"
            local bw_string="Unlimited"
            [[ "$bandwidth_gb" != "0" ]] && bw_string="${traffic_used}/${bandwidth_gb} GB"
            
            local status_text=$(_get_ssh_user_status "$user")
            
            printf "${C_WHITE}%-18s ${C_RESET}| ${C_YELLOW}%-12s ${C_RESET}| ${C_CYAN}%-10s ${C_RESET}| ${C_ORANGE}%-15s ${C_RESET}| %-20s\n" \
                "$user" "$expiry" "$conn_string" "$bw_string" "$status_text"
        done < "$SSH_USERS_DB"
    fi
    
    echo -e "${C_CYAN}=========================================================================================${C_RESET}\n"
    safe_read "" dummy
}

_edit_ssh_user() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- ✏️ Edit SSH User ---${C_RESET}"
    
    read -p "👉 Enter username to edit: " username
    local line=$(grep "^$username:" "$SSH_USERS_DB" 2>/dev/null)
    if [[ -z "$line" ]]; then
        echo -e "\n${C_RED}❌ User not found${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    if ! id "$username" &>/dev/null; then
        echo -e "\n${C_RED}❌ System user does not exist${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    local old_pass=$(echo "$line" | cut -d: -f2)
    local old_expiry=$(echo "$line" | cut -d: -f3)
    local old_limit=$(echo "$line" | cut -d: -f4)
    local old_bw=$(echo "$line" | cut -d: -f5)
    local old_used=$(echo "$line" | cut -d: -f6)
    local old_status=$(echo "$line" | cut -d: -f7)
    
    echo -e "\n${C_CYAN}Current values:${C_RESET}"
    echo -e "  Password: ${C_YELLOW}$old_pass${C_RESET}"
    echo -e "  Expires: ${C_YELLOW}$old_expiry${C_RESET}"
    echo -e "  Connection limit: ${C_YELLOW}$old_limit${C_RESET}"
    echo -e "  Bandwidth: ${C_YELLOW}$([[ $old_bw -eq 0 ]] && echo "Unlimited" || echo "${old_bw} GB")${C_RESET}"
    echo -e "  Status: ${C_YELLOW}$old_status${C_RESET}"
    
    echo -e "\n${C_CYAN}Leave empty to keep current value${C_RESET}"
    
    read -p "🔑 New password: " new_pass
    [[ -z "$new_pass" ]] && new_pass="$old_pass"
    
    read -p "🗓️ New expiry (YYYY-MM-DD) or +days: " new_expiry
    if [[ -z "$new_expiry" ]]; then
        new_expiry="$old_expiry"
    elif [[ "$new_expiry" =~ ^\+[0-9]+$ ]]; then
        days=${new_expiry#+}
        new_expiry=$(date -d "+$days days" +%Y-%m-%d)
    fi
    
    read -p "📶 New connection limit: " new_limit
    [[ -z "$new_limit" ]] && new_limit="$old_limit"
    
    read -p "📦 New bandwidth limit (GB, 0=unlimited): " new_bw
    [[ -z "$new_bw" ]] && new_bw="$old_bw"
    
    read -p "🔒 New status (ACTIVE/LOCKED): " new_status
    [[ -z "$new_status" ]] && new_status="$old_status"
    
    echo "$username:$new_pass" | chpasswd
    chage -E "$new_expiry" "$username"
    
    if [[ "$new_status" == "LOCKED" ]]; then
        usermod -L "$username"
    else
        usermod -U "$username"
    fi
    
    sed -i "/^$username:/d" "$SSH_USERS_DB"
    echo "$username:$new_pass:$new_expiry:$new_limit:$new_bw:$old_used:$new_status" >> "$SSH_USERS_DB"
    
    echo -e "\n${C_GREEN}✅ SSH user '$username' updated!${C_RESET}"
    safe_read "" dummy
}

_lock_ssh_user() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔒 Lock SSH User ---${C_RESET}"
    
    read -p "👉 Enter username to lock: " username
    local line=$(grep "^$username:" "$SSH_USERS_DB" 2>/dev/null)
    if [[ -z "$line" ]]; then
        echo -e "\n${C_RED}❌ User not found${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    if ! id "$username" &>/dev/null; then
        echo -e "\n${C_RED}❌ System user does not exist${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    usermod -L "$username"
    killall -u "$username" -9 2>/dev/null
    
    local pass=$(echo "$line" | cut -d: -f2)
    local expiry=$(echo "$line" | cut -d: -f3)
    local limit=$(echo "$line" | cut -d: -f4)
    local bw=$(echo "$line" | cut -d: -f5)
    local used=$(echo "$line" | cut -d: -f6)
    
    sed -i "/^$username:/d" "$SSH_USERS_DB"
    echo "$username:$pass:$expiry:$limit:$bw:$used:LOCKED" >> "$SSH_USERS_DB"
    
    echo -e "\n${C_GREEN}✅ SSH user '$username' locked${C_RESET}"
    safe_read "" dummy
}

_unlock_ssh_user() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔓 Unlock SSH User ---${C_RESET}"
    
    read -p "👉 Enter username to unlock: " username
    local line=$(grep "^$username:.*LOCKED" "$SSH_USERS_DB" 2>/dev/null)
    if [[ -z "$line" ]]; then
        echo -e "\n${C_YELLOW}⚠️ User not found or not locked${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    if ! id "$username" &>/dev/null; then
        echo -e "\n${C_RED}❌ System user does not exist${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    usermod -U "$username"
    
    local pass=$(echo "$line" | cut -d: -f2)
    local expiry=$(echo "$line" | cut -d: -f3)
    local limit=$(echo "$line" | cut -d: -f4)
    local bw=$(echo "$line" | cut -d: -f5)
    local used=$(echo "$line" | cut -d: -f6)
    
    sed -i "/^$username:/d" "$SSH_USERS_DB"
    echo "$username:$pass:$expiry:$limit:$bw:$used:ACTIVE" >> "$SSH_USERS_DB"
    
    echo -e "\n${C_GREEN}✅ SSH user '$username' unlocked${C_RESET}"
    safe_read "" dummy
}

_renew_ssh_user() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔄 Renew SSH User ---${C_RESET}"
    
    read -p "👉 Enter username to renew: " username
    local line=$(grep "^$username:" "$SSH_USERS_DB" 2>/dev/null)
    if [[ -z "$line" ]]; then
        echo -e "\n${C_RED}❌ User not found${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    if ! id "$username" &>/dev/null; then
        echo -e "\n${C_RED}❌ System user does not exist${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    read -p "👉 Add how many days? " days
    if ! [[ "$days" =~ ^[0-9]+$ ]]; then
        echo -e "\n${C_RED}❌ Invalid number${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    local pass=$(echo "$line" | cut -d: -f2)
    local old_expiry=$(echo "$line" | cut -d: -f3)
    local limit=$(echo "$line" | cut -d: -f4)
    local bw=$(echo "$line" | cut -d: -f5)
    local used=$(echo "$line" | cut -d: -f6)
    local status=$(echo "$line" | cut -d: -f7)
    
    local new_expiry=$(date -d "$old_expiry + $days days" +%Y-%m-%d)
    
    chage -E "$new_expiry" "$username"
    
    sed -i "/^$username:/d" "$SSH_USERS_DB"
    echo "$username:$pass:$new_expiry:$limit:$bw:$used:$status" >> "$SSH_USERS_DB"
    
    echo -e "\n${C_GREEN}✅ SSH user '$username' renewed until $new_expiry${C_RESET}"
    safe_read "" dummy
}

_delete_ssh_user() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🗑️ Delete SSH User ---${C_RESET}"
    
    read -p "👉 Enter username to delete: " username
    if ! grep -q "^$username:" "$SSH_USERS_DB" 2>/dev/null; then
        echo -e "\n${C_RED}❌ User not found${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    read -p "👉 Are you sure? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        killall -u "$username" -9 2>/dev/null
        userdel -r "$username" 2>/dev/null
        
        sed -i "/^$username:/d" "$SSH_USERS_DB"
        
        echo -e "\n${C_GREEN}✅ SSH user '$username' deleted${C_RESET}"
    fi
    safe_read "" dummy
}

_view_ssh_bandwidth() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 📊 SSH Bandwidth Details ---${C_RESET}"
    
    read -p "👉 Enter username: " username
    local line=$(grep "^$username:" "$SSH_USERS_DB" 2>/dev/null)
    if [[ -z "$line" ]]; then
        echo -e "\n${C_RED}❌ User not found${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    local bandwidth_gb=$(echo "$line" | cut -d: -f5)
    local traffic_used=$(echo "$line" | cut -d: -f6)
    [[ -z "$bandwidth_gb" ]] && bandwidth_gb="0"
    [[ -z "$traffic_used" ]] && traffic_used="0"
    
    echo -e "\n  ${C_CYAN}Data Used:${C_RESET}        ${C_WHITE}${traffic_used} GB${C_RESET}"
    
    if [[ "$bandwidth_gb" == "0" ]]; then
        echo -e "  ${C_CYAN}Bandwidth Limit:${C_RESET}  ${C_GREEN}Unlimited${C_RESET}"
    else
        local percentage=$(echo "scale=1; $traffic_used * 100 / $bandwidth_gb" | bc 2>/dev/null || echo "0")
        echo -e "  ${C_CYAN}Bandwidth Limit:${C_RESET}  ${C_YELLOW}${bandwidth_gb} GB${C_RESET}"
        echo -e "  ${C_CYAN}Usage:${C_RESET}            ${C_WHITE}${percentage}%${C_RESET}"
    fi
    safe_read "" dummy
}

_reset_ssh_bandwidth() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}--- 🔄 Reset SSH Bandwidth ---${C_RESET}"
    
    read -p "👉 Enter username: " username
    local line=$(grep "^$username:" "$SSH_USERS_DB" 2>/dev/null)
    if [[ -z "$line" ]]; then
        echo -e "\n${C_RED}❌ User not found${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    read -p "👉 Are you sure? (y/n): " confirm
    if [[ "$confirm" == "y" ]]; then
        local pass=$(echo "$line" | cut -d: -f2)
        local expiry=$(echo "$line" | cut -d: -f3)
        local limit=$(echo "$line" | cut -d: -f4)
        local bw=$(echo "$line" | cut -d: -f5)
        local status=$(echo "$line" | cut -d: -f7)
        
        sed -i "/^$username:/d" "$SSH_USERS_DB"
        echo "$username:$pass:$expiry:$limit:$bw:0:$status" >> "$SSH_USERS_DB"
        
        echo -e "\n${C_GREEN}✅ Bandwidth counter reset to 0${C_RESET}"
    fi
    safe_read "" dummy
}

_generate_ssh_client_config() {
    local username=$1
    local password=$2
    
    local line=$(grep "^$username:" "$SSH_USERS_DB" 2>/dev/null)
    local expiry=$(echo "$line" | cut -d: -f3)
    local limit=$(echo "$line" | cut -d: -f4)
    local bandwidth_gb=$(echo "$line" | cut -d: -f5)
    
    local host_ip=$(curl -s -4 icanhazip.com)
    
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}           📱 SSH CLIENT CONNECTION CONFIGURATION${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    
    echo -e "${C_CYAN}========================================${C_RESET}"
    echo -e "${C_CYAN}👤 USER ACCOUNT DETAILS${C_RESET}"
    echo -e "${C_CYAN}========================================${C_RESET}"
    echo -e "   • Username: ${C_YELLOW}$username${C_RESET}"
    echo -e "   • Password: ${C_YELLOW}$password${C_RESET}"
    echo -e "   • Account Expiry: ${C_YELLOW}$expiry${C_RESET}"
    echo -e "   • Connection Limit: ${C_YELLOW}$limit${C_RESET}"
    echo -e "   • Bandwidth Limit: ${C_YELLOW}$([[ $bandwidth_gb -eq 0 ]] && echo "Unlimited" || echo "${bandwidth_gb} GB")${C_RESET}"
    echo -e "   • Server IP: ${C_YELLOW}$host_ip${C_RESET}"
    echo -e "${C_CYAN}========================================${C_RESET}"
    
    echo -e "\n${C_GREEN}🔹 SSH DIRECT CONNECTION:${C_RESET}"
    echo -e "   • Host: $host_ip"
    echo -e "   • Port: $SSH_PORT"
    echo -e "   • Username: $username"
    echo -e "   • Password: $password"
    
    if [[ -f "$DB_DIR/dnstt-ssh_domain.txt" ]]; then
        local dnstt_domain=$(cat "$DB_DIR/dnstt-ssh_domain.txt" 2>/dev/null)
        echo -e "\n${C_GREEN}🔹 DNSTT + SSH TUNNEL:${C_RESET}"
        echo -e "   • Domain: $dnstt_domain"
        echo -e "   • Port: 53 (UDP)"
        if [[ -f "$DNSTT_KEYS_DIR/server.pub" ]]; then
            local pubkey=$(cat "$DNSTT_KEYS_DIR/server.pub")
            echo -e "   • Public Key: ${pubkey:0:80}..."
        fi
        echo -e "   • Username: $username"
        echo -e "   • Password: $password"
    fi
    
    if [[ -f "$DB_DIR/slip-ssh_domain.txt" ]]; then
        local slip_domain=$(cat "$DB_DIR/slip-ssh_domain.txt" 2>/dev/null)
        echo -e "\n${C_GREEN}🔹 SLIPSTREAM + SSH TUNNEL:${C_RESET}"
        echo -e "   • Domain: $slip_domain"
        echo -e "   • Port: 53 (UDP)"
        echo -e "   • Username: $username"
        echo -e "   • Password: $password"
    fi
    
    if [[ -f "$DB_DIR/vay-ssh_domain.txt" ]]; then
        local vay_domain=$(cat "$DB_DIR/vay-ssh_domain.txt" 2>/dev/null)
        echo -e "\n${C_GREEN}🔹 VAYDNS + SSH TUNNEL:${C_RESET}"
        echo -e "   • Domain: $vay_domain"
        echo -e "   • Port: 53 (UDP)"
        echo -e "   • Username: $username"
        echo -e "   • Password: $password"
    fi
    
    if [[ -f "$DB_DIR/noiz-ssh_domain.txt" ]]; then
        local noiz_domain=$(cat "$DB_DIR/noiz-ssh_domain.txt" 2>/dev/null)
        echo -e "\n${C_GREEN}🔹 NOIZDNS + SSH TUNNEL:${C_RESET}"
        echo -e "   • Domain: $noiz_domain"
        echo -e "   • Port: 53 (UDP)"
        echo -e "   • Username: $username"
        echo -e "   • Password: $password"
    fi
    
    echo -e "\n${C_CYAN}========================================${C_RESET}"
    echo -e "${C_CYAN}📌 CLIENT COMMAND (DNSTT):${C_RESET}"
    if [[ -f "$DB_DIR/dnstt-ssh_domain.txt" && -f "$DNSTT_KEYS_DIR/server.pub" ]]; then
        local dnstt_domain=$(cat "$DB_DIR/dnstt-ssh_domain.txt")
        local pubkey=$(cat "$DNSTT_KEYS_DIR/server.pub")
        echo -e "   dnstt-client -udp 8.8.8.8:53 \\"
        echo -e "     -pubkey \"$pubkey\" \\"
        echo -e "     $dnstt_domain \\"
        echo -e "     127.0.0.1:$SSH_PORT"
    fi
    echo -e "${C_CYAN}========================================${C_RESET}"
    
    safe_read "" dummy
}

ssh_user_menu() {
    while true; do
        clear
        show_banner
        echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}              🔧 SSH USER MANAGER${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo ""
        echo -e "  SSH Service Status: $(systemctl is-active ssh 2>/dev/null && echo "${C_GREEN}● RUNNING${C_RESET}" || echo "${C_RED}● STOPPED${C_RESET}")"
        echo ""
        echo -e "  ${C_GREEN}[1]${C_RESET} Create SSH User"
        echo -e "  ${C_GREEN}[2]${C_RESET} List SSH Users"
        echo -e "  ${C_GREEN}[3]${C_RESET} Edit SSH User"
        echo -e "  ${C_GREEN}[4]${C_RESET} Lock SSH User"
        echo -e "  ${C_GREEN}[5]${C_RESET} Unlock SSH User"
        echo -e "  ${C_GREEN}[6]${C_RESET} Renew SSH User"
        echo -e "  ${C_GREEN}[7]${C_RESET} Delete SSH User"
        echo -e "  ${C_GREEN}[8]${C_RESET} 📊 View Bandwidth Usage"
        echo -e "  ${C_GREEN}[9]${C_RESET} 🔄 Reset Bandwidth Counter"
        echo -e "  ${C_GREEN}[10]${C_RESET} 📱 Generate Client Config"
        echo -e "  ${C_RED}[0]${C_RESET} Return"
        echo ""
        
        read -p "$(echo -e ${C_PROMPT}"👉 Select option: "${C_RESET})" choice
        
        case $choice in
            1) _create_ssh_user ;;
            2) _list_ssh_users ;;
            3) _edit_ssh_user ;;
            4) _lock_ssh_user ;;
            5) _unlock_ssh_user ;;
            6) _renew_ssh_user ;;
            7) _delete_ssh_user ;;
            8) _view_ssh_bandwidth ;;
            9) _reset_ssh_bandwidth ;;
            10) 
                read -p "👉 Enter username: " u
                local pass=$(grep "^$u:" "$SSH_USERS_DB" | cut -d: -f2)
                _generate_ssh_client_config "$u" "$pass"
                safe_read "" dummy ;;
            0) return ;;
            *) echo -e "\n${C_RED}❌ Invalid option${C_RESET}"; sleep 2 ;;
        esac
    done
}

# ========== AUTO SSH BANNER (FALCON STYLE) ==========
_connect_auto_banner_to_ssh() {
    echo -e "\n${C_BLUE}🔗 Connecting Auto HTML Banner to SSH...${C_RESET}"
    
    mkdir -p /etc/ssh/sshd_config.d
    mkdir -p "$SSH_BANNER_DIR"
    
    cat > "$SSHD_FF_CONFIG" << 'EOF'
# Voltron Tech Auto HTML Banner (Falcon Style)
Match User *
    Banner /etc/voltrontech/banners/%u.txt
EOF

    if ! grep -q "Include /etc/ssh/sshd_config.d/" /etc/ssh/sshd_config 2>/dev/null; then
        echo "Include /etc/ssh/sshd_config.d/*.conf" >> /etc/ssh/sshd_config
    fi
    
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
    
    echo -e "${C_GREEN}✅ Auto HTML Banner connected to SSH${C_RESET}"
}

_enable_auto_banner() {
    echo -e "\n${C_BLUE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BLUE}           🎨 ENABLING AUTO HTML BANNER (FALCON STYLE)${C_RESET}"
    echo -e "${C_BLUE}═══════════════════════════════════════════════════════════════${C_RESET}"
    
    touch "$BANNER_ENABLED_FILE"
    mkdir -p "$SSH_BANNER_DIR"
    
    _connect_auto_banner_to_ssh
    
    echo -e "${C_GREEN}✅ Auto HTML Banner enabled!${C_RESET}"
    echo -e "${C_CYAN}📌 Users will see account status when connecting via SSH tunnel${C_RESET}"
    safe_read "" dummy
}

_disable_auto_banner() {
    echo -e "\n${C_BLUE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BLUE}           🛑 DISABLING AUTO HTML BANNER${C_RESET}"
    echo -e "${C_BLUE}═══════════════════════════════════════════════════════════════${C_RESET}"
    
    rm -f "$BANNER_ENABLED_FILE"
    rm -f "$SSHD_FF_CONFIG"
    systemctl reload sshd 2>/dev/null || systemctl reload ssh 2>/dev/null
    
    echo -e "${C_GREEN}✅ Auto HTML Banner disabled!${C_RESET}"
    safe_read "" dummy
}

_view_auto_banner_status() {
    clear
    show_banner
    
    if [ ! -f "$BANNER_ENABLED_FILE" ]; then
        echo -e "${C_BOLD}${C_PURPLE}--- 🎨 Auto HTML Banner Status ---${C_RESET}"
        echo -e "\n${C_RED}❌ Auto HTML Banner is DISABLED${C_RESET}"
        echo -e "${C_YELLOW}Please enable it first from the Auto HTML Banner menu.${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    if [[ ! -s "$SSH_USERS_DB" ]]; then
        echo -e "${C_BOLD}${C_PURPLE}--- 🎨 Auto HTML Banner Status ---${C_RESET}"
        echo -e "\n${C_YELLOW}ℹ️ No users found in the database.${C_RESET}"
        safe_read "" dummy
        return
    fi
    
    echo -e "${C_BOLD}${C_PURPLE}--- 🎨 Auto HTML Banner Status ---${C_RESET}"
    echo -e "\n${C_GREEN}✅ Auto HTML Banner is ENABLED${C_RESET}"
    echo -e "${C_CYAN}📌 Users will see account status banner on SSH login${C_RESET}"
    
    local first_user=$(head -1 "$SSH_USERS_DB" | cut -d: -f1)
    if [[ -f "$SSH_BANNER_DIR/${first_user}.txt" ]]; then
        echo -e "\n${C_CYAN}--- Banner Preview for user '$first_user' ---${C_RESET}"
        cat "$SSH_BANNER_DIR/${first_user}.txt"
    fi
    
    safe_read "" dummy
}

auto_banner_menu() {
    while true; do
        clear
        show_banner
        
        local banner_status=""
        if [ -f "$BANNER_ENABLED_FILE" ]; then
            banner_status="${C_GREEN}ENABLED${C_RESET}"
        else
            banner_status="${C_RED}DISABLED${C_RESET}"
        fi
        
        echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}           🎨 AUTO HTML BANNER (FALCON STYLE)${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}           📱 For HTTP Custom / HTTP Injector${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo ""
        echo -e "  ${C_CYAN}Current Status:${C_RESET} $banner_status"
        echo ""
        echo -e "  ${C_GREEN}[1]${C_RESET} Enable Auto HTML Banner"
        echo -e "  ${C_RED}[2]${C_RESET} Disable Auto HTML Banner"
        echo -e "  ${C_GREEN}[3]${C_RESET} View Status & Sample Banner"
        echo ""
        echo -e "  ${C_RED}[0]${C_RESET} Return"
        echo ""
        
        local choice
        read -p "$(echo -e ${C_PROMPT}"👉 Select option: "${C_RESET})" choice
        
        case $choice in
            1) _enable_auto_banner ;;
            2) _disable_auto_banner ;;
            3) _view_auto_banner_status ;;
            0) return ;;
            *) echo -e "\n${C_RED}❌ Invalid option${C_RESET}"; sleep 2 ;;
        esac
    done
}

# ========== AUTO REBOOT MENU ==========
auto_reboot_menu() {
    while true; do
        clear
        show_banner
        
        local reboot_status=""
        if crontab -l 2>/dev/null | grep -q "reboot"; then
            reboot_status="${C_GREEN}ENABLED (Daily at 00:00)${C_RESET}"
        else
            reboot_status="${C_RED}DISABLED${C_RESET}"
        fi
        
        echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}           🔄 AUTO REBOOT MANAGEMENT${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo ""
        echo -e "  ${C_CYAN}Current Status:${C_RESET} $reboot_status"
        echo ""
        echo -e "  ${C_GREEN}[1]${C_RESET} Enable Auto Reboot (Daily at 00:00)"
        echo -e "  ${C_RED}[2]${C_RESET} Disable Auto Reboot"
        echo -e "  ${C_RED}[0]${C_RESET} Return"
        echo ""
        
        local choice
        read -p "$(echo -e ${C_PROMPT}"👉 Select option: "${C_RESET})" choice
        
        case $choice in
            1)
                (crontab -l 2>/dev/null | grep -v "reboot") | crontab - 2>/dev/null
                (crontab -l 2>/dev/null; echo "0 0 * * * /sbin/reboot") | crontab - 2>/dev/null
                echo -e "${C_GREEN}✅ Auto reboot enabled${C_RESET}"
                safe_read "" dummy ;;
            2)
                (crontab -l 2>/dev/null | grep -v "reboot") | crontab - 2>/dev/null
                echo -e "${C_GREEN}✅ Auto reboot disabled${C_RESET}"
                safe_read "" dummy ;;
            0) return ;;
        esac
    done
}

# ========== CACHE CLEANER MENU ==========
cache_cleaner_menu() {
    while true; do
        clear
        show_banner
        
        local cache_status=""
        if [ -f "$CACHE_CRON_FILE" ]; then
            cache_status="${C_GREEN}ENABLED${C_RESET}"
        else
            cache_status="${C_RED}DISABLED${C_RESET}"
        fi
        
        echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}           🧹 ADVANCED AUTO CACHE CLEANER${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo ""
        echo -e "  ${C_CYAN}Current Status:${C_RESET} $cache_status"
        echo -e "  ${C_CYAN}Schedule:${C_RESET} ${C_YELLOW}Daily at 12:00 AM (Midnight)${C_RESET}"
        echo ""
        echo -e "  ${C_GREEN}[1]${C_RESET} Enable Auto Clean"
        echo -e "  ${C_RED}[2]${C_RESET} Disable Auto Clean"
        echo -e "  ${C_RED}[0]${C_RESET} Return"
        echo ""
        
        local choice
        read -p "$(echo -e ${C_PROMPT}"👉 Select option: "${C_RESET})" choice
        
        case $choice in
            1)
                cat > "$CACHE_SCRIPT" << 'EOF'
#!/bin/bash
apt clean && apt autoclean && apt autoremove -y
journalctl --vacuum-time=3d
rm -f /var/log/*.gz /var/log/*.old
rm -rf /tmp/* /var/tmp/*
EOF
                chmod +x "$CACHE_SCRIPT"
                echo "0 0 * * * root $CACHE_SCRIPT" > "$CACHE_CRON_FILE"
                echo -e "${C_GREEN}✅ Auto cache cleaner enabled${C_RESET}"
                safe_read "" dummy ;;
            2)
                rm -f "$CACHE_CRON_FILE"
                echo -e "${C_GREEN}✅ Auto cache cleaner disabled${C_RESET}"
                safe_read "" dummy ;;
            0) return ;;
        esac
    done
}

# ========== BACKUP ==========
backup_config() {
    local backup_file="$BACKUP_DIR/voltron_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
    tar -czf "$backup_file" $DB_DIR 2>/dev/null
    echo -e "${C_GREEN}✅ Backup saved: $backup_file${C_RESET}"
    safe_read "" dummy
}

# ========== RESTORE ==========
restore_config() {
    echo -e "\n${C_CYAN}Available backups:${C_RESET}"
    ls -la "$BACKUP_DIR"/*.tar.gz 2>/dev/null || echo "No backups found"
    echo ""
    read -p "👉 Enter backup file path: " backup_file
    if [[ -f "$backup_file" ]]; then
        tar -xzf "$backup_file" -C / 2>/dev/null
        echo -e "${C_GREEN}✅ Restore complete${C_RESET}"
    else
        echo -e "${C_RED}❌ Backup not found${C_RESET}"
    fi
    safe_read "" dummy
}

# ========== LIVE MONITOR ==========
live_monitor() {
    local iface=$(ip -4 route | grep default | awk '{print $5}' | head -1)
    echo -e "\n${C_BLUE}⚡ Live Traffic Monitor on $iface (Ctrl+C to stop)${C_RESET}\n"
    
    rx1=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null)
    tx1=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null)
    
    while true; do
        sleep 2
        rx2=$(cat /sys/class/net/$iface/statistics/rx_bytes 2>/dev/null)
        tx2=$(cat /sys/class/net/$iface/statistics/tx_bytes 2>/dev/null)
        
        rx_diff=$(( (rx2 - rx1) / 1024 / 2 ))
        tx_diff=$(( (tx2 - tx1) / 1024 / 2 ))
        
        printf "\r⬇️ Download: %4d KB/s  ⬆️ Upload: %4d KB/s" "$rx_diff" "$tx_diff"
        
        rx1=$rx2; tx1=$tx2
    done
}

# ========== BLOCK TORRENT ==========
block_torrent() {
    iptables -A FORWARD -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null
    iptables -A FORWARD -m string --string ".torrent" --algo bm -j DROP 2>/dev/null
    iptables -A OUTPUT -m string --string "BitTorrent" --algo bm -j DROP 2>/dev/null
    echo -e "${C_GREEN}✅ Torrent blocking enabled${C_RESET}"
    safe_read "" dummy
}

# ========== LIST USERS ==========
list_users() {
    clear
    show_banner
    echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}                    📋 USER LIST${C_RESET}"
    echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo ""
    
    echo -e "${C_CYAN}--- SOCKS5 USERS ---${C_RESET}"
    if [[ -s "$SOCKS5_USERS_DB" ]]; then
        printf "  ${C_BOLD}%-20s | %-12s | %-10s${C_RESET}\n" "USERNAME" "EXPIRES" "STATUS"
        echo -e "  ${C_CYAN}----------------------------------------${C_RESET}"
        while IFS=: read -r user pass expiry limit bw used status; do
            printf "  %-20s | %-12s | %-10s\n" "$user" "$expiry" "$status"
        done < "$SOCKS5_USERS_DB"
    else
        echo -e "  ${C_YELLOW}No SOCKS5 users found${C_RESET}"
    fi
    
    echo -e "\n${C_CYAN}--- SSH USERS ---${C_RESET}"
    if [[ -s "$SSH_USERS_DB" ]]; then
        printf "  ${C_BOLD}%-20s | %-12s | %-10s | %-10s${C_RESET}\n" "USERNAME" "EXPIRES" "CONNS" "STATUS"
        echo -e "  ${C_CYAN}------------------------------------------------${C_RESET}"
        while IFS=: read -r user pass expiry limit bw used status; do
            local online=$(_get_ssh_connection_count "$user")
            printf "  %-20s | %-12s | %-10s | %-10s\n" "$user" "$expiry" "$online/$limit" "$status"
        done < "$SSH_USERS_DB"
    else
        echo -e "  ${C_YELLOW}No SSH users found${C_RESET}"
    fi
    
    safe_read "" dummy
}

# ========== UNINSTALL ALL ==========
uninstall_all() {
    clear
    show_banner
    echo -e "${C_RED}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_RED}           💥 UNINSTALL ALL${C_RESET}"
    echo -e "${C_RED}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_YELLOW}⚠️ This will remove everything!${C_RESET}"
    echo ""
    read -p "👉 Type 'YES' to confirm: " confirm
    if [[ "$confirm" != "YES" ]]; then
        echo -e "${C_GREEN}Cancelled${C_RESET}"
        return
    fi
    
    systemctl stop gost-dns.service 2>/dev/null
    for tag in "${!TUNNEL_INFO[@]}"; do
        local service=$(echo "${TUNNEL_INFO[$tag]}" | grep -oP 'service:\K[^|]+')
        systemctl stop "$service" 2>/dev/null
        systemctl disable "$service" 2>/dev/null
        rm -f "/etc/systemd/system/${service}"
    done
    systemctl stop danted 2>/dev/null
    
    rm -f "$DNSTT_SERVER" "$SLIPSTREAM_SERVER" "$VAYDNS_SERVER" "$NOIZDNS_SERVER" "$GOST_BIN"
    
    rm -rf "$DB_DIR"
    rm -f "$GOST_CONFIG"
    rm -f /etc/iptables/rules.v4
    
    chattr -i /etc/resolv.conf 2>/dev/null
    rm -f /etc/resolv.conf
    echo "nameserver 8.8.8.8" > /etc/resolv.conf
    echo "nameserver 1.1.1.1" >> /etc/resolv.conf
    
    systemctl daemon-reload
    
    echo -e "\n${C_GREEN}✅ Uninstall complete!${C_RESET}"
    exit 0
}

# ========== INITIAL SETUP ==========
initial_setup() {
    echo -e "\n${C_BLUE}🔧 Running initial system setup...${C_RESET}"
    create_directories
    install_dependencies
    download_net2share_binaries
    generate_dnstt_keys
    configure_dns_proxy
    configure_firewall
    
    systemctl start gost-dns.service
    
    echo -e "\n${C_GREEN}✅ Initial setup complete!${C_RESET}"
    echo -e "  📌 All tunnels will be accessible via PORT $DNS_PORT"
    echo -e "  📌 Use 'Add New Tunnel' to create your first tunnel"
}

# ========== MAIN MENU ==========
main_menu() {
    while true; do
        show_banner
        
        echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}                    🔧 MAIN MENU${C_RESET}"
        echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "  ┌──────────────────────┬──────────────────────┐"
        echo -e "  │  ${C_GREEN}[1]${C_RESET} 🚀 Tunnel       │  ${C_GREEN}[8]${C_RESET} 🚫 Block Torrent │"
        echo -e "  │  ${C_GREEN}[2]${C_RESET} 🔧 SOCKS5 Mgmt  │  ${C_GREEN}[9]${C_RESET} 📈 Live Monitor  │"
        echo -e "  │  ${C_GREEN}[3]${C_RESET} 🔧 SSH Mgmt     │  ${C_GREEN}[10]${C_RESET} ⚡ Speed Booster │"
        echo -e "  │  ${C_GREEN}[4]${C_RESET} 📋 List Users   │  ${C_GREEN}[11]${C_RESET} 🎨 Auto Banner   │"
        echo -e "  │  ${C_GREEN}[5]${C_RESET} 💾 Backup       │  ${C_GREEN}[12]${C_RESET} 🔄 Auto Reboot   │"
        echo -e "  │  ${C_GREEN}[6]${C_RESET} 🔄 Restore      │  ${C_GREEN}[13]${C_RESET} 🧹 Cache Cleaner │"
        echo -e "  │  ${C_GREEN}[7]${C_RESET} 📡 Tunnel Status│  ${C_GREEN}[14]${C_RESET} 📋 View Logs     │"
        echo -e "  ├──────────────────────┴──────────────────────┤"
        echo -e "  │  ${C_RED}[00]${C_RESET} ↩️ Exit                    ${C_RED}[99]${C_RESET} 🗑️ Uninstall │"
        echo -e "  └─────────────────────────────────────────────┘"
        echo ""
        
        read -p "$(echo -e ${C_PROMPT}"👉 Select option: "${C_RESET})" choice
        
        case $choice in
            1)
                while true; do
                    clear
                    show_banner
                    echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
                    echo -e "${C_BOLD}${C_PURPLE}                      🚀 TUNNEL${C_RESET}"
                    echo -e "${C_BOLD}${C_PURPLE}═══════════════════════════════════════════════════════════════${C_RESET}"
                    echo ""
                    echo -e "  ${C_GREEN}[1]${C_RESET} Add New Tunnel"
                    echo -e "  ${C_GREEN}[2]${C_RESET} List Active Tunnels"
                    echo -e "  ${C_RED}[0]${C_RESET} Return"
                    echo ""
                    read -p "$(echo -e ${C_PROMPT}"👉 Select option: "${C_RESET})" tunnel_choice
                    case $tunnel_choice in
                        1) add_tunnel_wizard ;;
                        2) list_active_tunnels ;;
                        0) break ;;
                    esac
                done
                ;;
            2) socks5_user_menu ;;
            3) ssh_user_menu ;;
            4) list_users ;;
            5) backup_config ;;
            6) restore_config ;;
            7) list_active_tunnels ;;
            8) block_torrent ;;
            9) live_monitor ;;
            10) speed_booster_menu ;;
            11) auto_banner_menu ;;
            12) auto_reboot_menu ;;
            13) cache_cleaner_menu ;;
            14) echo "View Logs - Coming soon"; safe_read "" dummy ;;
            00) echo -e "\n${C_GREEN}👋 Goodbye!${C_RESET}"; exit 0 ;;
            99) uninstall_all ;;
            *) echo -e "\n${C_RED}❌ Invalid option${C_RESET}"; sleep 2 ;;
        esac
    done
}

# ========== SCRIPT START ==========
if [[ $EUID -ne 0 ]]; then
    echo -e "${C_RED}❌ This script must be run as root!${C_RESET}"
    exit 1
fi

if [[ ! -d "$DB_DIR" ]]; then
    initial_setup
fi

main_menu
