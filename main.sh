#!/bin/bash
# ============================================================================
# VOLTRON GATE v7.2 (DNSTM STYLE)
# - Bandwidth monitoring kwa SSH na SOCKS5 users
# - Data limiter (auto-lock when quota exceeded)
# - Expiry date kwa users
# - DNS tunnel methods: DNSTT na Slipstream tu
# - GOST DNS Router (multiplexing kwenye port 53)
# - microsocks SOCKS5 proxy
# - deSEC auto domain generation
# - SSH Banner kwa kila user
# - Super Speed Booster Levels 1-7
# - Uninstall script
# - Generate Client Config
# - Command: menu au voltron
# - Kila tunnel ina DNS port na Backend port yake tofauti
# - List Tunnels kwa mtindo wa namba
# ============================================================================

set -euo pipefail

# ========== SCRIPT PATH ==========
SCRIPT_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$(basename "${BASH_SOURCE[0]}")"

# ========== COLORS ==========
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_RED='\033[38;5;196m'
C_GREEN='\033[38;5;46m'
C_YELLOW='\033[38;5;226m'
C_BLUE='\033[38;5;39m'
C_PURPLE='\033[38;5;135m'
C_CYAN='\033[38;5;51m'
C_WHITE='\033[38;5;255m'
C_GRAY='\033[38;5;245m'
C_ORANGE='\033[38;5;208m'

# ========== YOUR DESEC CREDENTIALS ==========
DESEC_TOKEN="3WxD4Hkiu5VYBLWVizVhf1rzyKbz"
DESEC_DOMAIN="voltrontechtx.shop"

# ========== DIRECTORIES ==========
DB_DIR="/etc/voltron-gate"
BACKUP_DIR="$DB_DIR/backups"
BANNER_DIR="$DB_DIR/banners"
SSH_USERS_DB="$DB_DIR/ssh_users.db"
SOCKS5_USERS_DB="$DB_DIR/socks5_users.db"
TUNNELS_DB="$DB_DIR/tunnels.db"
BANDWIDTH_DIR="$DB_DIR/bandwidth"
PID_DIR="$BANDWIDTH_DIR/pidtrack"
BIN_DIR="/usr/local/bin"
LIMITER_SCRIPT="/usr/local/bin/voltron-limiter.sh"
LIMITER_SERVICE="/etc/systemd/system/voltron-limiter.service"
GOST_SERVICE="/etc/systemd/system/gost-dns.service"
MICROSOCKS_AUTH="$DB_DIR/microsocks.auth"
SSHD_FF_CONFIG="/etc/ssh/sshd_config.d/voltron-banner.conf"
FF_USERS_GROUP="ffusers"
CONFIG_DIR="$DB_DIR/configs"

# ========== PORTS ==========
SOCKS5_PORT=1080
DNS_PORT=53
SSH_PORT=22

# ========== PORT RANGES ==========
TUNNEL_PORT_START=5300
BACKEND_PORT_START=30000

# ========== CREATE DIRECTORIES ==========
mkdir -p $DB_DIR $BACKUP_DIR $BANNER_DIR $BANDWIDTH_DIR $PID_DIR $CONFIG_DIR
touch $SSH_USERS_DB $SOCKS5_USERS_DB $TUNNELS_DB $MICROSOCKS_AUTH

# ========== HELPER FUNCTIONS ==========
get_ip() { 
    local ip=$(curl -s -4 icanhazip.com 2>/dev/null)
    [[ -z "$ip" ]] && ip=$(curl -s -4 ifconfig.me 2>/dev/null)
    echo "$ip"
}

is_valid_ipv4() { 
    [[ $1 =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && \
    [[ ${1%%.*} -le 255 ]]
}

press_enter() { 
    echo -e "\n${C_YELLOW}Press [Enter] to continue...${C_RESET}"
    read -r
}

log() { echo -e "${C_BLUE}[$(date '+%H:%M:%S')]${C_RESET} $1"; }

error() { echo -e "${C_RED}❌ $1${C_RESET}"; return 1; }

success() { echo -e "${C_GREEN}✅ $1${C_RESET}"; }

# ========== DETECT PREFERRED HOST ==========
detect_preferred_host() {
    local host_domain=""
    if [[ -f "$TUNNELS_DB" ]]; then
        host_domain=$(head -1 "$TUNNELS_DB" | cut -d: -f2 2>/dev/null)
    fi
    if [[ -z "$host_domain" ]]; then
        host_domain=$(get_ip)
    fi
    echo "$host_domain"
}

# ========== FIND UNIQUE PORT ==========
find_unique_port() {
    local start_port=$1
    local port=$start_port
    local existing_ports=()
    
    if [[ -f "$TUNNELS_DB" ]]; then
        while IFS=: read -r t d b bp tag key tp mtu; do
            if [[ -n "$bp" && "$bp" =~ ^[0-9]+$ ]]; then
                existing_ports+=("$bp")
            fi
        done < "$TUNNELS_DB"
    fi
    
    while true; do
        local in_use=false
        for used in "${existing_ports[@]}"; do
            if [[ "$used" == "$port" ]]; then
                in_use=true
                break
            fi
        done
        if [[ "$in_use" == false ]]; then
            echo "$port"
            return
        fi
        port=$((port + 1))
    done
}

# ========== 1. INSTALL BINARIES (IMPROVED) ==========
install_binaries() {
    log "📥 Installing DNS tunnel binaries..."
    
    # ---- Check and install dependencies ----
    echo -e "${C_BLUE}🔧 Checking dependencies...${C_RESET}"
    local deps=("curl" "wget" "git" "make" "gcc" "openssl" "build-essential")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${C_YELLOW}⚠️ Installing missing dependencies: ${missing[*]}${C_RESET}"
        apt update && apt install -y "${missing[@]}"
    fi
    
    # ---- Create user ----
    if ! id "voltrondns" &>/dev/null; then
        useradd -r -s /usr/sbin/nologin voltrondns
    fi
    
    # ---- Backup existing binaries ----
    echo -e "${C_BLUE}💾 Backing up existing binaries...${C_RESET}"
    for bin in microsocks gost dnstt-server slipstream-server; do
        if [[ -f "$BIN_DIR/$bin" ]]; then
            cp "$BIN_DIR/$bin" "$BIN_DIR/${bin}.bak.$(date +%Y%m%d_%H%M%S)" 2>/dev/null || true
        fi
    done
    
    # ---- 1.1 microsocks ----
    log "Installing microsocks..."
    if ! command -v microsocks &>/dev/null; then
        cd /tmp
        git clone https://github.com/rofl0r/microsocks.git 2>/dev/null || true
        cd microsocks
        make && make install
        cd /tmp && rm -rf microsocks
        success "microsocks installed"
    else
        success "microsocks already installed"
    fi
    
    # ---- 1.2 GOST DNS Router ----
    log "Installing GOST DNS Router..."
    if ! command -v gost &>/dev/null; then
        local gost_version="2.11.5"
        local arch="linux_amd64"
        [[ $(uname -m) == "aarch64" ]] && arch="linux_arm64"
        
        if wget -q "https://github.com/ginuerzh/gost/releases/download/v${gost_version}/gost-${gost_version}-${arch}.tar.gz" -O /tmp/gost.tar.gz; then
            tar -xzf /tmp/gost.tar.gz -C /tmp
            cp "/tmp/gost_${gost_version}_linux_amd64/gost" "$BIN_DIR/gost" 2>/dev/null || \
            cp "/tmp/gost" "$BIN_DIR/gost" 2>/dev/null || true
            chmod +x "$BIN_DIR/gost"
            rm -rf /tmp/gost*
            success "GOST installed: v${gost_version}"
        else
            echo -e "${C_RED}❌ Failed to download GOST${C_RESET}"
            return 1
        fi
    else
        success "GOST already installed"
    fi
    
    # ---- 1.3 DNSTT Server ----
    log "Installing DNSTT server..."
    if ! command -v dnstt-server &>/dev/null; then
        cd /tmp
        if git clone https://www.bamsoftware.com/git/dnstt.git 2>/dev/null; then
            cd dnstt
            if make; then
                cp dnstt-server "$BIN_DIR/"
                cp dnstt-client "$BIN_DIR/"
                success "DNSTT installed successfully"
            else
                echo -e "${C_RED}❌ Failed to compile DNSTT${C_RESET}"
                cd /tmp && rm -rf dnstt
                return 1
            fi
            cd /tmp && rm -rf dnstt
        else
            echo -e "${C_RED}❌ Failed to clone DNSTT repository${C_RESET}"
            return 1
        fi
    else
        success "DNSTT already installed"
    fi
    
    # ---- 1.4 Slipstream Server ----
    log "Installing Slipstream server..."
    if ! command -v slipstream-server &>/dev/null; then
        cd /tmp
        if wget -q https://github.com/anonvector/slipstream/releases/latest/download/slipstream-server -O slipstream-server; then
            chmod +x slipstream-server
            mv slipstream-server "$BIN_DIR/"
            success "Slipstream installed successfully"
        else
            echo -e "${C_RED}❌ Failed to download Slipstream binary${C_RESET}"
            return 1
        fi
    else
        success "Slipstream already installed"
    fi
    
    # ---- Set ownership ----
    chown -R voltrondns:voltrondns "$DB_DIR" 2>/dev/null || true
    
    # ---- Show summary ----
    echo -e "\n${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}              ✅ ALL BINARIES INSTALLED!                     ${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "  ${C_BOLD}microsocks:${C_RESET}      $(command -v microsocks 2>/dev/null || echo 'Not found')"
    echo -e "  ${C_BOLD}gost:${C_RESET}            $(command -v gost 2>/dev/null || echo 'Not found')"
    echo -e "  ${C_BOLD}dnstt-server:${C_RESET}    $(command -v dnstt-server 2>/dev/null || echo 'Not found')"
    echo -e "  ${C_BOLD}slipstream-server:${C_RESET} $(command -v slipstream-server 2>/dev/null || echo 'Not found')"
    echo -e "${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    
    press_enter
}

# ========== 2. GENERATE DESEC DOMAIN ==========
gen_desec_domain() {
    local transport=$1
    local backend=$2
    local rand=$(head /dev/urandom | tr -dc 'a-z0-9' | head -c 6)
    
    local prefix=""
    case $transport in
        dnstt) prefix="d" ;;
        slipstream) prefix="t" ;;
        *) prefix="x" ;;
    esac
    
    local backend_suffix=""
    case $backend in
        ssh) backend_suffix="ssh" ;;
        socks) backend_suffix="socks" ;;
        *) backend_suffix="tun" ;;
    esac
    
    local ns="${prefix}-ns-${rand}"
    local tun="${prefix}-${backend_suffix}-${rand}"
    local ip=$(get_ip)
    
    is_valid_ipv4 "$ip" || { error "Invalid IP: $ip"; return 1; }
    
    log "Creating DNS records for ${C_YELLOW}${transport}${C_RESET} tunnel..."
    echo -e "  ${C_DIM}NS Record:${C_RESET} ${ns}.${DESEC_DOMAIN}"
    echo -e "  ${C_DIM}Tunnel:${C_RESET}    ${tun}.${DESEC_DOMAIN}"
    
    local response=$(curl -s -w "%{http_code}" -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
        -H "Authorization: Token $DESEC_TOKEN" \
        -H "Content-Type: application/json" \
        --data "[{\"subname\":\"$ns\",\"type\":\"A\",\"ttl\":60,\"records\":[\"$ip\"]}]")
    
    local http_code=${response: -3}
    if [[ $http_code -ne 201 && $http_code -ne 200 ]]; then
        error "Failed to create A record (HTTP $http_code)"
        return 1
    fi
    echo -e "  ${C_GREEN}✅ A record created${C_RESET}"
    
    response=$(curl -s -w "%{http_code}" -X POST "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/" \
        -H "Authorization: Token $DESEC_TOKEN" \
        -H "Content-Type: application/json" \
        --data "[{\"subname\":\"$tun\",\"type\":\"NS\",\"ttl\":60,\"records\":[\"${ns}.${DESEC_DOMAIN}.\"]}]")
    
    http_code=${response: -3}
    if [[ $http_code -ne 201 && $http_code -ne 200 ]]; then
        error "Failed to create NS record (HTTP $http_code)"
        curl -s -X DELETE "https://desec.io/api/v1/domains/$DESEC_DOMAIN/rrsets/$ns/A/" \
            -H "Authorization: Token $DESEC_TOKEN" >/dev/null 2>&1
        return 1
    fi
    echo -e "  ${C_GREEN}✅ NS record created${C_RESET}"
    
    local full_domain="${tun}.${DESEC_DOMAIN}"
    echo -e "  ${C_GREEN}✅ Tunnel domain: ${C_YELLOW}${full_domain}${C_RESET}"
    
    echo "$full_domain"
}

# ========== 3. START MICROSOCKS ==========
start_microsocks() {
    log "Starting microsocks on port $SOCKS5_PORT..."
    
    cat > "/etc/systemd/system/microsocks-main.service" << EOF
[Unit]
Description=MicroSocks SOCKS5 Proxy (Main)
After=network.target

[Service]
Type=simple
User=voltrondns
ExecStart=/usr/local/bin/microsocks -p $SOCKS5_PORT -i 127.0.0.1 -a $MICROSOCKS_AUTH
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable microsocks-main
    systemctl restart microsocks-main
    success "microsocks started on port $SOCKS5_PORT"
}

# ========== 4. START DNS ROUTER (GOST) ==========
start_dns_router() {
    log "Starting DNS Router (GOST) on port $DNS_PORT..."
    
    if [[ ! -f "$TUNNELS_DB" || ! -s "$TUNNELS_DB" ]]; then
        log "No tunnels configured yet. Skipping GOST setup."
        return
    fi
    
    local routes=""
    local count=0
    
    while IFS=: read -r transport domain backend backend_port tag key tunnel_port mtu; do
        [[ -z "$domain" ]] && continue
        local prefix=""
        case $transport in
            dnstt) prefix="d" ;;
            slipstream) prefix="t" ;;
            *) continue ;;
        esac
        
        routes="${routes} -L udp://:53/${prefix}.*.${domain}/127.0.0.1:${tunnel_port:-53}"
        count=$((count + 1))
    done < "$TUNNELS_DB"
    
    if [[ $count -eq 0 ]]; then
        return
    fi
    
    cat > "$GOST_SERVICE" << EOF
[Unit]
Description=GOST DNS Router
After=network.target

[Service]
Type=simple
User=voltrondns
ExecStart=/usr/local/bin/gost $routes
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable gost-dns
    systemctl restart gost-dns
    success "DNS Router started with $count tunnels"
}

# ========== 5. ADD TUNNEL ==========
add_tunnel() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    🚀 ADD DNS TUNNEL                        ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    # ---- STEP 1: Select Transport ----
    echo -e "${C_CYAN}${C_BOLD}[1] Select Transport Type:${C_RESET}"
    echo "  1) DNSTT       (Recommended - Fast & Stable)"
    echo "  2) Slipstream  (TCP over DNS - Adaptive MTU)"
    echo ""
    
    local t_choice
    while true; do
        read -p "Choice [1-2]: " t_choice
        case $t_choice in
            1) TRANSPORT="dnstt"; BINARY="dnstt-server"; NEEDS_MTU=true; break ;;
            2) TRANSPORT="slipstream"; BINARY="slipstream-server"; NEEDS_MTU=false; break ;;
            *) echo -e "${C_RED}❌ Invalid choice. Please select 1 or 2.${C_RESET}" ;;
        esac
    done
    
    if ! command -v "$BINARY" &>/dev/null; then
        error "$BINARY not installed. Run option [1] first."
        return 1
    fi
    echo -e "${C_GREEN}✅ Transport: ${C_YELLOW}$TRANSPORT${C_RESET}\n"
    
    # ---- STEP 2: Select Backend ----
    echo -e "${C_CYAN}${C_BOLD}[2] Select Backend:${C_RESET}"
    echo "  1) SOCKS5  (Recommended)"
    echo "  2) SSH"
    echo ""
    
    local b_choice
    while true; do
        read -p "Choice [1-2]: " b_choice
        case $b_choice in
            1) BACKEND="socks"; break ;;
            2) BACKEND="ssh"; break ;;
            *) echo -e "${C_RED}❌ Invalid choice. Please select 1 or 2.${C_RESET}" ;;
        esac
    done
    echo -e "${C_GREEN}✅ Backend: ${C_YELLOW}$BACKEND${C_RESET}\n"
    
    # ---- STEP 3: Tunnel Tag ----
    echo -e "${C_CYAN}${C_BOLD}[3] Tunnel Tag:${C_RESET}"
    echo -e "${C_DIM}Enter a descriptive name for this tunnel (e.g., 'brave-path', 'frost-link')${C_RESET}"
    echo ""
    
    read -p "Tunnel Tag: " TAG
    if [[ -z "$TAG" ]]; then
        TAG="tunnel-$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6)"
    else
        TAG=$(echo "$TAG" | tr -cd 'a-zA-Z0-9-' | head -c 20)
        [[ -z "$TAG" ]] && TAG="tunnel-$(tr -dc 'a-z0-9' < /dev/urandom | head -c 6)"
    fi
    echo -e "${C_GREEN}✅ Tag: ${C_YELLOW}$TAG${C_RESET}\n"
    
    # ---- STEP 4: Generate Unique Ports ----
    TUNNEL_PORT=$(find_unique_port $TUNNEL_PORT_START)
    if [[ "$BACKEND" == "socks" ]]; then
        BACKEND_PORT=$(find_unique_port $BACKEND_PORT_START)
    else
        BACKEND_PORT=22
    fi
    
    echo -e "${C_GREEN}✅ DNS Port: ${C_YELLOW}$TUNNEL_PORT${C_RESET}"
    echo -e "${C_GREEN}✅ Backend Port: ${C_YELLOW}$BACKEND_PORT${C_RESET}\n"
    
    # ---- STEP 5: Domain ----
    echo -e "${C_CYAN}${C_BOLD}[4] Domain:${C_RESET}"
    echo "  a) Auto-generate with deSEC (Recommended)"
    echo "  b) Enter custom domain"
    echo ""
    
    local d_choice
    while true; do
        read -p "Choice [a/b]: " d_choice
        case $d_choice in
            a|A)
                DOMAIN=$(gen_desec_domain "$TRANSPORT" "$BACKEND")
                if [[ -z "$DOMAIN" ]]; then
                    error "Failed to generate domain"
                    return 1
                fi
                break
                ;;
            b|B)
                read -p "Enter custom domain: " custom_domain
                if [[ -z "$custom_domain" ]]; then
                    error "Domain cannot be empty"
                    continue
                fi
                if grep -q ":$custom_domain:" "$TUNNELS_DB" 2>/dev/null; then
                    error "Domain $custom_domain is already in use"
                    continue
                fi
                DOMAIN="$custom_domain"
                break
                ;;
            *) echo -e "${C_RED}❌ Invalid choice${C_RESET}" ;;
        esac
    done
    echo -e "${C_GREEN}✅ Domain: ${C_YELLOW}$DOMAIN${C_RESET}\n"
    
    # ---- STEP 6: MTU (ONLY FOR DNSTT) ----
    local MTU=""
    if [[ "$NEEDS_MTU" == true ]]; then
        echo -e "${C_CYAN}${C_BOLD}[5] Select MTU Value:${C_RESET}"
        echo -e "${C_DIM}MTU affects packet size and performance for DNSTT tunnels.${C_RESET}"
        echo -e "${C_DIM}Default MTU for DNS tunnels is 1232 bytes.${C_RESET}\n"
        
        echo "  Recommended MTU values:"
        echo "  - 512:   Most reliable, works everywhere"
        echo "  - 1024:  Balanced performance"
        echo "  - 1232:  Default (recommended)"
        echo "  - 1400:  Maximum performance (may not work on all networks)"
        echo ""
        
        echo "  1) 512   (Most reliable)"
        echo "  2) 1024  (Balanced)"
        echo "  3) 1232  (Default - Recommended)"
        echo "  4) 1400  (Maximum speed)"
        echo "  5) Custom"
        echo ""
        
        local mtu_choice
        while true; do
            read -p "Choice [1-5]: " mtu_choice
            case $mtu_choice in
                1) MTU="512"; break ;;
                2) MTU="1024"; break ;;
                3) MTU="1232"; break ;;
                4) MTU="1400"; break ;;
                5)
                    while true; do
                        read -p "Enter custom MTU (512-1500): " MTU
                        if [[ "$MTU" =~ ^[0-9]+$ ]] && [[ $MTU -ge 512 ]] && [[ $MTU -le 1500 ]]; then
                            break
                        fi
                        echo -e "${C_RED}❌ Invalid MTU. Please enter 512-1500.${C_RESET}"
                    done
                    break
                    ;;
                *) echo -e "${C_RED}❌ Invalid choice${C_RESET}" ;;
            esac
        done
        echo -e "${C_GREEN}✅ MTU: ${C_YELLOW}$MTU${C_RESET}\n"
    else
        echo -e "${C_CYAN}${C_BOLD}[5] MTU:${C_RESET}"
        echo -e "${C_GREEN}✅ Slipstream uses Adaptive MTU (auto-optimized)${C_RESET}\n"
    fi
    
    # ---- STEP 7: Generate Key (ONLY FOR DNSTT) ----
    local KEY=""
    local PUBLIC_KEY=""
    if [[ "$TRANSPORT" == "dnstt" ]]; then
        echo -e "${C_CYAN}${C_BOLD}[6] Generating Server Key...${C_RESET}"
        KEY=$(openssl rand -base64 32 | tr -d '=' | head -c 32)
        echo "$KEY" > "$DB_DIR/${TRANSPORT}_${DOMAIN}.key"
        chmod 600 "$DB_DIR/${TRANSPORT}_${DOMAIN}.key"
        PUBLIC_KEY="${KEY}"
        echo -e "${C_GREEN}✅ Server key generated${C_RESET}\n"
    fi
    
    # ---- STEP 8: Start Backend Service (SOCKS5 only) ----
    if [[ "$BACKEND" == "socks" ]]; then
        echo -e "${C_BLUE}🔌 Starting backend service on port $BACKEND_PORT...${C_RESET}"
        
        local backend_service="microsocks-${TAG}"
        local backend_service_file="/etc/systemd/system/${backend_service}.service"
        
        cat > "$backend_service_file" << EOF
[Unit]
Description=MicroSocks SOCKS5 Proxy for $TAG
After=network.target

[Service]
Type=simple
User=voltrondns
ExecStart=/usr/local/bin/microsocks -p $BACKEND_PORT -i 127.0.0.1 -a $MICROSOCKS_AUTH
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

        systemctl daemon-reload
        systemctl enable "$backend_service"
        systemctl restart "$backend_service"
        echo -e "${C_GREEN}✅ Backend service started: $backend_service (port $BACKEND_PORT)${C_RESET}\n"
    else
        echo -e "${C_YELLOW}ℹ️ SSH backend uses system SSH on port 22${C_RESET}\n"
    fi
    
    # ---- STEP 9: Create Tunnel Service ----
    local service_name="voltron-${TRANSPORT}-${TAG}"
    local service_file="/etc/systemd/system/${service_name}.service"
    
    echo -e "${C_BLUE}📝 Creating tunnel service...${C_RESET}"
    
    local backend_addr="127.0.0.1:$BACKEND_PORT"
    if [[ "$BACKEND" == "ssh" ]]; then
        backend_addr="127.0.0.1:22"
    fi
    
    case $TRANSPORT in
        dnstt)
            cat > "$service_file" << EOF
[Unit]
Description=DNSTT Tunnel ($TAG - $DOMAIN)
After=network.target

[Service]
Type=simple
User=voltrondns
ExecStart=$BINARY -udp :$TUNNEL_PORT -mtu $MTU -privkey-file $DB_DIR/${TRANSPORT}_${DOMAIN}.key $DOMAIN $backend_addr
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
            ;;
        slipstream)
            if [[ ! -f "$DB_DIR/slipstream_cert.pem" ]]; then
                openssl req -x509 -newkey rsa:2048 -nodes -days 365 \
                    -keyout "$DB_DIR/slipstream_key.pem" \
                    -out "$DB_DIR/slipstream_cert.pem" \
                    -subj "/CN=$DOMAIN" 2>/dev/null
                chmod 600 "$DB_DIR/slipstream_key.pem"
                chmod 644 "$DB_DIR/slipstream_cert.pem"
            fi
            
            cat > "$service_file" << EOF
[Unit]
Description=Slipstream Tunnel ($TAG - $DOMAIN)
After=network.target

[Service]
Type=simple
User=voltrondns
ExecStart=$BINARY -domain $DOMAIN -target $backend_addr -listen :$TUNNEL_PORT -cert $DB_DIR/slipstream_cert.pem -key $DB_DIR/slipstream_key.pem
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
            ;;
    esac
    
    # Save tunnel info
    echo "$TRANSPORT:$DOMAIN:$BACKEND:$BACKEND_PORT:$TAG:$KEY:$TUNNEL_PORT:$MTU" >> "$TUNNELS_DB"
    
    systemctl daemon-reload
    systemctl enable "$service_name"
    systemctl restart "$service_name"
    
    # ---- STEP 10: Update GOST DNS Router ----
    echo -e "\n${C_BLUE}🔄 Updating DNS Router...${C_RESET}"
    systemctl restart gost-dns 2>/dev/null || true
    
    # ---- STEP 11: Show Summary ----
    echo -e "\n${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}                    ✅ TUNNEL CREATED!                       ${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "  ${C_BOLD}Tunnel:${C_RESET}         ${C_YELLOW}$TAG${C_RESET}"
    echo -e "  ${C_BOLD}Transport:${C_RESET}     ${C_CYAN}$TRANSPORT${C_RESET}"
    echo -e "  ${C_BOLD}Backend:${C_RESET}       ${C_WHITE}$BACKEND${C_RESET}"
    echo -e "  ${C_BOLD}Domain:${C_RESET}        ${C_YELLOW}$DOMAIN${C_RESET}"
    echo -e "  ${C_BOLD}DNS Port:${C_RESET}      ${C_YELLOW}$TUNNEL_PORT${C_RESET}"
    echo -e "  ${C_BOLD}Backend Port:${C_RESET}  ${C_YELLOW}$BACKEND_PORT${C_RESET}"
    echo -e "  ${C_BOLD}Service:${C_RESET}       ${C_WHITE}$service_name${C_RESET}"
    if [[ "$NEEDS_MTU" == true ]]; then
        echo -e "  ${C_BOLD}MTU:${C_RESET}           ${C_YELLOW}$MTU${C_RESET}"
    else
        echo -e "  ${C_BOLD}MTU:${C_RESET}           ${C_GREEN}Adaptive (auto-optimized)${C_RESET}"
    fi
    if [[ -n "$KEY" ]]; then
        echo -e "  ${C_BOLD}Server Key:${C_RESET}   ${C_ORANGE}$KEY${C_RESET}"
    fi
    echo -e "  ${C_BOLD}Status:${C_RESET}        ${C_GREEN}$(systemctl is-active "$service_name")${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    
    press_enter
}

# ========== 6. LIST TUNNELS ==========
list_tunnels() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    📡 ACTIVE TUNNELS                         ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    if [[ ! -f "$TUNNELS_DB" || ! -s "$TUNNELS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No tunnels configured yet.${C_RESET}"
        press_enter
        return
    fi
    
    local count=0
    local -A tunnel_info=()
    
    echo -e "${C_BOLD}${C_WHITE}Available Tunnels:${C_RESET}\n"
    
    while IFS=: read -r transport domain backend backend_port tag key tunnel_port mtu; do
        [[ -z "$transport" ]] && continue
        count=$((count + 1))
        
        local transport_display=""
        case $transport in
            dnstt) transport_display="DNSTT" ;;
            slipstream) transport_display="Slipstream" ;;
            *) transport_display="$transport" ;;
        esac
        
        local backend_display=""
        case $backend in
            ssh) backend_display="SSH" ;;
            socks) backend_display="SOCKS5" ;;
            *) backend_display="$backend" ;;
        esac
        
        local service="voltron-${transport}-${tag}"
        local status=$(systemctl is-active "$service" 2>/dev/null || echo "inactive")
        local status_icon="🟢"
        [[ "$status" == "inactive" ]] && status_icon="🔴"
        [[ "$status" == "failed" ]] && status_icon="💀"
        
        echo -e "  ${C_GREEN}[$count]${C_RESET} ${C_YELLOW}$tag${C_RESET} ${C_DIM}(${transport_display} + ${backend_display})${C_RESET} ${status_icon}"
        
        tunnel_info["$count"]="$transport:$domain:$backend:$backend_port:$tag:$key:$tunnel_port:$mtu:$status:$service"
        
    done < "$TUNNELS_DB"
    
    echo -e "\n${C_GRAY}───────────────────────────────────────────────────────────────────────────────────${C_RESET}"
    echo -e "${C_BOLD}Total Tunnels:${C_RESET} ${C_GREEN}$count${C_RESET}"
    echo ""
    
    if [[ $count -gt 0 ]]; then
        echo -e "${C_CYAN}Select a tunnel number to view full details, or 0 to return:${C_RESET}"
        echo -e "${C_DIM}Tip: Enter 0 to go back to main menu${C_RESET}"
        echo ""
        
        local choice
        while true; do
            read -p "👉 Enter tunnel number [0-$count]: " choice
            if [[ -z "$choice" ]]; then
                echo -e "${C_RED}❌ Please enter a number.${C_RESET}"
                continue
            fi
            if [[ "$choice" == "0" ]]; then
                return
            fi
            if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le $count ]]; then
                break
            fi
            echo -e "${C_RED}❌ Invalid choice. Please enter 0-$count.${C_RESET}"
        done
        
        local selected_info="${tunnel_info[$choice]}"
        IFS=: read -r transport domain backend backend_port tag key tunnel_port mtu status service <<< "$selected_info"
        
        local transport_color="$C_CYAN"
        case $transport in
            dnstt) transport_color="$C_GREEN" ;;
            slipstream) transport_color="$C_BLUE" ;;
        esac
        
        local transport_display=""
        case $transport in
            dnstt) transport_display="DNSTT" ;;
            slipstream) transport_display="Slipstream" ;;
            *) transport_display="$transport" ;;
        esac
        
        local backend_display=""
        case $backend in
            ssh) backend_display="SSH" ;;
            socks) backend_display="SOCKS5" ;;
            *) backend_display="$backend" ;;
        esac
        
        local status_icon="🟢"
        [[ "$status" == "inactive" ]] && status_icon="🔴"
        [[ "$status" == "failed" ]] && status_icon="💀"
        
        local fingerprint="N/A"
        if [[ "$transport" == "slipstream" && -f "$DB_DIR/slipstream_cert.pem" ]]; then
            fingerprint=$(openssl x509 -in "$DB_DIR/slipstream_cert.pem" -noout -fingerprint -sha256 2>/dev/null | cut -d'=' -f2)
        fi
        
        local pub_key="N/A"
        if [[ "$transport" == "dnstt" && -n "$key" ]]; then
            pub_key="${key}"
        fi
        
        echo -e "\n${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_GREEN}${C_BOLD}              📡 TUNNEL DETAILS - $tag                         ${C_RESET}"
        echo -e "${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo ""
        echo -e "${C_PURPLE}┌──────────────────────────────────────────────────────────────────────────┐${C_RESET}"
        echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Tunnel:${C_RESET} ${C_YELLOW}$tag${C_RESET}"
        echo -e "${C_PURPLE}│${C_RESET}"
        echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Transport:${C_RESET} ${transport_color}$transport_display${C_RESET}"
        echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Backend:${C_RESET}   ${C_WHITE}$backend_display${C_RESET}"
        echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Domain:${C_RESET}    ${C_YELLOW}$domain${C_RESET}"
        echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}DNS Port:${C_RESET}  ${C_YELLOW}${tunnel_port:-53}${C_RESET}"
        
        if [[ "$backend" == "ssh" ]]; then
            echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Backend Port:${C_RESET} ${C_YELLOW}22 (System SSH)${C_RESET}"
        else
            echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Backend Port:${C_RESET} ${C_YELLOW}${backend_port}${C_RESET}"
        fi
        
        echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Service:${C_RESET}   ${C_WHITE}$service${C_RESET}"
        echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Status:${C_RESET}    ${C_GREEN}$status_icon $status${C_RESET}"
        
        if [[ "$transport" == "dnstt" && -n "$mtu" ]]; then
            echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}MTU:${C_RESET}        ${C_YELLOW}${mtu:-1232}${C_RESET}"
        elif [[ "$transport" == "slipstream" ]]; then
            echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}MTU:${C_RESET}        ${C_GREEN}Adaptive (auto-optimized)${C_RESET}"
        fi
        
        if [[ "$transport" == "dnstt" && "$pub_key" != "N/A" ]]; then
            echo -e "${C_PURPLE}│${C_RESET}"
            echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Public Key${C_RESET}"
            local pk1="${pub_key:0:48}"
            local pk2="${pub_key:48}"
            echo -e "${C_PURPLE}│${C_RESET} ${C_ORANGE}${pk1}${C_RESET}"
            [[ -n "$pk2" ]] && echo -e "${C_PURPLE}│${C_RESET} ${C_ORANGE}${pk2}${C_RESET}"
        fi
        
        if [[ "$transport" == "slipstream" && "$fingerprint" != "N/A" ]]; then
            echo -e "${C_PURPLE}│${C_RESET}"
            echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Certificate Fingerprint${C_RESET}"
            local fp1="${fingerprint:0:56}"
            local fp2="${fingerprint:56}"
            echo -e "${C_PURPLE}│${C_RESET} ${C_GRAY}${fp1}${C_RESET}"
            [[ -n "$fp2" ]] && echo -e "${C_PURPLE}│${C_RESET} ${C_GRAY}${fp2}${C_RESET}"
        fi
        
        echo -e "${C_PURPLE}│${C_RESET}"
        echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Backend Info${C_RESET}"
        echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Type:${C_RESET}    ${C_WHITE}$backend_display${C_RESET}"
        
        if [[ "$backend" == "ssh" ]]; then
            echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Address:${C_RESET} ${C_WHITE}127.0.0.1:22${C_RESET}"
        else
            echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Address:${C_RESET} ${C_WHITE}127.0.0.1:${backend_port}${C_RESET}"
        fi
        
        if [[ "$backend" == "socks" ]]; then
            if [[ -f "$MICROSOCKS_AUTH" && -s "$MICROSOCKS_AUTH" ]]; then
                echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Auth:${C_RESET}     ${C_GREEN}Enabled${C_RESET}"
            else
                echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Auth:${C_RESET}     ${C_RED}Disabled${C_RESET}"
            fi
        elif [[ "$backend" == "ssh" ]]; then
            echo -e "${C_PURPLE}│${C_RESET} ${C_BOLD}${C_WHITE}Auth:${C_RESET}     ${C_GREEN}System Password${C_RESET}"
        fi
        
        echo -e "${C_PURPLE}└──────────────────────────────────────────────────────────────────────────┘${C_RESET}"
        echo ""
        
        echo -e "${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_DIM}Press Enter to return to tunnel list...${C_RESET}"
        read -r
        
        list_tunnels
        return
    fi
    
    echo ""
    press_enter
}

# ========== 7. DELETE TUNNEL ==========
delete_tunnel() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    🗑️ DELETE TUNNEL                        ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    if [[ ! -f "$TUNNELS_DB" || ! -s "$TUNNELS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No tunnels to delete.${C_RESET}"
        press_enter
        return
    fi
    
    echo -e "${C_CYAN}Current tunnels:${C_RESET}"
    cat -n "$TUNNELS_DB" | while IFS=: read -r num transport domain backend backend_port tag key tunnel_port mtu; do
        local backend_display=""
        case $backend in
            ssh) backend_display="SSH" ;;
            socks) backend_display="SOCKS5" ;;
            *) backend_display="$backend" ;;
        esac
        echo -e "  ${C_GREEN}[$num]${C_RESET} ${transport} | ${tag:-unnamed} | $domain | (${backend_display})"
    done
    
    echo ""
    local num
    local total_tunnels=$(wc -l < "$TUNNELS_DB")
    while true; do
        read -p "Enter number to delete (or 0 to cancel) [0-$total_tunnels]: " num
        if [[ -z "$num" ]]; then
            echo -e "${C_RED}❌ Please enter a number.${C_RESET}"
            continue
        fi
        if [[ "$num" == "0" ]]; then
            echo -e "${C_YELLOW}Cancelled${C_RESET}"
            return
        fi
        if [[ "$num" =~ ^[0-9]+$ ]] && [[ $num -ge 1 ]] && [[ $num -le $total_tunnels ]]; then
            break
        fi
        echo -e "${C_RED}❌ Invalid number. Please enter 0-$total_tunnels.${C_RESET}"
    done
    
    local line=$(sed -n "${num}p" "$TUNNELS_DB")
    [[ -z "$line" ]] && { error "Invalid number"; press_enter; return; }
    
    local transport=$(echo "$line" | cut -d: -f1)
    local tag=$(echo "$line" | cut -d: -f5)
    local backend=$(echo "$line" | cut -d: -f3)
    local domain=$(echo "$line" | cut -d: -f2)
    
    echo -e "\n${C_RED}⚠️ Are you sure you want to delete tunnel: ${C_YELLOW}$tag ($transport + $backend)${C_RESET}"
    local confirm
    while true; do
        read -p "Type 'yes' to confirm: " confirm
        if [[ "$confirm" == "yes" ]]; then
            break
        else
            echo -e "${C_YELLOW}Cancelled. Type 'yes' to confirm.${C_RESET}"
            return
        fi
    done
    
    local service="voltron-${transport}-${tag}"
    systemctl stop "$service" 2>/dev/null || true
    systemctl disable "$service" 2>/dev/null || true
    rm -f "/etc/systemd/system/${service}.service"
    
    if [[ "$backend" == "socks" ]]; then
        local backend_service="microsocks-${tag}"
        systemctl stop "$backend_service" 2>/dev/null || true
        systemctl disable "$backend_service" 2>/dev/null || true
        rm -f "/etc/systemd/system/${backend_service}.service"
    fi
    
    sed -i "${num}d" "$TUNNELS_DB"
    systemctl restart gost-dns 2>/dev/null || true
    systemctl daemon-reload
    
    success "Tunnel deleted"
    press_enter
}

# ========== 8. LIMITER SERVICE ==========
setup_limiter() {
    log "Installing bandwidth monitoring + limiter service..."
    
    cat > "$LIMITER_SCRIPT" << 'EOF'
#!/bin/bash
# Voltron Gate Limiter v2.0 - Bandwidth + Expiry + Connection Limit
DB_FILE="/etc/voltron-gate/ssh_users.db"
SOCKS5_DB="/etc/voltron-gate/socks5_users.db"
BW_DIR="/etc/voltron-gate/bandwidth"
PID_DIR="$BW_DIR/pidtrack"
BANNER_DIR="/etc/voltron-gate/banners"
SCAN_INTERVAL=30

mkdir -p "$BW_DIR" "$PID_DIR" "$BANNER_DIR"
shopt -s nullglob

write_banner() {
    local user="$1"
    local content="$2"
    local banner_file="$BANNER_DIR/${user}.txt"
    local tmp_file="${banner_file}.tmp"
    
    printf "%s" "$content" > "$tmp_file"
    if ! cmp -s "$tmp_file" "$banner_file" 2>/dev/null; then
        mv "$tmp_file" "$banner_file"
    else
        rm -f "$tmp_file"
    fi
}

while true; do
    current_ts=$(date +%s)
    
    # ---- Process SSH Users ----
    if [[ -f "$DB_FILE" ]]; then
        while IFS=: read -r user pass expiry limit bandwidth_gb used_bytes status; do
            [[ -z "$user" ]] && continue
            
            expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            if [[ $expiry_ts -lt $current_ts && $expiry_ts -ne 0 ]]; then
                usermod -L "$user" &>/dev/null
                killall -u "$user" -9 &>/dev/null
                sed -i "s/^$user:.*/$user:$pass:$expiry:$limit:$bandwidth_gb:$used_bytes:EXPIRED/" "$DB_FILE"
                continue
            fi
            
            online=$(pgrep -c -u "$user" sshd 2>/dev/null || echo 0)
            if [[ $online -gt $limit ]]; then
                usermod -L "$user" &>/dev/null
                killall -u "$user" -9 &>/dev/null
                (sleep 120; usermod -U "$user" &>/dev/null) &
            fi
            
            if [[ "$bandwidth_gb" != "0" && -n "$bandwidth_gb" ]]; then
                uid=$(id -u "$user" 2>/dev/null)
                if [[ -n "$uid" ]]; then
                    total=0
                    for pid in $(pgrep -u "$user" sshd 2>/dev/null); do
                        if [[ -r "/proc/$pid/io" ]]; then
                            r=$(awk '/^rchar/{print $2}' "/proc/$pid/io" 2>/dev/null)
                            w=$(awk '/^wchar/{print $2}' "/proc/$pid/io" 2>/dev/null)
                            [[ -n "$r" ]] && total=$((total + r))
                            [[ -n "$w" ]] && total=$((total + w))
                        fi
                    done
                    
                    used_bytes_val=$(cat "$BW_DIR/${user}.usage" 2>/dev/null || echo 0)
                    new_total=$((used_bytes_val + total))
                    echo "$new_total" > "$BW_DIR/${user}.usage"
                    
                    used_gb=$(awk "BEGIN {printf \"%.2f\", $new_total / 1073741824}")
                    quota_bytes=$(awk "BEGIN {printf \"%.0f\", $bandwidth_gb * 1073741824}")
                    
                    if [[ $new_total -ge $quota_bytes ]]; then
                        usermod -L "$user" &>/dev/null
                        killall -u "$user" -9 &>/dev/null
                        sed -i "s/^$user:.*/$user:$pass:$expiry:$limit:$bandwidth_gb:$used_gb:QUOTA_EXCEEDED/" "$DB_FILE"
                    else
                        sed -i "s/^$user:.*/$user:$pass:$expiry:$limit:$bandwidth_gb:$used_gb:ACTIVE/" "$DB_FILE"
                    fi
                    
                    days_left="N/A"
                    if [[ "$expiry" != "Never" && -n "$expiry" && $expiry_ts -gt 0 ]]; then
                        diff=$((expiry_ts - current_ts))
                        if (( diff <= 0 )); then
                            days_left="EXPIRED"
                        else
                            d_l=$(( diff / 86400 ))
                            h_l=$(( (diff % 86400) / 3600 ))
                            days_left="${d_l}d ${h_l}h"
                        fi
                    fi
                    
                    percent=$(awk "BEGIN {printf \"%.0f\", ($new_total / ($bandwidth_gb * 1073741824)) * 100}")
                    [[ $percent -gt 100 ]] && percent=100
                    bar_width=20
                    filled=$(awk "BEGIN {printf \"%.0f\", ($percent / 100) * $bar_width}")
                    [[ $filled -gt $bar_width ]] && filled=$bar_width
                    empty=$((bar_width - filled))
                    progress_bar="["
                    for ((i=0; i<filled; i++)); do progress_bar+="█"; done
                    for ((i=0; i<empty; i++)); do progress_bar+="░"; done
                    progress_bar+="]"
                    
                    banner_content="<br><font color=\"cyan\"><b>========================================</b></font><br>"
                    banner_content+="<font color=\"cyan\"><b>     🔥 VOLTRON GATE ACCOUNT INFO     </b></font><br>"
                    banner_content+="<font color=\"cyan\"><b>========================================</b></font><br><br>"
                    banner_content+="<font color=\"white\">👤 <b>Username    :</b> $user</font><br>"
                    banner_content+="<font color=\"white\">📅 <b>Expires     :</b> $expiry ($days_left)</font><br>"
                    banner_content+="<font color=\"white\">📊 <b>Bandwidth   :</b> ${used_gb} / ${bandwidth_gb} GB</font><br>"
                    banner_content+="<font color=\"white\">📈 <b>Progress    :</b> $progress_bar $percent%</font><br>"
                    banner_content+="<font color=\"white\">🔌 <b>Sessions   :</b> $online / $limit</font><br>"
                    
                    if [[ "$status" == "QUOTA_EXCEEDED" ]]; then
                        banner_content+="<font color=\"red\">📦 QUOTA EXCEEDED - ACCOUNT LOCKED</font><br>"
                    elif [[ "$status" == "EXPIRED" ]]; then
                        banner_content+="<font color=\"red\">⚠️ ACCOUNT EXPIRED</font><br>"
                    else
                        banner_content+="<font color=\"green\">✅ ACCOUNT ACTIVE</font><br>"
                    fi
                    banner_content+="<font color=\"cyan\"><b>========================================</b></font><br>"
                    
                    write_banner "$user" "$banner_content"
                fi
            fi
        done < "$DB_FILE"
    fi
    
    # ---- Process SOCKS5 Users ----
    if [[ -f "$SOCKS5_DB" ]]; then
        while IFS=: read -r user pass expiry limit bandwidth_gb used_bytes status; do
            [[ -z "$user" ]] && continue
            
            expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
            if [[ $expiry_ts -lt $current_ts && $expiry_ts -ne 0 ]]; then
                sed -i "/^$user:/d" "$SOCKS5_DB"
                sed -i "/^$user:/d" "/etc/voltron-gate/microsocks.auth"
                systemctl restart microsocks-main
                continue
            fi
            
            if [[ "$bandwidth_gb" != "0" && -n "$bandwidth_gb" ]]; then
                used_bytes_val=$(cat "$BW_DIR/${user}.socks5.usage" 2>/dev/null || echo 0)
                used_gb=$(awk "BEGIN {printf \"%.2f\", $used_bytes_val / 1073741824}")
                quota_bytes=$(awk "BEGIN {printf \"%.0f\", $bandwidth_gb * 1073741824}")
                
                if [[ $used_bytes_val -ge $quota_bytes ]]; then
                    sed -i "/^$user:/d" "$SOCKS5_DB"
                    sed -i "/^$user:/d" "/etc/voltron-gate/microsocks.auth"
                    systemctl restart microsocks-main
                    sed -i "s/^$user:.*/$user:$pass:$expiry:$limit:$bandwidth_gb:$used_gb:QUOTA_EXCEEDED/" "$SOCKS5_DB"
                else
                    sed -i "s/^$user:.*/$user:$pass:$expiry:$limit:$bandwidth_gb:$used_gb:ACTIVE/" "$SOCKS5_DB"
                fi
            fi
        done < "$SOCKS5_DB"
    fi
    
    sleep "$SCAN_INTERVAL"
done
EOF
    
    chmod +x "$LIMITER_SCRIPT"
    
    cat > "$LIMITER_SERVICE" << EOF
[Unit]
Description=Voltron Gate Limiter (Bandwidth + Expiry + Connections)
After=network.target

[Service]
Type=simple
ExecStart=$LIMITER_SCRIPT
Restart=always
RestartSec=10
Nice=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable voltron-limiter
    systemctl restart voltron-limiter
    
    success "Limiter service installed (bandwidth + expiry + connection limit)"
    press_enter
}

# ========== 9. ADD SSH USER ==========
add_ssh_user() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    👤 ADD SSH USER                          ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    local u
    while true; do
        read -p "Username: " u
        if [[ -z "$u" ]]; then
            echo -e "${C_RED}❌ Username cannot be empty${C_RESET}"
            continue
        fi
        if [[ ! "$u" =~ ^[a-zA-Z0-9_-]{3,32}$ ]]; then
            echo -e "${C_RED}❌ Invalid username. Use 3-32 characters (letters, numbers, underscore, dash).${C_RESET}"
            continue
        fi
        if id "$u" &>/dev/null; then
            echo -e "${C_RED}❌ User $u already exists on system${C_RESET}"
            continue
        fi
        if grep -q "^$u:" "$SSH_USERS_DB" 2>/dev/null; then
            echo -e "${C_RED}❌ User $u already exists in database${C_RESET}"
            continue
        fi
        break
    done
    
    local p
    echo "Password (leave empty for auto-generated): "
    while true; do
        read -p "" p
        if [[ -z "$p" ]]; then
            p=$(tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 12)
            echo -e "${C_GREEN}🔑 Auto-generated password: ${C_YELLOW}$p${C_RESET}"
            break
        fi
        if [[ ${#p} -lt 6 ]]; then
            echo -e "${C_RED}❌ Password must be at least 6 characters.${C_RESET}"
            continue
        fi
        break
    done
    
    local days
    while true; do
        read -p "Account expiry (days) [30]: " days
        days=${days:-30}
        if [[ "$days" =~ ^[0-9]+$ ]] && [[ $days -gt 0 ]]; then
            break
        fi
        echo -e "${C_RED}❌ Invalid days. Please enter a positive number.${C_RESET}"
    done
    local expire=$(date -d "+$days days" +%Y-%m-%d)
    
    local limit
    while true; do
        read -p "Connection limit [1]: " limit
        limit=${limit:-1}
        if [[ "$limit" =~ ^[0-9]+$ ]] && [[ $limit -gt 0 ]]; then
            break
        fi
        echo -e "${C_RED}❌ Invalid limit. Please enter a positive number.${C_RESET}"
    done
    
    local bw
    while true; do
        read -p "Bandwidth limit (GB) [0 = unlimited]: " bw
        bw=${bw:-0}
        if [[ "$bw" =~ ^[0-9]+$ ]]; then
            break
        fi
        echo -e "${C_RED}❌ Invalid bandwidth. Please enter a number.${C_RESET}"
    done
    
    if useradd -m -s /usr/sbin/nologin "$u" 2>/dev/null; then
        echo "$u:$p" | chpasswd
        chage -E "$expire" "$u"
        echo "$u:$p:$expire:$limit:$bw:0:ACTIVE" >> "$SSH_USERS_DB"
        echo "0" > "$BANDWIDTH_DIR/${u}.usage"
        
        echo -e "\n${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "${C_GREEN}${C_BOLD}                    ✅ SSH USER CREATED!                     ${C_RESET}"
        echo -e "${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
        echo -e "  ${C_BOLD}Username:${C_RESET}       ${C_YELLOW}$u${C_RESET}"
        echo -e "  ${C_BOLD}Password:${C_RESET}       ${C_YELLOW}$p${C_RESET}"
        echo -e "  ${C_BOLD}Expires:${C_RESET}        ${C_YELLOW}$expire${C_RESET} (${days} days)"
        echo -e "  ${C_BOLD}Connections:${C_RESET}    ${C_YELLOW}$limit${C_RESET}"
        echo -e "  ${C_BOLD}Bandwidth:${C_RESET}      ${C_YELLOW}${bw}GB${C_RESET}"
        echo -e "  ${C_BOLD}Status:${C_RESET}         ${C_GREEN}ACTIVE${C_RESET}"
        echo -e "${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
        
        echo
        read -p "👉 Generate client config for this user? (y/n): " gen_conf
        if [[ "$gen_conf" == "y" || "$gen_conf" == "Y" ]]; then
            generate_ssh_client_config "$u" "$p"
        fi
    else
        error "Failed to create system user."
        return 1
    fi
    
    press_enter
}

# ========== 10. ADD SOCKS5 USER ==========
add_socks5_user() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    🔌 ADD SOCKS5 USER                       ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    local u
    while true; do
        read -p "Username: " u
        if [[ -z "$u" ]]; then
            echo -e "${C_RED}❌ Username cannot be empty${C_RESET}"
            continue
        fi
        if [[ ! "$u" =~ ^[a-zA-Z0-9_-]{3,32}$ ]]; then
            echo -e "${C_RED}❌ Invalid username. Use 3-32 characters (letters, numbers, underscore, dash).${C_RESET}"
            continue
        fi
        if grep -q "^$u:" "$SOCKS5_USERS_DB" 2>/dev/null; then
            echo -e "${C_RED}❌ User $u already exists in database${C_RESET}"
            continue
        fi
        if grep -q "^$u:" "$MICROSOCKS_AUTH" 2>/dev/null; then
            echo -e "${C_RED}❌ User $u already exists in microsocks auth${C_RESET}"
            continue
        fi
        break
    done
    
    local p
    echo "Password (leave empty for auto-generated): "
    while true; do
        read -p "" p
        if [[ -z "$p" ]]; then
            p=$(tr -dc 'A-Za-z0-9!@#$%^&*' < /dev/urandom | head -c 12)
            echo -e "${C_GREEN}🔑 Auto-generated password: ${C_YELLOW}$p${C_RESET}"
            break
        fi
        if [[ ${#p} -lt 6 ]]; then
            echo -e "${C_RED}❌ Password must be at least 6 characters.${C_RESET}"
            continue
        fi
        break
    done
    
    local days
    while true; do
        read -p "Account expiry (days) [30]: " days
        days=${days:-30}
        if [[ "$days" =~ ^[0-9]+$ ]] && [[ $days -gt 0 ]]; then
            break
        fi
        echo -e "${C_RED}❌ Invalid days. Please enter a positive number.${C_RESET}"
    done
    local expire=$(date -d "+$days days" +%Y-%m-%d)
    
    local limit
    while true; do
        read -p "Connection limit [1]: " limit
        limit=${limit:-1}
        if [[ "$limit" =~ ^[0-9]+$ ]] && [[ $limit -gt 0 ]]; then
            break
        fi
        echo -e "${C_RED}❌ Invalid limit. Please enter a positive number.${C_RESET}"
    done
    
    local bw
    while true; do
        read -p "Bandwidth limit (GB) [0 = unlimited]: " bw
        bw=${bw:-0}
        if [[ "$bw" =~ ^[0-9]+$ ]]; then
            break
        fi
        echo -e "${C_RED}❌ Invalid bandwidth. Please enter a number.${C_RESET}"
    done
    
    echo "$u:$p:$expire:$limit:$bw:0:ACTIVE" >> "$SOCKS5_USERS_DB"
    echo "$u:$p" >> "$MICROSOCKS_AUTH"
    echo "0" > "$BANDWIDTH_DIR/${u}.socks5.usage"
    
    systemctl restart microsocks-main
    
    echo -e "\n${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}                  ✅ SOCKS5 USER CREATED!                    ${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "  ${C_BOLD}Username:${C_RESET}       ${C_YELLOW}$u${C_RESET}"
    echo -e "  ${C_BOLD}Password:${C_RESET}       ${C_YELLOW}$p${C_RESET}"
    echo -e "  ${C_BOLD}Expires:${C_RESET}        ${C_YELLOW}$expire${C_RESET} (${days} days)"
    echo -e "  ${C_BOLD}Connections:${C_RESET}    ${C_YELLOW}$limit${C_RESET}"
    echo -e "  ${C_BOLD}Bandwidth:${C_RESET}      ${C_YELLOW}${bw}GB${C_RESET}"
    echo -e "  ${C_BOLD}SOCKS5 Port:${C_RESET}    ${C_YELLOW}$SOCKS5_PORT${C_RESET}"
    echo -e "  ${C_BOLD}Status:${C_RESET}         ${C_GREEN}ACTIVE${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    
    echo
    read -p "👉 Generate client config for this user? (y/n): " gen_conf
    if [[ "$gen_conf" == "y" || "$gen_conf" == "Y" ]]; then
        generate_socks5_client_config "$u" "$p"
    fi
    
    press_enter
}

# ========== 11. GENERATE SSH CLIENT CONFIG ==========
generate_ssh_client_config() {
    local user=$1
    local pass=$2
    
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    📱 SSH CLIENT CONFIG                     ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    local ip=$(get_ip)
    local host_domain=$(detect_preferred_host)
    [[ -z "$host_domain" ]] && host_domain="$ip"
    
    echo -e "${C_YELLOW}${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_BOLD}👤 USER CREDENTIALS${C_RESET}"
    echo -e "  ${C_BOLD}Username:${C_RESET} ${C_YELLOW}$user${C_RESET}"
    echo -e "  ${C_BOLD}Password:${C_RESET} ${C_YELLOW}$pass${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    
    echo -e "\n${C_BOLD}🔹 DIRECT SSH CONNECTION:${C_RESET}"
    echo -e "  ssh $user@$host_domain -p 22"
    echo -e "  Password: $pass"
    
    echo -e "\n${C_BOLD}🔹 DNS TUNNEL CONNECTIONS:${C_RESET}"
    if [[ -f "$TUNNELS_DB" ]]; then
        while IFS=: read -r transport domain backend backend_port tag key tunnel_port mtu; do
            if [[ "$backend" == "ssh" ]]; then
                local transport_display=""
                case $transport in
                    dnstt) transport_display="DNSTT" ;;
                    slipstream) transport_display="Slipstream" ;;
                    *) transport_display="$transport" ;;
                esac
                echo -e "  ${C_GREEN}● ${transport_display}${C_RESET} → $domain"
                echo -e "    ssh $user@$domain -p 22 (after DNS tunnel setup)"
                echo -e "    DNS Port: $tunnel_port"
            fi
        done < "$TUNNELS_DB"
    fi
    
    echo -e "\n${C_BOLD}🔹 SSH CONFIG FILE (~/.ssh/config):${C_RESET}"
    echo "  Host voltron-ssh"
    echo "      HostName $host_domain"
    echo "      User $user"
    echo "      Port 22"
    
    local config_file="$CONFIG_DIR/${user}_ssh_config.txt"
    cat > "$config_file" << EOF
═══════════════════════════════════════════════════════════════
                    SSH CLIENT CONFIG - $user
═══════════════════════════════════════════════════════════════

USER CREDENTIALS:
  Username: $user
  Password: $pass

DIRECT SSH CONNECTION:
  ssh $user@$host_domain -p 22
  Password: $pass

DNS TUNNEL CONNECTIONS:
EOF
    while IFS=: read -r transport domain backend backend_port tag key tunnel_port mtu; do
        if [[ "$backend" == "ssh" ]]; then
            local transport_display=""
            case $transport in
                dnstt) transport_display="DNSTT" ;;
                slipstream) transport_display="Slipstream" ;;
                *) transport_display="$transport" ;;
            esac
            echo "  ${transport_display} → $domain" >> "$config_file"
            echo "    ssh $user@$domain -p 22 (after DNS tunnel setup)" >> "$config_file"
            echo "    DNS Port: $tunnel_port" >> "$config_file"
        fi
    done < "$TUNNELS_DB"
    
    echo "SSH CONFIG FILE (~/.ssh/config):" >> "$config_file"
    echo "  Host voltron-ssh" >> "$config_file"
    echo "      HostName $host_domain" >> "$config_file"
    echo "      User $user" >> "$config_file"
    echo "      Port 22" >> "$config_file"
    
    echo -e "\n${C_GREEN}✅ Config saved to: ${C_YELLOW}$config_file${C_RESET}"
    
    echo -e "\n${C_YELLOW}${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    press_enter
}

# ========== 12. GENERATE SOCKS5 CLIENT CONFIG ==========
generate_socks5_client_config() {
    local user=$1
    local pass=$2
    
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    🔌 SOCKS5 CLIENT CONFIG                  ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    local ip=$(get_ip)
    local host_domain=$(detect_preferred_host)
    [[ -z "$host_domain" ]] && host_domain="$ip"
    
    echo -e "${C_YELLOW}${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    echo -e "${C_BOLD}👤 USER CREDENTIALS${C_RESET}"
    echo -e "  ${C_BOLD}Username:${C_RESET} ${C_YELLOW}$user${C_RESET}"
    echo -e "  ${C_BOLD}Password:${C_RESET} ${C_YELLOW}$pass${C_RESET}"
    echo -e "  ${C_BOLD}SOCKS5 Port:${C_RESET} ${C_YELLOW}$SOCKS5_PORT${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    
    echo -e "\n${C_BOLD}🔹 DIRECT SOCKS5 CONNECTION:${C_RESET}"
    echo -e "  Proxy: $host_domain:$SOCKS5_PORT"
    echo -e "  Username: $user"
    echo -e "  Password: $pass"
    
    echo -e "\n${C_BOLD}🔹 DNS TUNNEL SOCKS5 CONNECTIONS:${C_RESET}"
    if [[ -f "$TUNNELS_DB" ]]; then
        while IFS=: read -r transport domain backend backend_port tag key tunnel_port mtu; do
            if [[ "$backend" == "socks" ]]; then
                local transport_display=""
                case $transport in
                    dnstt) transport_display="DNSTT" ;;
                    slipstream) transport_display="Slipstream" ;;
                    *) transport_display="$transport" ;;
                esac
                echo -e "  ${C_GREEN}● ${transport_display}${C_RESET} → $domain"
                echo -e "    SOCKS5 Proxy: $domain:$backend_port (after DNS tunnel setup)"
                echo -e "    DNS Port: $tunnel_port"
            fi
        done < "$TUNNELS_DB"
    fi
    
    echo -e "\n${C_BOLD}🔹 BROWSER CONFIGURATION:${C_RESET}"
    echo "  Firefox: Settings → Network Settings → Manual Proxy"
    echo "    SOCKS5 Host: $host_domain"
    echo "    SOCKS5 Port: $SOCKS5_PORT"
    echo "    Check: Proxy DNS when using SOCKS v5"
    echo "    Username: $user"
    echo "    Password: $pass"
    
    echo -e "\n${C_BOLD}🔹 COMMAND LINE (curl):${C_RESET}"
    echo "  curl --socks5 $user:$pass@$host_domain:$SOCKS5_PORT https://api.ipify.org"
    
    local config_file="$CONFIG_DIR/${user}_socks5_config.txt"
    cat > "$config_file" << EOF
═══════════════════════════════════════════════════════════════
                    SOCKS5 CLIENT CONFIG - $user
═══════════════════════════════════════════════════════════════

USER CREDENTIALS:
  Username: $user
  Password: $pass
  SOCKS5 Port: $SOCKS5_PORT

DIRECT SOCKS5 CONNECTION:
  Proxy: $host_domain:$SOCKS5_PORT
  Username: $user
  Password: $pass

DNS TUNNEL SOCKS5 CONNECTIONS:
EOF
    while IFS=: read -r transport domain backend backend_port tag key tunnel_port mtu; do
        if [[ "$backend" == "socks" ]]; then
            local transport_display=""
            case $transport in
                dnstt) transport_display="DNSTT" ;;
                slipstream) transport_display="Slipstream" ;;
                *) transport_display="$transport" ;;
            esac
            echo "  ${transport_display} → $domain" >> "$config_file"
            echo "    SOCKS5 Proxy: $domain:$backend_port (after DNS tunnel setup)" >> "$config_file"
            echo "    DNS Port: $tunnel_port" >> "$config_file"
        fi
    done < "$TUNNELS_DB"
    
    echo "" >> "$config_file"
    echo "BROWSER CONFIGURATION:" >> "$config_file"
    echo "  Firefox: Settings → Network Settings → Manual Proxy" >> "$config_file"
    echo "    SOCKS5 Host: $host_domain" >> "$config_file"
    echo "    SOCKS5 Port: $SOCKS5_PORT" >> "$config_file"
    echo "    Username: $user" >> "$config_file"
    echo "    Password: $pass" >> "$config_file"
    
    echo "" >> "$config_file"
    echo "COMMAND LINE (curl):" >> "$config_file"
    echo "  curl --socks5 $user:$pass@$host_domain:$SOCKS5_PORT https://api.ipify.org" >> "$config_file"
    
    echo -e "\n${C_GREEN}✅ Config saved to: ${C_YELLOW}$config_file${C_RESET}"
    
    echo -e "\n${C_YELLOW}${C_BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${C_RESET}"
    press_enter
}

# ========== 13. SSH USER MANAGER ==========
ssh_user_menu() {
    while true; do
        clear
        echo -e "${C_PURPLE}╔═══════════════════════════════════════════════════════════════╗${C_RESET}"
        echo -e "${C_PURPLE}║${C_BOLD}              👤 SSH USER MANAGER                     ${C_RESET}${C_PURPLE}║${C_RESET}"
        echo -e "${C_PURPLE}╚═══════════════════════════════════════════════════════════════╝${C_RESET}"
        
        local total_users=$(wc -l < "$SSH_USERS_DB" 2>/dev/null || echo 0)
        echo -e "${C_DIM}📊 Total SSH Users: ${C_YELLOW}$total_users${C_RESET}"
        echo ""
        
        echo -e "  ${C_GREEN}[1]${C_RESET} Add SSH User"
        echo -e "  ${C_GREEN}[2]${C_RESET} List SSH Users"
        echo -e "  ${C_GREEN}[3]${C_RESET} View SSH User Bandwidth"
        echo -e "  ${C_GREEN}[4]${C_RESET} Renew SSH User"
        echo -e "  ${C_GREEN}[5]${C_RESET} Delete SSH User"
        echo -e "  ${C_GREEN}[6]${C_RESET} Lock SSH User"
        echo -e "  ${C_GREEN}[7]${C_RESET} Unlock SSH User"
        echo -e "  ${C_GREEN}[8]${C_RESET} Generate SSH Client Config"
        echo ""
        echo -e "  ${C_RED}[0]${C_RESET} Return to Main Menu"
        echo ""
        
        local opt
        while true; do
            read -p "👉 Select option: " opt
            case $opt in
                1|2|3|4|5|6|7|8|0) break ;;
                *) echo -e "${C_RED}❌ Invalid option. Please enter 0-8.${C_RESET}" ;;
            esac
        done
        
        case $opt in
            1) add_ssh_user ;;
            2) list_ssh_users ;;
            3) view_ssh_bandwidth ;;
            4) renew_ssh_user ;;
            5) delete_ssh_user ;;
            6) lock_ssh_user ;;
            7) unlock_ssh_user ;;
            8) generate_ssh_client_config_menu ;;
            0) return ;;
        esac
    done
}

# ========== 14. SOCKS5 USER MANAGER ==========
socks5_user_menu() {
    while true; do
        clear
        echo -e "${C_PURPLE}╔═══════════════════════════════════════════════════════════════╗${C_RESET}"
        echo -e "${C_PURPLE}║${C_BOLD}              🔌 SOCKS5 USER MANAGER                  ${C_RESET}${C_PURPLE}║${C_RESET}"
        echo -e "${C_PURPLE}╚═══════════════════════════════════════════════════════════════╝${C_RESET}"
        
        local total_users=$(wc -l < "$SOCKS5_USERS_DB" 2>/dev/null || echo 0)
        local microsocks_status=$(systemctl is-active microsocks-main 2>/dev/null || echo "inactive")
        local status_color="$C_GREEN"
        [[ "$microsocks_status" == "inactive" ]] && status_color="$C_RED"
        
        echo -e "${C_DIM}📊 Total SOCKS5 Users: ${C_YELLOW}$total_users${C_RESET}"
        echo -e "${C_DIM}🔌 Microsocks: ${status_color}$microsocks_status${C_RESET} (port $SOCKS5_PORT)"
        echo ""
        
        echo -e "  ${C_GREEN}[1]${C_RESET} Add SOCKS5 User"
        echo -e "  ${C_GREEN}[2]${C_RESET} List SOCKS5 Users"
        echo -e "  ${C_GREEN}[3]${C_RESET} View SOCKS5 User Bandwidth"
        echo -e "  ${C_GREEN}[4]${C_RESET} Renew SOCKS5 User"
        echo -e "  ${C_GREEN}[5]${C_RESET} Delete SOCKS5 User"
        echo -e "  ${C_GREEN}[6]${C_RESET} Restart Microsocks"
        echo -e "  ${C_GREEN}[7]${C_RESET} Generate SOCKS5 Client Config"
        echo ""
        echo -e "  ${C_RED}[0]${C_RESET} Return to Main Menu"
        echo ""
        
        local opt
        while true; do
            read -p "👉 Select option: " opt
            case $opt in
                1|2|3|4|5|6|7|0) break ;;
                *) echo -e "${C_RED}❌ Invalid option. Please enter 0-7.${C_RESET}" ;;
            esac
        done
        
        case $opt in
            1) add_socks5_user ;;
            2) list_socks5_users ;;
            3) view_socks5_bandwidth ;;
            4) renew_socks5_user ;;
            5) delete_socks5_user ;;
            6) systemctl restart microsocks-main; echo -e "${C_GREEN}✅ Microsocks restarted${C_RESET}"; press_enter ;;
            7) generate_socks5_client_config_menu ;;
            0) return ;;
        esac
    done
}

# ========== 15. GENERATE CLIENT CONFIG MENUS ==========
generate_ssh_client_config_menu() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    📱 GENERATE SSH CLIENT CONFIG            ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    if [[ ! -f "$SSH_USERS_DB" || ! -s "$SSH_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No SSH users found.${C_RESET}"
        press_enter
        return
    fi
    
    echo -e "${C_CYAN}Available SSH users:${C_RESET}"
    cut -d: -f1 "$SSH_USERS_DB" | cat -n
    echo ""
    
    local username
    while true; do
        read -p "Enter username: " username
        if grep -q "^$username:" "$SSH_USERS_DB" 2>/dev/null; then
            break
        fi
        echo -e "${C_RED}❌ User not found.${C_RESET}"
    done
    
    local pass=$(grep "^$username:" "$SSH_USERS_DB" | cut -d: -f2)
    generate_ssh_client_config "$username" "$pass"
}

generate_socks5_client_config_menu() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    📱 GENERATE SOCKS5 CLIENT CONFIG          ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    if [[ ! -f "$SOCKS5_USERS_DB" || ! -s "$SOCKS5_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No SOCKS5 users found.${C_RESET}"
        press_enter
        return
    fi
    
    echo -e "${C_CYAN}Available SOCKS5 users:${C_RESET}"
    cut -d: -f1 "$SOCKS5_USERS_DB" | cat -n
    echo ""
    
    local username
    while true; do
        read -p "Enter username: " username
        if grep -q "^$username:" "$SOCKS5_USERS_DB" 2>/dev/null; then
            break
        fi
        echo -e "${C_RED}❌ User not found.${C_RESET}"
    done
    
    local pass=$(grep "^$username:" "$SOCKS5_USERS_DB" | cut -d: -f2)
    generate_socks5_client_config "$username" "$pass"
}

# ========== 16. SSH USER FUNCTIONS ==========
list_ssh_users() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    👥 SSH USERS                             ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    if [[ ! -f "$SSH_USERS_DB" || ! -s "$SSH_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No SSH users found.${C_RESET}"
        press_enter
        return
    fi
    
    printf "${C_BOLD}${C_WHITE}%-15s | %-12s | %-8s | %-12s | %-15s | %-10s${C_RESET}\n" \
        "USERNAME" "EXPIRES" "CONNS" "BANDWIDTH" "USED" "STATUS"
    echo -e "${C_GRAY}───────────────────────────────────────────────────────────────────────────────${C_RESET}"
    
    while IFS=: read -r user pass expiry limit bandwidth_gb used_gb status; do
        [[ -z "$user" ]] && continue
        
        local online=$(pgrep -c -u "$user" sshd 2>/dev/null || echo 0)
        local conn_string="${online}/${limit}"
        
        local used_bytes=$(cat "$BANDWIDTH_DIR/${user}.usage" 2>/dev/null || echo 0)
        local used_gb_display=$(awk "BEGIN {printf \"%.2f\", $used_bytes / 1073741824}")
        
        local status_color="$C_GREEN"
        [[ "$status" == "LOCKED" ]] && status_color="$C_YELLOW"
        [[ "$status" == "EXPIRED" ]] && status_color="$C_RED"
        [[ "$status" == "QUOTA_EXCEEDED" ]] && status_color="$C_RED"
        
        local bw_display="Unlimited"
        [[ "$bandwidth_gb" != "0" ]] && bw_display="${bandwidth_gb}GB"
        
        printf "%-15s | ${C_YELLOW}%-12s${C_RESET} | ${C_CYAN}%-8s${C_RESET} | ${C_ORANGE}%-12s${C_RESET} | ${C_WHITE}%-15s${C_RESET} | ${status_color}%-10s${C_RESET}\n" \
            "$user" "$expiry" "$conn_string" "$bw_display" "${used_gb_display}GB" "$status"
    done < "$SSH_USERS_DB"
    
    echo -e "${C_GRAY}───────────────────────────────────────────────────────────────────────────────${C_RESET}"
    echo -e "${C_BOLD}Total SSH Users:${C_RESET} ${C_GREEN}$(wc -l < "$SSH_USERS_DB")${C_RESET}"
    press_enter
}

view_ssh_bandwidth() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    📊 SSH USER BANDWIDTH                    ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    if [[ ! -f "$SSH_USERS_DB" || ! -s "$SSH_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No SSH users found.${C_RESET}"
        press_enter
        return
    fi
    
    echo -e "${C_CYAN}Available SSH users:${C_RESET}"
    cut -d: -f1 "$SSH_USERS_DB" | cat -n
    echo ""
    
    local username
    while true; do
        read -p "Enter username: " username
        if grep -q "^$username:" "$SSH_USERS_DB" 2>/dev/null; then
            break
        fi
        echo -e "${C_RED}❌ User not found.${C_RESET}"
    done
    
    local line=$(grep "^$username:" "$SSH_USERS_DB")
    IFS=: read -r user pass expiry limit bw used status <<< "$line"
    
    local used_bytes=$(cat "$BANDWIDTH_DIR/${user}.usage" 2>/dev/null || echo 0)
    local used_gb=$(awk "BEGIN {printf \"%.2f\", $used_bytes / 1073741824}")
    local expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
    local current_ts=$(date +%s)
    local days_left=$(((expiry_ts - current_ts) / 86400))
    [[ $days_left -lt 0 ]] && days_left=0
    
    echo -e "\n${C_YELLOW}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}                    👤 USER: ${C_WHITE}$user${C_YELLOW}                         ${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "  ${C_BOLD}Expires:${C_RESET}          ${C_YELLOW}$expiry${C_RESET} (${days_left} days left)"
    echo -e "  ${C_BOLD}Status:${C_RESET}           ${C_GREEN}$status${C_RESET}"
    echo -e "  ${C_BOLD}Connections:${C_RESET}      ${C_CYAN}$limit${C_RESET}"
    echo -e "  ${C_BOLD}Bandwidth Limit:${C_RESET}  ${C_ORANGE}${bw}GB${C_RESET}"
    echo -e "  ${C_BOLD}Used:${C_RESET}             ${C_WHITE}${used_gb}GB${C_RESET}"
    
    if [[ "$bw" != "0" ]]; then
        local percent=$(awk "BEGIN {printf \"%.1f\", ($used_bytes / ($bw * 1073741824)) * 100}")
        local bar_width=40
        local filled=$(awk "BEGIN {printf \"%.0f\", ($percent / 100) * $bar_width}")
        [[ $filled -gt $bar_width ]] && filled=$bar_width
        local empty=$((bar_width - filled))
        
        local bar_color="$C_GREEN"
        if (( $(awk "BEGIN {print ($percent > 80)}" ) )); then bar_color="$C_RED"
        elif (( $(awk "BEGIN {print ($percent > 50)}" ) )); then bar_color="$C_YELLOW"
        fi
        
        printf "  ${C_BOLD}Usage:${C_RESET}            ${bar_color}["
        for ((i=0; i<filled; i++)); do printf "█"; done
        for ((i=0; i<empty; i++)); do printf "░"; done
        printf "]${C_RESET} ${percent}%%\n"
    fi
    
    echo -e "${C_YELLOW}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    press_enter
}

renew_ssh_user() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    🔄 RENEW SSH USER                       ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    if [[ ! -f "$SSH_USERS_DB" || ! -s "$SSH_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No SSH users found.${C_RESET}"
        press_enter
        return
    fi
    
    echo -e "${C_CYAN}Available SSH users:${C_RESET}"
    cut -d: -f1 "$SSH_USERS_DB" | cat -n
    echo ""
    
    local username
    while true; do
        read -p "Enter username to renew: " username
        if grep -q "^$username:" "$SSH_USERS_DB" 2>/dev/null; then
            break
        fi
        echo -e "${C_RED}❌ User not found.${C_RESET}"
    done
    
    local days
    while true; do
        read -p "Enter number of days to extend: " days
        if [[ "$days" =~ ^[0-9]+$ ]] && [[ $days -gt 0 ]]; then
            break
        fi
        echo -e "${C_RED}❌ Invalid days.${C_RESET}"
    done
    
    local line=$(grep "^$username:" "$SSH_USERS_DB")
    IFS=: read -r user pass expiry limit bw used status <<< "$line"
    
    local new_expiry=$(date -d "+$days days" +%Y-%m-%d)
    
    chage -E "$new_expiry" "$user"
    sed -i "s/^$username:.*/$username:$pass:$new_expiry:$limit:$bw:$used:ACTIVE/" "$SSH_USERS_DB"
    usermod -U "$user" &>/dev/null
    
    success "SSH user $username renewed until $new_expiry"
    press_enter
}

delete_ssh_user() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    🗑️ DELETE SSH USER                      ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    if [[ ! -f "$SSH_USERS_DB" || ! -s "$SSH_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No SSH users found.${C_RESET}"
        press_enter
        return
    fi
    
    echo -e "${C_CYAN}Available SSH users:${C_RESET}"
    cut -d: -f1 "$SSH_USERS_DB" | cat -n
    echo ""
    
    local username
    while true; do
        read -p "Enter username to delete: " username
        if grep -q "^$username:" "$SSH_USERS_DB" 2>/dev/null; then
            break
        fi
        echo -e "${C_RED}❌ User not found.${C_RESET}"
    done
    
    echo -e "\n${C_RED}⚠️ WARNING: This will permanently delete SSH user '$username'${C_RESET}"
    local confirm
    while true; do
        read -p "Type 'yes' to confirm: " confirm
        if [[ "$confirm" == "yes" ]]; then
            break
        else
            echo -e "${C_YELLOW}Cancelled. Type 'yes' to confirm.${C_RESET}"
            return
        fi
    done
    
    killall -u "$username" -9 &>/dev/null
    userdel -r "$username" &>/dev/null
    rm -f "$BANDWIDTH_DIR/${username}.usage"
    rm -rf "$BANDWIDTH_DIR/pidtrack/${username}"
    sed -i "/^$username:/d" "$SSH_USERS_DB"
    
    success "SSH user $username deleted"
    press_enter
}

lock_ssh_user() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    🔒 LOCK SSH USER                        ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    if [[ ! -f "$SSH_USERS_DB" || ! -s "$SSH_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No SSH users found.${C_RESET}"
        press_enter
        return
    fi
    
    echo -e "${C_CYAN}Available SSH users:${C_RESET}"
    cut -d: -f1 "$SSH_USERS_DB" | cat -n
    echo ""
    
    local username
    while true; do
        read -p "Enter username to lock: " username
        if grep -q "^$username:" "$SSH_USERS_DB" 2>/dev/null; then
            break
        fi
        echo -e "${C_RED}❌ User not found.${C_RESET}"
    done
    
    usermod -L "$username"
    killall -u "$username" -9 &>/dev/null
    
    local line=$(grep "^$username:" "$SSH_USERS_DB")
    IFS=: read -r user pass expiry limit bw used status <<< "$line"
    sed -i "s/^$username:.*/$username:$pass:$expiry:$limit:$bw:$used:LOCKED/" "$SSH_USERS_DB"
    
    success "SSH user $username locked"
    press_enter
}

unlock_ssh_user() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    🔓 UNLOCK SSH USER                      ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    if [[ ! -f "$SSH_USERS_DB" || ! -s "$SSH_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No SSH users found.${C_RESET}"
        press_enter
        return
    fi
    
    echo -e "${C_CYAN}Available SSH users:${C_RESET}"
    cut -d: -f1 "$SSH_USERS_DB" | cat -n
    echo ""
    
    local username
    while true; do
        read -p "Enter username to unlock: " username
        if grep -q "^$username:" "$SSH_USERS_DB" 2>/dev/null; then
            break
        fi
        echo -e "${C_RED}❌ User not found.${C_RESET}"
    done
    
    usermod -U "$username"
    
    local line=$(grep "^$username:" "$SSH_USERS_DB")
    IFS=: read -r user pass expiry limit bw used status <<< "$line"
    sed -i "s/^$username:.*/$username:$pass:$expiry:$limit:$bw:$used:ACTIVE/" "$SSH_USERS_DB"
    
    success "SSH user $username unlocked"
    press_enter
}

# ========== 17. SOCKS5 USER FUNCTIONS ==========
list_socks5_users() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    🔌 SOCKS5 USERS                          ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    if [[ ! -f "$SOCKS5_USERS_DB" || ! -s "$SOCKS5_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No SOCKS5 users found.${C_RESET}"
        press_enter
        return
    fi
    
    printf "${C_BOLD}${C_WHITE}%-15s | %-12s | %-8s | %-12s | %-15s | %-10s${C_RESET}\n" \
        "USERNAME" "EXPIRES" "CONNS" "BANDWIDTH" "USED" "STATUS"
    echo -e "${C_GRAY}───────────────────────────────────────────────────────────────────────────────${C_RESET}"
    
    while IFS=: read -r user pass expiry limit bandwidth_gb used_gb status; do
        [[ -z "$user" ]] && continue
        
        local used_bytes=$(cat "$BANDWIDTH_DIR/${user}.socks5.usage" 2>/dev/null || echo 0)
        local used_gb_display=$(awk "BEGIN {printf \"%.2f\", $used_bytes / 1073741824}")
        
        local status_color="$C_GREEN"
        [[ "$status" == "LOCKED" ]] && status_color="$C_YELLOW"
        [[ "$status" == "EXPIRED" ]] && status_color="$C_RED"
        [[ "$status" == "QUOTA_EXCEEDED" ]] && status_color="$C_RED"
        
        local bw_display="Unlimited"
        [[ "$bandwidth_gb" != "0" ]] && bw_display="${bandwidth_gb}GB"
        
        printf "%-15s | ${C_YELLOW}%-12s${C_RESET} | ${C_CYAN}%-8s${C_RESET} | ${C_ORANGE}%-12s${C_RESET} | ${C_WHITE}%-15s${C_RESET} | ${status_color}%-10s${C_RESET}\n" \
            "$user" "$expiry" "$limit" "$bw_display" "${used_gb_display}GB" "$status"
    done < "$SOCKS5_USERS_DB"
    
    echo -e "${C_GRAY}───────────────────────────────────────────────────────────────────────────────${C_RESET}"
    echo -e "${C_BOLD}Total SOCKS5 Users:${C_RESET} ${C_GREEN}$(wc -l < "$SOCKS5_USERS_DB")${C_RESET}"
    press_enter
}

view_socks5_bandwidth() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    📊 SOCKS5 USER BANDWIDTH                 ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    if [[ ! -f "$SOCKS5_USERS_DB" || ! -s "$SOCKS5_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No SOCKS5 users found.${C_RESET}"
        press_enter
        return
    fi
    
    echo -e "${C_CYAN}Available SOCKS5 users:${C_RESET}"
    cut -d: -f1 "$SOCKS5_USERS_DB" | cat -n
    echo ""
    
    local username
    while true; do
        read -p "Enter username: " username
        if grep -q "^$username:" "$SOCKS5_USERS_DB" 2>/dev/null; then
            break
        fi
        echo -e "${C_RED}❌ User not found.${C_RESET}"
    done
    
    local line=$(grep "^$username:" "$SOCKS5_USERS_DB")
    IFS=: read -r user pass expiry limit bw used status <<< "$line"
    
    local used_bytes=$(cat "$BANDWIDTH_DIR/${user}.socks5.usage" 2>/dev/null || echo 0)
    local used_gb=$(awk "BEGIN {printf \"%.2f\", $used_bytes / 1073741824}")
    local expiry_ts=$(date -d "$expiry" +%s 2>/dev/null || echo 0)
    local current_ts=$(date +%s)
    local days_left=$(((expiry_ts - current_ts) / 86400))
    [[ $days_left -lt 0 ]] && days_left=0
    
    echo -e "\n${C_YELLOW}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}                    🔌 USER: ${C_WHITE}$user${C_YELLOW}                        ${C_RESET}"
    echo -e "${C_YELLOW}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "  ${C_BOLD}Expires:${C_RESET}          ${C_YELLOW}$expiry${C_RESET} (${days_left} days left)"
    echo -e "  ${C_BOLD}Status:${C_RESET}           ${C_GREEN}$status${C_RESET}"
    echo -e "  ${C_BOLD}Connections:${C_RESET}      ${C_CYAN}$limit${C_RESET}"
    echo -e "  ${C_BOLD}Bandwidth Limit:${C_RESET}  ${C_ORANGE}${bw}GB${C_RESET}"
    echo -e "  ${C_BOLD}Used:${C_RESET}             ${C_WHITE}${used_gb}GB${C_RESET}"
    
    if [[ "$bw" != "0" ]]; then
        local percent=$(awk "BEGIN {printf \"%.1f\", ($used_bytes / ($bw * 1073741824)) * 100}")
        local bar_width=40
        local filled=$(awk "BEGIN {printf \"%.0f\", ($percent / 100) * $bar_width}")
        [[ $filled -gt $bar_width ]] && filled=$bar_width
        local empty=$((bar_width - filled))
        
        local bar_color="$C_GREEN"
        if (( $(awk "BEGIN {print ($percent > 80)}" ) )); then bar_color="$C_RED"
        elif (( $(awk "BEGIN {print ($percent > 50)}" ) )); then bar_color="$C_YELLOW"
        fi
        
        printf "  ${C_BOLD}Usage:${C_RESET}            ${bar_color}["
        for ((i=0; i<filled; i++)); do printf "█"; done
        for ((i=0; i<empty; i++)); do printf "░"; done
        printf "]${C_RESET} ${percent}%%\n"
    fi
    
    echo -e "${C_YELLOW}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    press_enter
}

renew_socks5_user() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    🔄 RENEW SOCKS5 USER                    ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    if [[ ! -f "$SOCKS5_USERS_DB" || ! -s "$SOCKS5_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No SOCKS5 users found.${C_RESET}"
        press_enter
        return
    fi
    
    echo -e "${C_CYAN}Available SOCKS5 users:${C_RESET}"
    cut -d: -f1 "$SOCKS5_USERS_DB" | cat -n
    echo ""
    
    local username
    while true; do
        read -p "Enter username to renew: " username
        if grep -q "^$username:" "$SOCKS5_USERS_DB" 2>/dev/null; then
            break
        fi
        echo -e "${C_RED}❌ User not found.${C_RESET}"
    done
    
    local days
    while true; do
        read -p "Enter number of days to extend: " days
        if [[ "$days" =~ ^[0-9]+$ ]] && [[ $days -gt 0 ]]; then
            break
        fi
        echo -e "${C_RED}❌ Invalid days.${C_RESET}"
    done
    
    local line=$(grep "^$username:" "$SOCKS5_USERS_DB")
    IFS=: read -r user pass expiry limit bw used status <<< "$line"
    
    local new_expiry=$(date -d "+$days days" +%Y-%m-%d)
    
    sed -i "s/^$username:.*/$username:$pass:$new_expiry:$limit:$bw:$used:ACTIVE/" "$SOCKS5_USERS_DB"
    
    success "SOCKS5 user $username renewed until $new_expiry"
    press_enter
}

delete_socks5_user() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    🗑️ DELETE SOCKS5 USER                   ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    if [[ ! -f "$SOCKS5_USERS_DB" || ! -s "$SOCKS5_USERS_DB" ]]; then
        echo -e "${C_YELLOW}ℹ️ No SOCKS5 users found.${C_RESET}"
        press_enter
        return
    fi
    
    echo -e "${C_CYAN}Available SOCKS5 users:${C_RESET}"
    cut -d: -f1 "$SOCKS5_USERS_DB" | cat -n
    echo ""
    
    local username
    while true; do
        read -p "Enter username to delete: " username
        if grep -q "^$username:" "$SOCKS5_USERS_DB" 2>/dev/null; then
            break
        fi
        echo -e "${C_RED}❌ User not found.${C_RESET}"
    done
    
    echo -e "\n${C_RED}⚠️ WARNING: This will permanently delete SOCKS5 user '$username'${C_RESET}"
    local confirm
    while true; do
        read -p "Type 'yes' to confirm: " confirm
        if [[ "$confirm" == "yes" ]]; then
            break
        else
            echo -e "${C_YELLOW}Cancelled. Type 'yes' to confirm.${C_RESET}"
            return
        fi
    done
    
    sed -i "/^$username:/d" "$SOCKS5_USERS_DB"
    sed -i "/^$username:/d" "$MICROSOCKS_AUTH"
    rm -f "$BANDWIDTH_DIR/${username}.socks5.usage"
    systemctl restart microsocks-main
    
    success "SOCKS5 user $username deleted"
    press_enter
}

# ========== 18. LIST ALL USERS ==========
list_users() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    👥 ALL USERS                            ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    echo -e "${C_CYAN}${C_BOLD}SSH USERS:${C_RESET}\n"
    if [[ -f "$SSH_USERS_DB" && -s "$SSH_USERS_DB" ]]; then
        printf "${C_BOLD}${C_WHITE}%-15s | %-12s | %-8s | %-12s | %-15s | %-10s${C_RESET}\n" \
            "USERNAME" "EXPIRES" "CONNS" "BANDWIDTH" "USED" "STATUS"
        echo -e "${C_GRAY}───────────────────────────────────────────────────────────────────────────────${C_RESET}"
        
        while IFS=: read -r user pass expiry limit bandwidth_gb used_gb status; do
            [[ -z "$user" ]] && continue
            
            local online=$(pgrep -c -u "$user" sshd 2>/dev/null || echo 0)
            local conn_string="${online}/${limit}"
            
            local used_bytes=$(cat "$BANDWIDTH_DIR/${user}.usage" 2>/dev/null || echo 0)
            local used_gb_display=$(awk "BEGIN {printf \"%.2f\", $used_bytes / 1073741824}")
            
            local status_color="$C_GREEN"
            [[ "$status" == "LOCKED" ]] && status_color="$C_YELLOW"
            [[ "$status" == "EXPIRED" ]] && status_color="$C_RED"
            [[ "$status" == "QUOTA_EXCEEDED" ]] && status_color="$C_RED"
            
            local bw_display="Unlimited"
            [[ "$bandwidth_gb" != "0" ]] && bw_display="${bandwidth_gb}GB"
            
            printf "%-15s | ${C_YELLOW}%-12s${C_RESET} | ${C_CYAN}%-8s${C_RESET} | ${C_ORANGE}%-12s${C_RESET} | ${C_WHITE}%-15s${C_RESET} | ${status_color}%-10s${C_RESET}\n" \
                "$user" "$expiry" "$conn_string" "$bw_display" "${used_gb_display}GB" "$status"
        done < "$SSH_USERS_DB"
        
        echo -e "${C_GRAY}───────────────────────────────────────────────────────────────────────────────${C_RESET}"
        echo -e "${C_BOLD}Total SSH Users:${C_RESET} ${C_GREEN}$(wc -l < "$SSH_USERS_DB")${C_RESET}"
    else
        echo -e "${C_YELLOW}ℹ️ No SSH users found.${C_RESET}"
    fi
    
    echo -e "\n${C_CYAN}${C_BOLD}SOCKS5 USERS:${C_RESET}\n"
    if [[ -f "$SOCKS5_USERS_DB" && -s "$SOCKS5_USERS_DB" ]]; then
        printf "${C_BOLD}${C_WHITE}%-15s | %-12s | %-8s | %-12s | %-15s | %-10s${C_RESET}\n" \
            "USERNAME" "EXPIRES" "CONNS" "BANDWIDTH" "USED" "STATUS"
        echo -e "${C_GRAY}───────────────────────────────────────────────────────────────────────────────${C_RESET}"
        
        while IFS=: read -r user pass expiry limit bandwidth_gb used_gb status; do
            [[ -z "$user" ]] && continue
            
            local used_bytes=$(cat "$BANDWIDTH_DIR/${user}.socks5.usage" 2>/dev/null || echo 0)
            local used_gb_display=$(awk "BEGIN {printf \"%.2f\", $used_bytes / 1073741824}")
            
            local status_color="$C_GREEN"
            [[ "$status" == "LOCKED" ]] && status_color="$C_YELLOW"
            [[ "$status" == "EXPIRED" ]] && status_color="$C_RED"
            [[ "$status" == "QUOTA_EXCEEDED" ]] && status_color="$C_RED"
            
            local bw_display="Unlimited"
            [[ "$bandwidth_gb" != "0" ]] && bw_display="${bandwidth_gb}GB"
            
            printf "%-15s | ${C_YELLOW}%-12s${C_RESET} | ${C_CYAN}%-8s${C_RESET} | ${C_ORANGE}%-12s${C_RESET} | ${C_WHITE}%-15s${C_RESET} | ${status_color}%-10s${C_RESET}\n" \
                "$user" "$expiry" "$limit" "$bw_display" "${used_gb_display}GB" "$status"
        done < "$SOCKS5_USERS_DB"
        
        echo -e "${C_GRAY}───────────────────────────────────────────────────────────────────────────────${C_RESET}"
        echo -e "${C_BOLD}Total SOCKS5 Users:${C_RESET} ${C_GREEN}$(wc -l < "$SOCKS5_USERS_DB")${C_RESET}"
    else
        echo -e "${C_YELLOW}ℹ️ No SOCKS5 users found.${C_RESET}"
    fi
    
    press_enter
}

# ========== 19. SUPER SPEED BOOSTER ==========
apply_speed_booster() {
    clear
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}              ⚡ SUPER SPEED BOOSTER - DNSTT                ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    echo -e "${C_BOLD}${C_WHITE}Select Speed Level for Maximum DNSTT Performance:${C_RESET}\n"
    
    echo -e "  ${C_GREEN}[1]${C_RESET} ${C_WHITE}LIGHTNING${C_RESET}   - Light speed (1-5 users)"
    echo -e "  ${C_GREEN}[2]${C_RESET} ${C_WHITE}STORM${C_RESET}      - Storm speed (5-15 users)"
    echo -e "  ${C_GREEN}[3]${C_RESET} ${C_WHITE}TURBO${C_RESET}      - Turbo speed (15-30 users)"
    echo -e "  ${C_GREEN}[4]${C_RESET} ${C_WHITE}ULTRA${C_RESET}      - Ultra speed (30-50 users)"
    echo -e "  ${C_GREEN}[5]${C_RESET} ${C_WHITE}EXTREME${C_RESET}    - Extreme speed (50-100 users)"
    echo -e "  ${C_GREEN}[6]${C_RESET} ${C_WHITE}MEGA${C_RESET}       - Mega speed (100-200 users)"
    echo -e "  ${C_GREEN}[7]${C_RESET} ${C_WHITE}TITAN${C_RESET}      - Titan speed (200+ users)"
    echo ""
    echo -e "  ${C_RED}[0]${C_RESET} Cancel"
    echo ""
    
    local level
    while true; do
        read -p "👉 Select level [1-7]: " level
        case $level in
            1|2|3|4|5|6|7) break ;;
            0) echo -e "${C_YELLOW}Cancelled${C_RESET}"; return ;;
            *) echo -e "${C_RED}❌ Invalid choice${C_RESET}" ;;
        esac
    done
    
    echo -e "\n${C_BLUE}⚡ Applying Super Speed Booster level $level...${C_RESET}"
    echo -e "${C_DIM}Optimizing DNSTT for maximum performance...${C_RESET}\n"
    
    case $level in
        1)
            echo -e "${C_CYAN}▶ LIGHTNING MODE - Light speed activation${C_RESET}"
            sysctl -w net.core.rmem_default=1048576 >/dev/null 2>&1
            sysctl -w net.core.wmem_default=1048576 >/dev/null 2>&1
            sysctl -w net.core.rmem_max=16777216 >/dev/null 2>&1
            sysctl -w net.core.wmem_max=16777216 >/dev/null 2>&1
            sysctl -w net.ipv4.udp_mem="1048576 2097152 16777216" >/dev/null 2>&1
            sysctl -w net.ipv4.udp_rmem_min=32768 >/dev/null 2>&1
            sysctl -w net.ipv4.udp_wmem_min=32768 >/dev/null 2>&1
            sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1
            sysctl -w net.core.netdev_max_backlog=5000 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_rmem="4096 87380 16777216" >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_wmem="4096 65536 16777216" >/dev/null 2>&1
            echo -e "${C_GREEN}✅ DNSTT buffer: 16MB${C_RESET}"
            echo -e "${C_GREEN}✅ BBR congestion control activated${C_RESET}"
            ;;
        2)
            echo -e "${C_CYAN}▶ STORM MODE - Storm speed activation${C_RESET}"
            sysctl -w net.core.rmem_default=2097152 >/dev/null 2>&1
            sysctl -w net.core.wmem_default=2097152 >/dev/null 2>&1
            sysctl -w net.core.rmem_max=33554432 >/dev/null 2>&1
            sysctl -w net.core.wmem_max=33554432 >/dev/null 2>&1
            sysctl -w net.ipv4.udp_mem="2097152 4194304 33554432" >/dev/null 2>&1
            sysctl -w net.ipv4.udp_rmem_min=65536 >/dev/null 2>&1
            sysctl -w net.ipv4.udp_wmem_min=65536 >/dev/null 2>&1
            sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1
            sysctl -w net.core.netdev_max_backlog=10000 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_rmem="4096 87380 33554432" >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_wmem="4096 65536 33554432" >/dev/null 2>&1
            sysctl -w net.core.optmem_max=40960 >/dev/null 2>&1
            echo -e "${C_GREEN}✅ DNSTT buffer: 32MB${C_RESET}"
            echo -e "${C_GREEN}✅ BBR + FQ activated${C_RESET}"
            ;;
        3)
            echo -e "${C_CYAN}▶ TURBO MODE - Turbo speed activation${C_RESET}"
            sysctl -w net.core.rmem_default=4194304 >/dev/null 2>&1
            sysctl -w net.core.wmem_default=4194304 >/dev/null 2>&1
            sysctl -w net.core.rmem_max=67108864 >/dev/null 2>&1
            sysctl -w net.core.wmem_max=67108864 >/dev/null 2>&1
            sysctl -w net.ipv4.udp_mem="4194304 8388608 67108864" >/dev/null 2>&1
            sysctl -w net.ipv4.udp_rmem_min=131072 >/dev/null 2>&1
            sysctl -w net.ipv4.udp_wmem_min=131072 >/dev/null 2>&1
            sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1
            sysctl -w net.core.netdev_max_backlog=20000 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_rmem="4096 87380 67108864" >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_wmem="4096 65536 67108864" >/dev/null 2>&1
            sysctl -w net.core.optmem_max=81920 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
            echo -e "${C_GREEN}✅ DNSTT buffer: 64MB${C_RESET}"
            echo -e "${C_GREEN}✅ Full TCP optimizations activated${C_RESET}"
            ;;
        4)
            echo -e "${C_CYAN}▶ ULTRA MODE - Ultra speed activation${C_RESET}"
            sysctl -w net.core.rmem_default=8388608 >/dev/null 2>&1
            sysctl -w net.core.wmem_default=8388608 >/dev/null 2>&1
            sysctl -w net.core.rmem_max=134217728 >/dev/null 2>&1
            sysctl -w net.core.wmem_max=134217728 >/dev/null 2>&1
            sysctl -w net.ipv4.udp_mem="8388608 16777216 134217728" >/dev/null 2>&1
            sysctl -w net.ipv4.udp_rmem_min=262144 >/dev/null 2>&1
            sysctl -w net.ipv4.udp_wmem_min=262144 >/dev/null 2>&1
            sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1
            sysctl -w net.core.netdev_max_backlog=50000 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_rmem="4096 87380 134217728" >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_wmem="4096 65536 134217728" >/dev/null 2>&1
            sysctl -w net.core.optmem_max=163840 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_dsack=1 >/dev/null 2>&1
            echo -e "${C_GREEN}✅ DNSTT buffer: 128MB${C_RESET}"
            echo -e "${C_GREEN}✅ Advanced TCP optimizations activated${C_RESET}"
            ;;
        5)
            echo -e "${C_CYAN}▶ EXTREME MODE - Extreme speed activation${C_RESET}"
            sysctl -w net.core.rmem_default=16777216 >/dev/null 2>&1
            sysctl -w net.core.wmem_default=16777216 >/dev/null 2>&1
            sysctl -w net.core.rmem_max=268435456 >/dev/null 2>&1
            sysctl -w net.core.wmem_max=268435456 >/dev/null 2>&1
            sysctl -w net.ipv4.udp_mem="16777216 33554432 268435456" >/dev/null 2>&1
            sysctl -w net.ipv4.udp_rmem_min=524288 >/dev/null 2>&1
            sysctl -w net.ipv4.udp_wmem_min=524288 >/dev/null 2>&1
            sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1
            sysctl -w net.core.netdev_max_backlog=100000 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_rmem="4096 87380 268435456" >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_wmem="4096 65536 268435456" >/dev/null 2>&1
            sysctl -w net.core.optmem_max=327680 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_dsack=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_frto=2 >/dev/null 2>&1
            echo -e "${C_GREEN}✅ DNSTT buffer: 256MB${C_RESET}"
            echo -e "${C_GREEN}✅ Extreme TCP optimizations activated${C_RESET}"
            ;;
        6)
            echo -e "${C_CYAN}▶ MEGA MODE - Mega speed activation${C_RESET}"
            sysctl -w net.core.rmem_default=33554432 >/dev/null 2>&1
            sysctl -w net.core.wmem_default=33554432 >/dev/null 2>&1
            sysctl -w net.core.rmem_max=536870912 >/dev/null 2>&1
            sysctl -w net.core.wmem_max=536870912 >/dev/null 2>&1
            sysctl -w net.ipv4.udp_mem="33554432 67108864 536870912" >/dev/null 2>&1
            sysctl -w net.ipv4.udp_rmem_min=1048576 >/dev/null 2>&1
            sysctl -w net.ipv4.udp_wmem_min=1048576 >/dev/null 2>&1
            sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1
            sysctl -w net.core.netdev_max_backlog=200000 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_rmem="4096 87380 536870912" >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_wmem="4096 65536 536870912" >/dev/null 2>&1
            sysctl -w net.core.optmem_max=655360 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_dsack=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_frto=2 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_adv_win_scale=1 >/dev/null 2>&1
            echo -e "${C_GREEN}✅ DNSTT buffer: 512MB${C_RESET}"
            echo -e "${C_GREEN}✅ Enterprise-grade optimizations activated${C_RESET}"
            ;;
        7)
            echo -e "${C_CYAN}▶ TITAN MODE - Titan speed activation${C_RESET}"
            sysctl -w net.core.rmem_default=67108864 >/dev/null 2>&1
            sysctl -w net.core.wmem_default=67108864 >/dev/null 2>&1
            sysctl -w net.core.rmem_max=1073741824 >/dev/null 2>&1
            sysctl -w net.core.wmem_max=1073741824 >/dev/null 2>&1
            sysctl -w net.ipv4.udp_mem="67108864 134217728 1073741824" >/dev/null 2>&1
            sysctl -w net.ipv4.udp_rmem_min=2097152 >/dev/null 2>&1
            sysctl -w net.ipv4.udp_wmem_min=2097152 >/dev/null 2>&1
            sysctl -w net.core.default_qdisc=fq >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_congestion_control=bbr >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_fastopen=3 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_slow_start_after_idle=0 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_tw_reuse=1 >/dev/null 2>&1
            sysctl -w net.core.netdev_max_backlog=500000 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_mtu_probing=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_rmem="4096 87380 1073741824" >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_wmem="4096 65536 1073741824" >/dev/null 2>&1
            sysctl -w net.core.optmem_max=1310720 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_window_scaling=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_sack=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_dsack=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_frto=2 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_adv_win_scale=1 >/dev/null 2>&1
            sysctl -w net.ipv4.tcp_low_latency=1 >/dev/null 2>&1
            echo -e "${C_GREEN}✅ DNSTT buffer: 1GB${C_RESET}"
            echo -e "${C_GREEN}✅ Maximum performance optimizations activated${C_RESET}"
            ;;
    esac
    
    echo -e "\n${C_BLUE}🔧 DNSTT Noise Protocol Optimization...${C_RESET}"
    echo "fs.file-max = 2097152" >> /etc/sysctl.conf 2>/dev/null
    echo "fs.nr_open = 2097152" >> /etc/sysctl.conf 2>/dev/null
    echo "net.ipv4.tcp_timestamps = 1" >> /etc/sysctl.conf 2>/dev/null
    echo "net.ipv4.tcp_keepalive_time = 120" >> /etc/sysctl.conf 2>/dev/null
    echo "net.ipv4.tcp_keepalive_intvl = 30" >> /etc/sysctl.conf 2>/dev/null
    echo "net.ipv4.tcp_keepalive_probes = 3" >> /etc/sysctl.conf 2>/dev/null
    
    cat > /etc/sysctl.d/99-voltron-dnstt-super-speed.conf << EOF
# ============================================================
# VOLTRON GATE - SUPER SPEED BOOSTER
# Applied on: $(date)
# Level: $level
# ============================================================

net.core.rmem_default=$(sysctl -n net.core.rmem_default 2>/dev/null || echo 1048576)
net.core.wmem_default=$(sysctl -n net.core.wmem_default 2>/dev/null || echo 1048576)
net.core.rmem_max=$(sysctl -n net.core.rmem_max 2>/dev/null || echo 16777216)
net.core.wmem_max=$(sysctl -n net.core.wmem_max 2>/dev/null || echo 16777216)
net.ipv4.udp_mem=$(sysctl -n net.ipv4.udp_mem 2>/dev/null || echo "1048576 2097152 16777216")
net.ipv4.udp_rmem_min=$(sysctl -n net.ipv4.udp_rmem_min 2>/dev/null || echo 32768)
net.ipv4.udp_wmem_min=$(sysctl -n net.ipv4.udp_wmem_min 2>/dev/null || echo 32768)
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.netdev_max_backlog=$(sysctl -n net.core.netdev_max_backlog 2>/dev/null || echo 5000)
net.core.optmem_max=$(sysctl -n net.core.optmem_max 2>/dev/null || echo 20480)
net.ipv4.tcp_fastopen=3
net.ipv4.tcp_slow_start_after_idle=0
net.ipv4.tcp_tw_reuse=1
net.ipv4.tcp_rmem=$(sysctl -n net.ipv4.tcp_rmem 2>/dev/null || echo "4096 87380 16777216")
net.ipv4.tcp_wmem=$(sysctl -n net.ipv4.tcp_wmem 2>/dev/null || echo "4096 65536 16777216")
net.ipv4.tcp_mtu_probing=1
net.ipv4.tcp_window_scaling=1
net.ipv4.tcp_sack=1
net.ipv4.tcp_dsack=1
net.ipv4.tcp_frto=2
fs.file-max=2097152
fs.nr_open=2097152
net.ipv4.tcp_timestamps=1
net.ipv4.tcp_keepalive_time=120
net.ipv4.tcp_keepalive_intvl=30
net.ipv4.tcp_keepalive_probes=3
# ============================================================
EOF

    echo -e "\n${C_BLUE}🔄 Restarting DNSTT services...${C_RESET}"
    if [[ -f "$TUNNELS_DB" ]]; then
        while IFS=: read -r transport domain backend backend_port tag key tunnel_port mtu; do
            if [[ "$transport" == "dnstt" ]]; then
                local service="voltron-${transport}-${tag}"
                if systemctl is-active --quiet "$service" 2>/dev/null; then
                    systemctl restart "$service"
                    echo -e "  ${C_GREEN}✅ Restarted: $service${C_RESET}"
                fi
            fi
        done < "$TUNNELS_DB"
    fi
    
    systemctl restart gost-dns 2>/dev/null
    systemctl restart voltron-limiter 2>/dev/null
    
    echo -e "\n${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}              ✅ SUPER SPEED BOOSTER APPLIED!                 ${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "  ${C_BOLD}Level:${C_RESET}          ${C_YELLOW}$level${C_RESET}"
    echo -e "  ${C_BOLD}DNSTT Buffer:${C_RESET}   ${C_GREEN}$(sysctl -n net.core.rmem_max 2>/dev/null | awk '{printf \"%.0f MB\", $1/1048576}')${C_RESET}"
    echo -e "  ${C_BOLD}Congestion:${C_RESET}     ${C_GREEN}$(sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null)${C_RESET}"
    echo -e "  ${C_BOLD}Queue Disc:${C_RESET}     ${C_GREEN}$(sysctl -n net.core.default_qdisc 2>/dev/null)${C_RESET}"
    echo -e "  ${C_BOLD}TCP Fast Open:${C_RESET}  ${C_GREEN}$(sysctl -n net.ipv4.tcp_fastopen 2>/dev/null)${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    
    echo -e "\n${C_YELLOW}💡 To verify DNSTT performance improvement:${C_RESET}"
    echo -e "  ${C_DIM}1. Check DNSTT logs: journalctl -u voltron-dnstt-* -f${C_RESET}"
    echo -e "  ${C_DIM}2. Check UDP buffer: sysctl net.core.rmem_max${C_RESET}"
    echo -e "  ${C_DIM}3. Monitor bandwidth: bmon or nethogs${C_RESET}"
    
    press_enter
}

# ========== 20. SETUP FIREWALL ==========
setup_firewall() {
    log "Setting up firewall..."
    
    iptables-save > "$BACKUP_DIR/iptables_backup_$(date +%Y%m%d).txt" 2>/dev/null || true
    
    systemctl stop systemd-resolved 2>/dev/null || true
    systemctl disable systemd-resolved 2>/dev/null || true
    
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-port 53 2>/dev/null || true
    iptables -D INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || true
    
    iptables -t nat -I PREROUTING -p udp --dport 53 -j REDIRECT --to-port 53
    iptables -I INPUT -p udp --dport 53 -j ACCEPT
    iptables -I INPUT -p tcp --dport "$SSH_PORT" -j ACCEPT
    iptables -I INPUT -p tcp --dport "$SOCKS5_PORT" -j ACCEPT
    
    mkdir -p /etc/iptables
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
    
    success "Firewall configured"
    press_enter
}

# ========== 21. SHOW SYSTEM INFO ==========
show_system_info() {
    echo -e "\n${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}                    📊 SYSTEM INFORMATION                    ${C_RESET}"
    echo -e "${C_CYAN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    echo -e "  ${C_BOLD}📌 Server IP:${C_RESET}      $(get_ip)"
    echo -e "  ${C_BOLD}💾 Memory:${C_RESET}         $(free -h | awk '/^Mem:/{print $3 "/" $2}')"
    echo -e "  ${C_BOLD}💿 Disk:${C_RESET}           $(df -h / | awk 'NR==2{print $3 "/" $2}')"
    echo -e "  ${C_BOLD}⏱️  Uptime:${C_RESET}        $(uptime -p | sed 's/up //')"
    echo -e "  ${C_BOLD}🔒 Active SSH Users:${C_RESET} $(who | wc -l)"
    echo -e "  ${C_BOLD}🌐 DNS Tunnels:${C_RESET}    $(wc -l < "$TUNNELS_DB" 2>/dev/null || echo 0)"
    echo -e "  ${C_BOLD}📊 Bandwidth Usage:${C_RESET} $(du -sh "$BANDWIDTH_DIR" 2>/dev/null | cut -f1 || echo 0)"
    echo -e "  ${C_BOLD}👥 SSH Users:${C_RESET}      $(wc -l < "$SSH_USERS_DB" 2>/dev/null || echo 0)"
    echo -e "  ${C_BOLD}🔌 SOCKS5 Users:${C_RESET}   $(wc -l < "$SOCKS5_USERS_DB" 2>/dev/null || echo 0)"
    
    press_enter
}

# ========== 22. UNINSTALL SCRIPT ==========
uninstall_script() {
    clear
    echo -e "${C_RED}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_RED}${C_BOLD}                    🔥 UNINSTALL VOLTRON GATE                ${C_RESET}"
    echo -e "${C_RED}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}\n"
    
    echo -e "${C_YELLOW}⚠️ WARNING: This will PERMANENTLY remove Voltron Gate from this VPS!${C_RESET}\n"
    echo -e "This will remove:"
    echo -e "  - All DNS tunnels (DNSTT, Slipstream)"
    echo -e "  - All SSH and SOCKS5 users"
    echo -e "  - All configuration files"
    echo -e "  - All services (gost, microsocks, limiter)"
    echo -e "  - All binaries (dnstt-server, slipstream-server)"
    echo -e "  - The 'menu' and 'voltron' commands"
    echo ""
    
    local confirm
    while true; do
        read -p "Type 'yes' to confirm uninstall: " confirm
        if [[ "$confirm" == "yes" ]]; then
            break
        else
            echo -e "${C_YELLOW}Cancelled. Type 'yes' to confirm.${C_RESET}"
            return
        fi
    done
    
    echo -e "\n${C_BLUE}🛑 Stopping and removing all services...${C_RESET}"
    
    if [[ -f "$TUNNELS_DB" ]]; then
        while IFS=: read -r transport domain backend backend_port tag key tunnel_port mtu; do
            local service="voltron-${transport}-${tag}"
            systemctl stop "$service" 2>/dev/null || true
            systemctl disable "$service" 2>/dev/null || true
            rm -f "/etc/systemd/system/${service}.service"
            
            if [[ "$backend" == "socks" ]]; then
                local backend_service="microsocks-${tag}"
                systemctl stop "$backend_service" 2>/dev/null || true
                systemctl disable "$backend_service" 2>/dev/null || true
                rm -f "/etc/systemd/system/${backend_service}.service"
            fi
        done < "$TUNNELS_DB"
    fi
    
    systemctl stop gost-dns 2>/dev/null || true
    systemctl disable gost-dns 2>/dev/null || true
    rm -f "$GOST_SERVICE"
    
    systemctl stop microsocks-main 2>/dev/null || true
    systemctl disable microsocks-main 2>/dev/null || true
    rm -f "/etc/systemd/system/microsocks-main.service"
    
    systemctl stop voltron-limiter 2>/dev/null || true
    systemctl disable voltron-limiter 2>/dev/null || true
    rm -f "$LIMITER_SERVICE"
    
    systemctl daemon-reload
    
    echo -e "${C_BLUE}🗑️ Removing binaries...${C_RESET}"
    rm -f "$BIN_DIR/gost"
    rm -f "$BIN_DIR/dnstt-server"
    rm -f "$BIN_DIR/dnstt-client"
    rm -f "$BIN_DIR/slipstream-server"
    rm -f "$BIN_DIR/microsocks"
    rm -f "$BIN_DIR/voltron-limiter.sh"
    
    echo -e "${C_BLUE}🗑️ Removing configuration files...${C_RESET}"
    rm -rf "$DB_DIR"
    rm -f "$SSHD_FF_CONFIG"
    
    echo -e "${C_BLUE}🗑️ Removing commands...${C_RESET}"
    rm -f /usr/local/bin/menu
    rm -f /usr/local/bin/voltron
    
    echo -e "${C_BLUE}🧹 Removing iptables rules...${C_RESET}"
    iptables -t nat -D PREROUTING -p udp --dport 53 -j REDIRECT --to-port 53 2>/dev/null || true
    iptables -D INPUT -p udp --dport 53 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
    iptables -D INPUT -p tcp --dport 1080 -j ACCEPT 2>/dev/null || true
    
    echo -e "${C_BLUE}🧹 Cleaning up DNS resolver...${C_RESET}"
    systemctl start systemd-resolved 2>/dev/null || true
    systemctl enable systemd-resolved 2>/dev/null || true
    chattr -i /etc/resolv.conf 2>/dev/null || true
    rm -f /etc/resolv.conf
    echo "nameserver 127.0.0.53" > /etc/resolv.conf
    chattr +i /etc/resolv.conf 2>/dev/null || true
    
    echo -e "\n${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}              ✅ VOLTRON GATE UNINSTALLED!                    ${C_RESET}"
    echo -e "${C_GREEN}${C_BOLD}═══════════════════════════════════════════════════════════════${C_RESET}"
    echo -e "\n${C_YELLOW}All Voltron Gate components have been removed from this VPS.${C_RESET}"
    echo -e "${C_YELLOW}The 'menu' and 'voltron' commands are no longer available.${C_RESET}\n"
    
    exit 0
}

# ========== 23. MAIN MENU ==========
main_menu() {
    while true; do
        clear
        echo -e "${C_PURPLE}╔═══════════════════════════════════════════════════════════════╗${C_RESET}"
        echo -e "${C_PURPLE}║${C_BOLD}         🔥 VOLTRON GATE v7.2 (DNSTM STYLE) 🔥${C_RESET}${C_PURPLE}        ║${C_RESET}"
        echo -e "${C_PURPLE}║${C_WHITE}    Bandwidth + Expiry + DNS Tunnel Manager${C_RESET}${C_PURPLE}          ║${C_RESET}"
        echo -e "${C_PURPLE}╚═══════════════════════════════════════════════════════════════╝${C_RESET}"
        echo ""
        
        echo -e "  ${C_GREEN}${C_BOLD}📦 DNS TUNNEL MANAGEMENT${C_RESET}"
        echo -e "  ──────────────────────"
        echo -e "  ${C_GREEN}[1]${C_RESET} Install All Binaries"
        echo -e "  ${C_GREEN}[2]${C_RESET} Add New Tunnel (DNSTT or Slipstream)"
        echo -e "  ${C_GREEN}[3]${C_RESET} List Tunnels"
        echo -e "  ${C_GREEN}[4]${C_RESET} Delete Tunnel"
        echo ""
        
        echo -e "  ${C_GREEN}${C_BOLD}👥 USER MANAGEMENT${C_RESET}"
        echo -e "  ──────────────"
        echo -e "  ${C_GREEN}[5]${C_RESET} SSH User Manager"
        echo -e "  ${C_GREEN}[6]${C_RESET} SOCKS5 User Manager"
        echo -e "  ${C_GREEN}[7]${C_RESET} List All Users"
        echo ""
        
        echo -e "  ${C_GREEN}${C_BOLD}⚡ PERFORMANCE${C_RESET}"
        echo -e "  ────────────"
        echo -e "  ${C_GREEN}[8]${C_RESET} Apply Super Speed Booster (DNSTT)"
        echo -e "  ${C_GREEN}[9]${C_RESET} Setup Firewall"
        echo -e "  ${C_GREEN}[A]${C_RESET} Install Limiter Service"
        echo ""
        
        echo -e "  ${C_GREEN}${C_BOLD}ℹ️ INFO${C_RESET}"
        echo -e "  ────────────"
        echo -e "  ${C_GREEN}[B]${C_RESET} System Info"
        echo ""
        
        echo -e "  ${C_RED}${C_BOLD}[0]${C_RESET} Exit"
        echo -e "  ${C_RED}${C_BOLD}[99]${C_RESET} Uninstall Voltron Gate"
        echo ""
        
        local opt
        while true; do
            read -p "👉 Select option: " opt
            case $opt in
                1|2|3|4|5|6|7|8|9|A|a|B|b|0|99)
                    break
                    ;;
                *)
                    echo -e "${C_RED}❌ Invalid option. Please enter a valid option.${C_RESET}"
                    ;;
            esac
        done
        
        opt=$(echo "$opt" | tr '[:lower:]' '[:upper:]')
        
        case $opt in
            1) install_binaries ;;
            2) add_tunnel ;;
            3) list_tunnels ;;
            4) delete_tunnel ;;
            5) ssh_user_menu ;;
            6) socks5_user_menu ;;
            7) list_users ;;
            8) apply_speed_booster ;;
            9) setup_firewall ;;
            A) setup_limiter ;;
            B) show_system_info ;;
            0) 
                echo -e "${C_GREEN}👋 Goodbye!${C_RESET}"
                exit 0 
                ;;
            99) uninstall_script ;;
        esac
    done
}

# ========== CREATE COMMAND ALIAS ==========
setup_command() {
    if [[ "$0" != "/usr/local/bin/menu" ]] && [[ "$0" != "/usr/local/bin/voltron" ]]; then
        cp "$0" /usr/local/bin/menu
        chmod +x /usr/local/bin/menu
        cp "$0" /usr/local/bin/voltron
        chmod +x /usr/local/bin/voltron
        echo -e "${C_GREEN}✅ Commands created: 'menu' and 'voltron'${C_RESET}"
    fi
}

# ========== INITIAL SETUP ==========
if [[ $EUID -ne 0 ]]; then
    echo -e "${C_RED}❌ Error: This script requires root privileges to run.${C_RESET}"
    exit 1
fi

mkdir -p $DB_DIR $BACKUP_DIR $BANNER_DIR $BANDWIDTH_DIR $PID_DIR $CONFIG_DIR
touch $SSH_USERS_DB $SOCKS5_USERS_DB $TUNNELS_DB $MICROSOCKS_AUTH

setup_command

if ! systemctl is-active --quiet microsocks-main 2>/dev/null; then
    start_microsocks
fi

if ! systemctl is-active --quiet voltron-limiter 2>/dev/null; then
    setup_limiter
fi

main_menu
