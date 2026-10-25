#!/bin/bash
# =========================================================
# RYZENNC Panel - Automated Installation & Management Script
# =========================================================

# Ensure running in bash
if [ -z "$BASH_VERSION" ]; then
    if command -v bash > /dev/null 2>&1; then
        exec bash "$0" "$@"
    fi
fi

# Force a UTF-8 locale so box drawing / Vietnamese text is measured correctly
case "${LC_ALL:-${LANG:-}}" in
    *UTF-8*|*utf8*|*UTF8*) ;;
    *) export LC_ALL=C.UTF-8 2>/dev/null || true ;;
esac

# Enhanced 256-color palette for professional hosting CLI
GREEN='\033[38;5;48m'
EMERALD='\033[38;5;42m'
CYAN='\033[38;5;51m'
TEAL='\033[38;5;37m'
BLUE='\033[38;5;75m'
VIOLET='\033[38;5;141m'
YELLOW='\033[38;5;220m'
AMBER='\033[38;5;214m'
ORANGE='\033[38;5;208m'
RED='\033[38;5;196m'
WHITE='\033[1;37m'
LIGHT='\033[38;5;252m'
GRAY='\033[38;5;242m'
DARKGRAY='\033[38;5;236m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Ensure initial tools exist if cloning is needed
if [ ! -f "package.json" ] && [ ! -f "Ryzennc/package.json" ]; then
    echo -e "  \033[38;5;51m⚡ Initializing RYZENNC Panel files...\033[0m"
    if ! command -v git > /dev/null 2>&1 || ! command -v curl > /dev/null 2>&1; then
        if command -v apt-get > /dev/null 2>&1; then
            (export DEBIAN_FRONTEND=noninteractive; apt-get update -y -q > /dev/null 2>&1 || sudo apt-get update -y -q > /dev/null 2>&1 || true)
            (export DEBIAN_FRONTEND=noninteractive; apt-get install -y -q git curl tar ca-certificates > /dev/null 2>&1 || sudo apt-get install -y -q git curl tar ca-certificates > /dev/null 2>&1 || true)
        elif command -v yum > /dev/null 2>&1; then
            (yum install -y git curl tar ca-certificates > /dev/null 2>&1 || sudo yum install -y git curl tar ca-certificates > /dev/null 2>&1 || true)
        elif command -v dnf > /dev/null 2>&1; then
            (dnf install -y git curl tar ca-certificates > /dev/null 2>&1 || sudo dnf install -y git curl tar ca-certificates > /dev/null 2>&1 || true)
        fi
    fi
    git clone https://github.com/Ryzenhost/ryzenhost Ryzennc 2>/dev/null || git clone https://github.com/Ryzenhost/ryzenhost.git Ryzennc 2>/dev/null || true
fi

if [ -f "package.json" ]; then
    WORK_DIR="."
elif [ -d "Ryzennc" ] && [ -f "Ryzennc/package.json" ]; then
    WORK_DIR="Ryzennc"
else
    WORK_DIR="."
fi
cd "$WORK_DIR" || true

CACHED_OS_TYPE=""
CACHED_SYS_ARCH=""
CACHED_SYS_IP=""

detect_os() {
    OS_TYPE="Linux"
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_TYPE=${PRETTY_NAME:-${ID:-"Linux"}}
    elif command -v uname &> /dev/null; then
        OS_TYPE=$(uname -s)
    fi
}

get_sys_ip() {
    if [ -n "$CACHED_SYS_IP" ]; then
        echo "$CACHED_SYS_IP"
        return
    fi
    local ip=$(hostname -I 2>/dev/null | awk '{print $1}')
    if [ -z "$ip" ]; then
        ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7}')
    fi
    if [ -z "$ip" ] || [ "$ip" = "127.0.0.1" ]; then
        ip=$(curl -s --connect-timeout 0.5 --max-time 0.8 ifconfig.me 2>/dev/null || echo "127.0.0.1")
    fi
    CACHED_SYS_IP="${ip:-127.0.0.1}"
    echo "$CACHED_SYS_IP"
}

check_port_active() {
    local port="$1"
    if command -v ss > /dev/null 2>&1; then
        ss -lnt 2>/dev/null | grep -q ":$port " && return 0
    elif command -v netstat > /dev/null 2>&1; then
        netstat -lnt 2>/dev/null | grep -q ":$port " && return 0
    elif [ -d "/proc/net" ]; then
        local hex=$(printf '%04X' "$port")
        grep -q ":$hex " /proc/net/tcp /proc/net/tcp6 2>/dev/null && return 0
    fi
    return 1
}

detect_sys_meta() {
    if [ -z "$CACHED_OS_TYPE" ]; then
        detect_os
        CACHED_OS_TYPE="$OS_TYPE"
        CACHED_SYS_ARCH=$(uname -m 2>/dev/null || echo "x86_64")
    fi
    OS_TYPE="$CACHED_OS_TYPE"
    SYS_ARCH="$CACHED_SYS_ARCH"
    SYS_RAM=$(free -h 2>/dev/null | awk '/^Mem:/{print $3 "/" $2}' || echo "N/A")
    SYS_IP=$(get_sys_ip)
    
    SYS_STATE="${GRAY}○ STOPPED${NC}"
    if check_port_active 6767; then
        SYS_STATE="${GREEN}● ONLINE (:6767)${NC}"
    elif check_port_active 3000; then
        SYS_STATE="${CYAN}● DEV MODE (:3000)${NC}"
    elif run_pm2 list 2>/dev/null | grep -q "ryzennc-main.*online"; then
        SYS_STATE="${GREEN}● ONLINE (:6767)${NC}"
    elif run_pm2 list 2>/dev/null | grep -q "ryzennc-admin.*online"; then
        SYS_STATE="${CYAN}● DEV MODE (:3000)${NC}"
    fi
}

banner_row() {
    # banner_row COLOR TEXT  (hàng có viền phải, canh theo số ký tự)
    local c="$1" t="$2"
    local pad=$((60 - ${#t}))
    [ $pad -lt 0 ] && pad=0
    printf "  ${EMERALD}${BOLD}│${NC} %b%s${NC}%*s ${EMERALD}${BOLD}│${NC}\n" "$c" "$t" "$pad" ""
}

menu_item() {
    # menu_item NUM COLOR TITLE DESC
    local t="$3" d="$4"
    t="${t:0:24}"; d="${d:0:31}"
    local pt=$((24 - ${#t})) pd=$((31 - ${#d}))
    printf "  ${EMERALD}│${NC}  %b${BOLD}[%s]${NC}  ${WHITE}${BOLD}%s${NC}%*s${GRAY}%s${NC}%*s${EMERALD}│${NC}\n" "$2" "$1" "$t" "$pt" "" "$d" "$pd" ""
}

print_banner() {
    if [ -t 1 ]; then
        clear 2>/dev/null || true
    fi
    detect_sys_meta
    local line
    line=$(printf '─%.0s' $(seq 1 62))
    echo ""
    echo -e "  ${EMERALD}${BOLD}╭${line}╮${NC}"
    banner_row "${WHITE}${BOLD}" "◆ RYZENNC CONTROL PANEL"
    banner_row "${CYAN}" "  Next-Gen Minecraft Server Manager"
    banner_row "${AMBER}" "  v3.0.0 · Production Ready · Cloudflare Ready"
    echo -e "  ${EMERALD}${BOLD}├${line}┤${NC}"
    echo -e "  ${EMERALD}${BOLD}│${NC} ${GRAY}System :${NC} ${WHITE}${OS_TYPE} (${SYS_ARCH})${NC}"
    echo -e "  ${EMERALD}${BOLD}│${NC} ${GRAY}Memory :${NC} ${WHITE}${SYS_RAM}${NC}   ${GRAY}IP:${NC} ${CYAN}${SYS_IP}${NC}   ${GRAY}Status:${NC} ${SYS_STATE}"
    echo -e "  ${EMERALD}${BOLD}╰${line}╯${NC}"
    echo ""
}

log_info() { echo -e "  ${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "  ${GREEN}✔${NC} $1"; }
log_warning() { echo -e "  ${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "  ${RED}✖${NC} $1"; }

run_pm2() {
    if command -v pm2 &> /dev/null; then
        pm2 "$@"
    elif [ -x "/usr/local/bin/pm2" ]; then
        /usr/local/bin/pm2 "$@"
    elif [ -x "./node_modules/.bin/pm2" ]; then
        ./node_modules/.bin/pm2 "$@"
    else
        return 1
    fi
}

get_docker_cmd() {
    if docker info > /dev/null 2>&1; then
        echo "docker"
    elif command -v sudo &> /dev/null && sudo docker info > /dev/null 2>&1; then
        echo "sudo docker"
    else
        echo "docker"
    fi
}

get_compose_cmd() {
    local d_cmd=$(get_docker_cmd)
    if $d_cmd compose version > /dev/null 2>&1; then
        echo "$d_cmd compose"
    elif command -v docker-compose > /dev/null 2>&1; then
        echo "docker-compose"
    elif command -v sudo &> /dev/null && sudo docker-compose version > /dev/null 2>&1; then
        echo "sudo docker-compose"
    else
        echo "$d_cmd compose"
    fi
}

run_root() {
    if [ "$EUID" -eq 0 ]; then
        "$@"
    elif command -v sudo > /dev/null 2>&1; then
        sudo "$@"
    else
        "$@"
    fi
}

execute_step() {
    local msg="$1"
    shift
    local step_id="ryzennc_step_$RANDOM"
    local log_file="/tmp/${step_id}.log"
    rm -f "$log_file"
    
    local is_optional=0
    case "$msg" in
        *"Java"*) is_optional=1 ;;
    esac

    printf "  ${GRAY}│${NC}  ${CYAN}⚙${NC}  %-44s " "$msg"
    
    # Run command in background and capture all stdout and stderr
    "$@" > "$log_file" 2>&1 &
    local pid=$!
    
    if [ -t 1 ]; then
        local spinstr='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
        while kill -0 $pid 2>/dev/null; do
            local temp=${spinstr#?}
            printf "${CYAN}[%c]${NC}" "$spinstr"
            local spinstr=$temp${spinstr%"$temp"}
            sleep 0.1
            printf "\b\b\b"
        done
    else
        while kill -0 $pid 2>/dev/null; do
            sleep 1
        done
    fi
    
    local status=0
    wait $pid 2>/dev/null || status=$?
    
    if [ $status -eq 0 ]; then
        printf "\r  ${GRAY}│${NC}  ${GREEN}✔${NC}  %-44s ${GREEN}[DONE]${NC}\n" "$msg"
    elif [ $is_optional -eq 1 ]; then
        printf "\r  ${GRAY}│${NC}  ${YELLOW}ℹ${NC}  %-44s ${YELLOW}[DOCKER JVM]${NC}\n" "$msg"
        return 0
    else
        printf "\r  ${GRAY}│${NC}  ${RED}✖${NC}  %-44s ${RED}[FAILED]${NC}\n" "$msg"
        echo -e "\n  ${RED}┌── STEP FAILED: $msg ──────────────────────────────┐${NC}"
        echo -e "  ${RED}│  Exit Code: $status${NC}"
        echo -e "  ${RED}│  Log details:${NC}"
        if [ -s "$log_file" ]; then
            tail -n 25 "$log_file" | sed 's/^/  │  /'
        else
            echo "  │  No error logs produced."
        fi
        echo -e "  ${RED}└───────────────────────────────────────────────────┘${NC}\n"
        exit 1
    fi
    return $status
}

check_system_deps() {
    detect_os
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1
    export UCF_FORCE_CONFFOLD=1

    local MISSING_DEPS=""
    for cmd in curl git tar jq; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            MISSING_DEPS="$MISSING_DEPS $cmd"
        fi
    done

    if [ -n "$MISSING_DEPS" ]; then
        if command -v apt-get > /dev/null 2>&1; then
            local APT_OPTS="-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o Acquire::http::Timeout=10 -o Acquire::ftp::Timeout=10"
            if [ "$EUID" -eq 0 ]; then
                apt-get update $APT_OPTS > /dev/null 2>&1 || true
                apt-get install $APT_OPTS $MISSING_DEPS build-essential ca-certificates xz-utils > /dev/null 2>&1 || true
            elif command -v sudo > /dev/null 2>&1; then
                sudo apt-get update $APT_OPTS > /dev/null 2>&1 || true
                sudo apt-get install $APT_OPTS $MISSING_DEPS build-essential ca-certificates xz-utils > /dev/null 2>&1 || true
            fi
        elif command -v yum > /dev/null 2>&1; then
            if [ "$EUID" -eq 0 ]; then
                yum update -y -q > /dev/null 2>&1 || true
                yum install -y $MISSING_DEPS make gcc-c++ ca-certificates xz > /dev/null 2>&1 || true
            elif command -v sudo > /dev/null 2>&1; then
                sudo yum update -y -q > /dev/null 2>&1 || true
                sudo yum install -y $MISSING_DEPS make gcc-c++ ca-certificates xz > /dev/null 2>&1 || true
            fi
        elif command -v dnf > /dev/null 2>&1; then
            if [ "$EUID" -eq 0 ]; then
                dnf install -y $MISSING_DEPS make gcc-c++ ca-certificates xz > /dev/null 2>&1 || true
            elif command -v sudo > /dev/null 2>&1; then
                sudo dnf install -y $MISSING_DEPS make gcc-c++ ca-certificates xz > /dev/null 2>&1 || true
            fi
        fi
    fi

    # Ensure swap if memory is low (< 2GB) and swap is low (< 512MB) to prevent OOM kills during build/run
    local total_mem=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "2048")
    local total_swap=$(free -m 2>/dev/null | awk '/^Swap:/{print $2}' || echo "0")
    if [ -n "$total_mem" ] && [ "$total_mem" -lt 2000 ] && [ "$total_swap" -lt 512 ]; then
        if command -v swapon &> /dev/null && command -v sudo &> /dev/null; then
            if [ ! -f "/swapfile" ]; then
                if command -v fallocate &> /dev/null; then
                    sudo fallocate -l 2G /swapfile > /dev/null 2>&1 || sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 > /dev/null 2>&1 || true
                else
                    sudo dd if=/dev/zero of=/swapfile bs=1M count=2048 > /dev/null 2>&1 || true
                fi
                sudo chmod 600 /swapfile > /dev/null 2>&1 || true
                sudo mkswap /swapfile > /dev/null 2>&1 || true
                sudo swapon /swapfile > /dev/null 2>&1 || true
            else
                sudo swapon /swapfile > /dev/null 2>&1 || true
            fi
        fi
    fi

    for cmd in curl git tar; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Required system dependency '$cmd' is missing."
            return 1
        fi
    done
    return 0
}

install_docker() {
    if ! command -v docker &> /dev/null; then
        curl -fsSL https://get.docker.com | sh > /dev/null 2>&1 || true
        if command -v systemctl &> /dev/null; then
            sudo systemctl enable --now docker > /dev/null 2>&1 || true
        elif command -v service &> /dev/null; then
            sudo service docker start > /dev/null 2>&1 || true
        fi
    fi
    
    if ! command -v docker &> /dev/null; then
        echo "Docker could not be installed automatically. Please install Docker and retry."
        return 1
    fi
    
    # Check Docker daemon connectivity
    if ! docker info > /dev/null 2>&1; then
        if command -v systemctl &> /dev/null; then
            sudo systemctl start docker > /dev/null 2>&1 || true
        elif command -v service &> /dev/null; then
            sudo service docker start > /dev/null 2>&1 || true
        fi
        if ! docker info > /dev/null 2>&1; then
            if command -v sudo &> /dev/null && sudo docker info > /dev/null 2>&1; then
                sudo usermod -aG docker "$USER" 2>/dev/null || true
            else
                echo "Docker daemon is not running or current user lacks permission to access /var/run/docker.sock."
                return 1
            fi
        fi
    fi
    
    local d_cmd=$(get_docker_cmd)
    if ! $d_cmd compose version &> /dev/null && ! command -v docker-compose &> /dev/null; then
        sudo curl -L "https://github.com/docker/compose/releases/download/v2.24.5/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose > /dev/null 2>&1 || true
        sudo chmod +x /usr/local/bin/docker-compose > /dev/null 2>&1 || true
    fi
    
    local c_cmd=$(get_compose_cmd)
    if ! $c_cmd version &> /dev/null; then
        echo "Docker Compose is required but could not be installed."
        return 1
    fi
    return 0
}

install_node() {
    local NEED_NODE=0
    if ! command -v node &> /dev/null; then
        NEED_NODE=1
    else
        local NODE_MAJOR=$(node -v 2>/dev/null | tr -d 'v' | cut -d'.' -f1)
        if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 20 ]; then
            NEED_NODE=1
        fi
    fi

    if [ "$NEED_NODE" -eq 1 ]; then
        if command -v apt-get &> /dev/null; then
            curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - > /dev/null 2>&1 || true
            sudo apt-get install -y nodejs > /dev/null 2>&1 || true
        fi
        
        local CURRENT_MAJOR=0
        if command -v node &> /dev/null; then
            CURRENT_MAJOR=$(node -v 2>/dev/null | tr -d 'v' | cut -d'.' -f1)
        fi
        
        if [ "$CURRENT_MAJOR" -lt 20 ]; then
            local ARCH=$(uname -m)
            local NODE_ARCH="x64"
            case "$ARCH" in
                x86_64) NODE_ARCH="x64" ;;
                aarch64|arm64) NODE_ARCH="arm64" ;;
                armv7l) NODE_ARCH="armv7l" ;;
                *) NODE_ARCH="x64" ;;
            esac
            local NODE_DIST="node-v22.13.1-linux-${NODE_ARCH}"
            curl -fsSL "https://nodejs.org/dist/v22.13.1/${NODE_DIST}.tar.xz" -o /tmp/node22.tar.xz > /dev/null 2>&1 || true
            if [ -f "/tmp/node22.tar.xz" ]; then
                sudo tar -xJf /tmp/node22.tar.xz -C /usr/local --strip-components=1 > /dev/null 2>&1 || true
                rm -f /tmp/node22.tar.xz
            fi
        fi
    fi
    
    if ! command -v node &> /dev/null; then
        echo "Node.js (>=20) installation failed."
        return 1
    fi
    
    local VER=$(node -v 2>/dev/null | tr -d 'v' | cut -d'.' -f1)
    if [ "$VER" -lt 20 ]; then
        echo "Node.js version must be >= 20. Current: $(node -v)"
        return 1
    fi

    if ! command -v npm &> /dev/null; then
        echo "npm is not installed."
        return 1
    fi
    return 0
}

install_java() {
    trap 'return 0' TERM INT

    # 1. Quick check: Is Java already working in PATH?
    if command -v java > /dev/null 2>&1 && java -version > /dev/null 2>&1; then
        echo "Java runtime already active: $(java -version 2>&1 | head -n 1)"
        return 0
    fi

    # 2. Check common JVM installation directories
    for cand in /usr/lib/jvm/java-21-openjdk-*/bin/java \
                /usr/lib/jvm/java-17-openjdk-*/bin/java \
                /usr/lib/jvm/default-java/bin/java \
                /usr/lib/jvm/java-11-openjdk-*/bin/java \
                /usr/lib/jvm/*-openjdk*/bin/java \
                /opt/java/bin/java \
                /opt/ryzennc-java/bin/java \
                /usr/local/java/bin/java; do
        if [ -x "$cand" ]; then
            echo "Found existing JVM at: $cand"
            if [ "$EUID" -eq 0 ]; then
                ln -sf "$cand" /usr/local/bin/java 2>/dev/null || true
            elif command -v sudo > /dev/null 2>&1; then
                sudo ln -sf "$cand" /usr/local/bin/java 2>/dev/null || true
            fi
            export PATH="/usr/local/bin:$PATH"
            if command -v java > /dev/null 2>&1 && java -version > /dev/null 2>&1; then
                return 0
            fi
        fi
    done

    # 3. If Docker is available, host Java is not strictly required
    if command -v docker > /dev/null 2>&1; then
        echo "Docker detected. Minecraft servers will utilize containerized Java runtimes."
        return 0
    fi

    echo "Configuring OpenJDK runtime..."

    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    export NEEDRESTART_SUSPEND=1
    export UCF_FORCE_CONFFOLD=1

    if command -v apt-get > /dev/null 2>&1; then
        local APT_OPTS="-y -q -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold -o Acquire::http::Timeout=10 -o Acquire::ftp::Timeout=10"
        if [ "$EUID" -eq 0 ]; then
            apt-get install $APT_OPTS openjdk-21-jre-headless > /dev/null 2>&1 || \
            apt-get install $APT_OPTS openjdk-17-jre-headless > /dev/null 2>&1 || \
            apt-get install $APT_OPTS default-jre-headless > /dev/null 2>&1 || true
        elif command -v sudo > /dev/null 2>&1; then
            sudo apt-get install $APT_OPTS openjdk-21-jre-headless > /dev/null 2>&1 || \
            sudo apt-get install $APT_OPTS openjdk-17-jre-headless > /dev/null 2>&1 || \
            sudo apt-get install $APT_OPTS default-jre-headless > /dev/null 2>&1 || true
        fi
    elif command -v dnf > /dev/null 2>&1; then
        if [ "$EUID" -eq 0 ]; then
            dnf install -y java-21-openjdk-headless > /dev/null 2>&1 || dnf install -y java-17-openjdk-headless > /dev/null 2>&1 || true
        elif command -v sudo > /dev/null 2>&1; then
            sudo dnf install -y java-21-openjdk-headless > /dev/null 2>&1 || sudo dnf install -y java-17-openjdk-headless > /dev/null 2>&1 || true
        fi
    elif command -v yum > /dev/null 2>&1; then
        if [ "$EUID" -eq 0 ]; then
            yum install -y java-21-openjdk-headless > /dev/null 2>&1 || yum install -y java-17-openjdk-headless > /dev/null 2>&1 || true
        elif command -v sudo > /dev/null 2>&1; then
            sudo yum install -y java-21-openjdk-headless > /dev/null 2>&1 || sudo yum install -y java-17-openjdk-headless > /dev/null 2>&1 || true
        fi
    elif command -v apk > /dev/null 2>&1; then
        apk add --no-cache openjdk21-jre-headless > /dev/null 2>&1 || apk add --no-cache openjdk17-jre-headless > /dev/null 2>&1 || true
    elif command -v pacman > /dev/null 2>&1; then
        if [ "$EUID" -eq 0 ]; then
            pacman -Sy --noconfirm jre21-openjdk-headless > /dev/null 2>&1 || true
        elif command -v sudo > /dev/null 2>&1; then
            sudo pacman -Sy --noconfirm jre21-openjdk-headless > /dev/null 2>&1 || true
        fi
    fi

    # Check if package manager installed Java successfully
    if command -v java > /dev/null 2>&1 && java -version > /dev/null 2>&1; then
        return 0
    fi

    # Check discovered JVM directories again
    for cand in /usr/lib/jvm/java-21-openjdk-*/bin/java \
                /usr/lib/jvm/java-17-openjdk-*/bin/java \
                /usr/lib/jvm/default-java/bin/java \
                /usr/lib/jvm/*-openjdk*/bin/java; do
        if [ -x "$cand" ]; then
            if [ "$EUID" -eq 0 ]; then
                ln -sf "$cand" /usr/local/bin/java 2>/dev/null || true
            elif command -v sudo > /dev/null 2>&1; then
                sudo ln -sf "$cand" /usr/local/bin/java 2>/dev/null || true
            fi
            export PATH="/usr/local/bin:$PATH"
            if command -v java > /dev/null 2>&1; then
                return 0
            fi
        fi
    done

    # 4. Direct lightweight headless JRE fallback via Adoptium
    local ARCH=$(uname -m)
    local ADOPT_ARCH=""
    case "$ARCH" in
        x86_64) ADOPT_ARCH="x64" ;;
        aarch64|arm64) ADOPT_ARCH="aarch64" ;;
        *) ADOPT_ARCH="" ;;
    esac

    if [ -n "$ADOPT_ARCH" ] && command -v curl > /dev/null 2>&1; then
        echo "Attempting fast binary runtime fetch..."
        local JRE_URL="https://api.adoptium.net/v3/binary/latest/21/ga/linux/${ADOPT_ARCH}/jre/hotspot/normal/eclipse"
        curl -fsSL --connect-timeout 8 --max-time 45 "$JRE_URL" -o /tmp/ryzennc_jre.tar.gz > /dev/null 2>&1 || true
        if [ -f "/tmp/ryzennc_jre.tar.gz" ] && [ -s "/tmp/ryzennc_jre.tar.gz" ]; then
            if [ "$EUID" -eq 0 ]; then
                mkdir -p /opt/ryzennc-java
                tar -xzf /tmp/ryzennc_jre.tar.gz -C /opt/ryzennc-java --strip-components=1 > /dev/null 2>&1 || true
                if [ -x "/opt/ryzennc-java/bin/java" ]; then
                    ln -sf /opt/ryzennc-java/bin/java /usr/local/bin/java 2>/dev/null || true
                fi
            elif command -v sudo > /dev/null 2>&1; then
                sudo mkdir -p /opt/ryzennc-java
                sudo tar -xzf /tmp/ryzennc_jre.tar.gz -C /opt/ryzennc-java --strip-components=1 > /dev/null 2>&1 || true
                if [ -x "/opt/ryzennc-java/bin/java" ]; then
                    sudo ln -sf /opt/ryzennc-java/bin/java /usr/local/bin/java 2>/dev/null || true
                fi
            fi
            rm -f /tmp/ryzennc_jre.tar.gz 2>/dev/null || true
            export PATH="/usr/local/bin:$PATH"
            if command -v java > /dev/null 2>&1; then
                echo "Java OpenJDK runtime installed successfully."
                return 0
            fi
        fi
        rm -f /tmp/ryzennc_jre.tar.gz 2>/dev/null || true
    fi

    echo "Notice: Host Java setup completed with container fallback."
    echo "Note: Docker-managed Minecraft servers will run using containerized Java."
    return 0
}

setup_docker_env() {
    install_docker
    cat << 'EOF2' > Dockerfile
FROM node:22-alpine
RUN apk add --no-cache docker-cli git make g++ python3 curl
WORKDIR /app
COPY package*.json ./
RUN npm install --no-audit --no-fund --legacy-peer-deps
COPY . .
RUN if [ ! -f "dist/server.cjs" ] || [ ! -f "dist/index.html" ]; then NODE_OPTIONS="--max-old-space-size=2048" npm run build; fi
EXPOSE 6767 6868
CMD ["npm", "start"]
EOF2
    
    if [ ! -f "docker-compose.yml" ]; then
        cat << 'EOF2' > docker-compose.yml
version: '3.8'
services:
  ryzennc-main:
    build: .
    container_name: ryzennc-main
    restart: unless-stopped
    ports:
      - "6767:6767"
      - "6868:6868"
    environment:
      - NODE_ENV=production
      - PORT=6767
      - RYZENNC_HOST_DATA_PATH=${PWD}/.data
      - RYZENNC_OWNER_USER=${RYZENNC_OWNER_USER:-}
      - RYZENNC_OWNER_PASS=${RYZENNC_OWNER_PASS:-}
    volumes:
      - ./.data:/app/.data
      - ./backups:/app/backups
      - /var/run/docker.sock:/var/run/docker.sock

  ryzennc-admin:
    build: .
    container_name: ryzennc-admin
    restart: unless-stopped
    command: npm run dev
    ports:
      - "3000:3000"
      - "6869:6869"
    environment:
      - NODE_ENV=development
      - PORT=3000
      - RYZENNC_HOST_DATA_PATH=${PWD}/.data
      - RYZENNC_OWNER_USER=${RYZENNC_OWNER_USER:-}
      - RYZENNC_OWNER_PASS=${RYZENNC_OWNER_PASS:-}
    volumes:
      - ./.data:/app/.data
      - ./backups:/app/backups
      - /var/run/docker.sock:/var/run/docker.sock
EOF2
    fi
}

setup_node_env() {
    local RUNTIME_PREF=$1
    install_node

    if ! command -v pm2 &> /dev/null && [ ! -x "/usr/local/bin/pm2" ] && [ ! -x "./node_modules/.bin/pm2" ]; then
        if [ "$EUID" -eq 0 ]; then
            npm install -g pm2 --no-audit --no-fund > /dev/null 2>&1 || npm install --save-dev pm2 --no-audit --no-fund > /dev/null 2>&1 || true
        elif command -v sudo &> /dev/null; then
            sudo npm install -g pm2 --no-audit --no-fund > /dev/null 2>&1 || npm install --save-dev pm2 --no-audit --no-fund > /dev/null 2>&1 || true
        else
            npm install -g pm2 --no-audit --no-fund > /dev/null 2>&1 || npm install --save-dev pm2 --no-audit --no-fund > /dev/null 2>&1 || true
        fi
    fi
    
    local DEFAULT_RT="docker"
    local ENABLE_DOCKER="true"
    
    if [ "$RUNTIME_PREF" = "local" ]; then
        DEFAULT_RT="local"
        ENABLE_DOCKER="false"
    else
        # Ensure Docker is ready on host for Minecraft server containers
        if ! command -v docker &> /dev/null; then
            echo "Installing Docker for Minecraft server containers..."
            install_docker 2>/dev/null || true
        fi
        if command -v systemctl &> /dev/null; then
            systemctl enable --now docker 2>/dev/null || sudo systemctl enable --now docker 2>/dev/null || true
        elif command -v service &> /dev/null; then
            service docker start 2>/dev/null || sudo service docker start 2>/dev/null || true
        fi
        if [ -S "/var/run/docker.sock" ]; then
            chmod 666 /var/run/docker.sock 2>/dev/null || sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
        fi
    fi
    
    cat << EOF2 > ecosystem.config.cjs
module.exports = {
  apps: [
    {
      name: "ryzennc-main",
      script: "npm",
      args: "start",
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: "1G",
      env: {
        NODE_ENV: "production",
        PORT: 6767,
        DEFAULT_RUNTIME: "${DEFAULT_RT}",
        ENABLE_DOCKER: "${ENABLE_DOCKER}",
        DOCKER_SOCKET_PATH: "/var/run/docker.sock"
      }
    },
    {
      name: "ryzennc-admin",
      script: "npm",
      args: "run dev",
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: "2G",
      env: {
        NODE_ENV: "development",
        PORT: 3000,
        DEFAULT_RUNTIME: "${DEFAULT_RT}",
        ENABLE_DOCKER: "${ENABLE_DOCKER}",
        DOCKER_SOCKET_PATH: "/var/run/docker.sock"
      }
    }
  ]
};
EOF2
}

install_dependencies() {
    if [ ! -f "package.json" ]; then
        echo "Error: package.json not found in $(pwd)."
        return 1
    fi
    if [ -d "node_modules" ] && \
       [ -d "node_modules/express" ] && \
       [ -d "node_modules/react" ] && \
       [ -d "node_modules/vite" ] && \
       [ -x "node_modules/.bin/vite" ] && \
       [ -x "node_modules/.bin/esbuild" ] && \
       [ -x "node_modules/.bin/tsx" ]; then
        return 0
    fi
    echo "Installing panel dependencies..."
    npm install --no-audit --no-fund --legacy-peer-deps 2>&1 || npm install --no-audit --no-fund --legacy-peer-deps --force 2>&1
    
    if [ ! -d "node_modules/express" ] || [ ! -x "node_modules/.bin/vite" ]; then
        echo "Failed to install critical npm dependencies."
        return 1
    fi
    return 0
}

setup_owner() {
    npm run createuser
}

setup_owner_docker() {
    local TARGET=$1
    if [ -n "$RYZENNC_OWNER_USER" ] && [ -n "$RYZENNC_OWNER_PASS" ]; then
        local DOCKER_CLI=$(get_docker_cmd)
        sleep 2
        $DOCKER_CLI exec -e RYZENNC_OWNER_USER="$RYZENNC_OWNER_USER" -e RYZENNC_OWNER_PASS="$RYZENNC_OWNER_PASS" "$TARGET" npm run createuser 2>&1 || {
            if command -v node &> /dev/null && [ -f "scripts/createuser.ts" ] && [ -d "node_modules" ]; then
                npm run createuser 2>&1 || true
            fi
        }
    fi
}

build_application() {
    echo "Building application bundle..."
    rm -rf dist
    export NODE_OPTIONS="--max-old-space-size=2048"
    npm run build 2>&1
    local status=$?
    if [ $status -ne 0 ] || [ ! -f "dist/server.cjs" ] || [ ! -f "dist/index.html" ]; then
        echo "Build failed: dist/server.cjs or dist/index.html is missing."
        return 1
    fi
    return 0
}

start_panel_docker() {
    local TARGET=$1
    local DOCKER_CLI=$(get_docker_cmd)
    local COMPOSE_CLI=$(get_compose_cmd)

    export PWD=$(pwd)

    # Free up port from PM2 if it was previously running under local Node.js
    if command -v pm2 &> /dev/null || [ -f "node_modules/.bin/pm2" ]; then
        run_pm2 delete "$TARGET" > /dev/null 2>&1 || true
        if [ "$TARGET" = "ryzennc-main" ]; then
            run_pm2 delete "ryzennc-panel" > /dev/null 2>&1 || true
        fi
    fi

    # Remove any existing container with the same name to prevent naming collision
    $DOCKER_CLI rm -f "$TARGET" > /dev/null 2>&1 || true

    # Pre-build on host if node/npm are present and dist is not yet built (saves container memory)
    if [ ! -f "dist/server.cjs" ] || [ ! -f "dist/index.html" ]; then
        if command -v npm &> /dev/null && [ -d "node_modules" ]; then
            NODE_OPTIONS="--max-old-space-size=2048" npm run build > /dev/null 2>&1 || true
        fi
    fi

    echo "Starting container $TARGET via $COMPOSE_CLI..."
    if ! $COMPOSE_CLI up -d --build "$TARGET"; then
        echo "Docker Compose command failed to build or start $TARGET."
        echo "--- Docker Compose Logs ---"
        $COMPOSE_CLI logs --tail 50 "$TARGET" 2>&1 || true
        return 1
    fi
    
    local container_status=""
    local check_attempts=0
    while [ $check_attempts -lt 15 ]; do
        sleep 2
        container_status=$($DOCKER_CLI inspect --format '{{.State.Status}}' "$TARGET" 2>/dev/null || echo "not_found")
        if [ "$container_status" = "running" ]; then
            break
        elif [ "$container_status" = "exited" ] || [ "$container_status" = "dead" ]; then
            echo "Docker container $TARGET failed to start. Status: $container_status"
            echo "--- Docker Logs for $TARGET ---"
            $DOCKER_CLI logs "$TARGET" --tail 50 2>&1 || true
            return 1
        fi
        check_attempts=$((check_attempts + 1))
    done

    if [ "$container_status" != "running" ]; then
        echo "Docker container $TARGET is not in running state (Status: $container_status)."
        echo "--- Container Status ---"
        $DOCKER_CLI ps -a --filter "name=$TARGET" 2>&1 || true
        echo "--- Docker Logs for $TARGET ---"
        $DOCKER_CLI logs "$TARGET" --tail 50 2>&1 || true
        return 1
    fi
    return 0
}

start_panel_node() {
    local TARGET=$1
    if [ "$TARGET" = "ryzennc-main" ]; then
        run_pm2 delete ryzennc-panel 2>/dev/null || true
        # Clean up conflicting Docker container if previously running via Docker
        local DOCKER_CLI=$(get_docker_cmd)
        $DOCKER_CLI rm -f ryzennc-main ryzennc-panel 2>/dev/null || true
    fi
    # Ensure Docker daemon is running and socket accessible for Minecraft containers
    if command -v systemctl &> /dev/null; then
        systemctl enable --now docker 2>/dev/null || sudo systemctl enable --now docker 2>/dev/null || true
    elif command -v service &> /dev/null; then
        service docker start 2>/dev/null || sudo service docker start 2>/dev/null || true
    fi
    if [ -S "/var/run/docker.sock" ]; then
        chmod 666 /var/run/docker.sock 2>/dev/null || sudo chmod 666 /var/run/docker.sock 2>/dev/null || true
    fi
    run_pm2 delete "$TARGET" 2>/dev/null || true
    run_pm2 start ecosystem.config.cjs --only "$TARGET"
    run_pm2 save --force 2>/dev/null || true
}

health_check() {
    local PORT=$1
    local RUNTIME_TYPE=$2
    local TARGET=$3
    local ATTEMPTS=0
    local MAX_ATTEMPTS=30
    local DOCKER_CLI=$(get_docker_cmd)

    while [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
        if curl -s -f "http://127.0.0.1:${PORT}/api/health" >/dev/null 2>&1 || curl -s -f "http://127.0.0.1:${PORT}/" >/dev/null 2>&1; then
            return 0
        fi
        
        if [ "$RUNTIME_TYPE" = "docker" ]; then
            local cstatus=$($DOCKER_CLI inspect --format '{{.State.Status}}' "$TARGET" 2>/dev/null || echo "not_found")
            if [ "$cstatus" = "exited" ] || [ "$cstatus" = "dead" ] || [ "$cstatus" = "not_found" ]; then
                echo "Container $TARGET is not running during health check (Status: $cstatus)."
                echo "--- Logs for $TARGET ---"
                $DOCKER_CLI logs "$TARGET" --tail 50 2>&1 || true
                return 1
            fi
        else
            if run_pm2 list 2>/dev/null | grep "$TARGET" | grep -qE "errored|stopped"; then
                echo "PM2 process $TARGET crashed or stopped."
                echo "--- Logs for $TARGET ---"
                run_pm2 logs "$TARGET" --lines 40 --nostream 2>&1 || true
                return 1
            fi
        fi
        
        sleep 2
        ATTEMPTS=$((ATTEMPTS + 1))
    done

    echo "Health check timed out waiting for application on port $PORT."
    if [ "$RUNTIME_TYPE" = "docker" ]; then
        echo "--- Container Status ---"
        $DOCKER_CLI ps -a --filter "name=$TARGET" || true
        echo "--- Docker Logs ---"
        $DOCKER_CLI logs "$TARGET" --tail 50 2>&1 || true
    else
        echo "--- PM2 Status ---"
        run_pm2 list || true
        echo "--- PM2 Logs ---"
        run_pm2 logs "$TARGET" --lines 50 --nostream || true
    fi
    return 1
}

check_port() {
    local PORT=$1
    if command -v ss &> /dev/null; then
        if ss -lnt | grep -q ":$PORT "; then return 1; fi
    elif command -v netstat &> /dev/null; then
        if netstat -tuln | grep -q ":$PORT "; then return 1; fi
    elif command -v lsof &> /dev/null; then
        if lsof -i :$PORT -sTCP:LISTEN -t >/dev/null 2>&1; then return 1; fi
    fi
    return 0
}

show_status() {
    detect_sys_meta
    local MAIN_STATUS="${RED}● OFFLINE${NC}"
    local DEV_STATUS="${RED}● OFFLINE${NC}"
    local SFTP_STATUS="${RED}● OFFLINE${NC}"
    
    if check_port_active 6767 || (run_pm2 list 2>/dev/null | grep "ryzennc-main" | grep -q "online") || (command -v docker &> /dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^ryzennc-main$"); then
        MAIN_STATUS="${GREEN}● ONLINE${NC}"
    fi
    
    if check_port_active 3000 || (run_pm2 list 2>/dev/null | grep "ryzennc-admin" | grep -q "online") || (command -v docker &> /dev/null && docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^ryzennc-admin$"); then
        DEV_STATUS="${GREEN}● ONLINE${NC}"
    fi
    
    if [ "$MAIN_STATUS" = "${GREEN}● ONLINE${NC}" ] || [ "$DEV_STATUS" = "${GREEN}● ONLINE${NC}" ]; then
        SFTP_STATUS="${GREEN}● ONLINE${NC}"
    fi
    
    echo ""
    echo -e "  ${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════╗"
    echo -e "  ║                    RYZENNC PANEL LIVE STATUS                     ║"
    echo -e "  ╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ║                                                              ║"
    echo -e "  ║  • Main Panel       : ${MAIN_STATUS} ${CYAN}http://${SYS_IP}:6767${NC}"
    echo -e "  ║  • Developer Panel  : ${DEV_STATUS} ${CYAN}http://${SYS_IP}:3000${NC}"
    echo -e "  ║  • SFTP Service     : ${SFTP_STATUS} ${YELLOW}Port 2022${NC}"
    echo -e "  ║  • Host Memory      : ${WHITE}${SYS_RAM}${NC}"
    echo -e "  ║  • Host System      : ${WHITE}${OS_TYPE} (${SYS_ARCH})${NC}"
    echo -e "  ║                                                              ║"
    echo -e "  ${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

install_panel() {
    local TARGET=$1
    local PANEL_NAME="Main Panel"
    local PORT="6767"
    local SERVICE_NAME="ryzennc-main"
    
    if [ "$TARGET" = "dev" ]; then
        PANEL_NAME="Developer Panel"
        PORT="3000"
        SERVICE_NAME="ryzennc-admin"
    fi

    print_banner
    echo -e "  ${GRAY}┌──${NC} ${BOLD}SELECT RUNTIME ENVIRONMENT${NC} ${GRAY}─────────────────────────────────┐${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}  ${CYAN}${BOLD}[1]${NC}  ${WHITE}${BOLD}Node.js + PM2 (Recommended)${NC}                                ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}       • Panel runs natively via PM2 on host                     ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}       • Minecraft servers run in isolated Docker containers      ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}  ${CYAN}${BOLD}[2]${NC}  ${WHITE}${BOLD}Pure Local Node.js${NC}                                        ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}       • Panel and servers run directly on host                   ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}  ${YELLOW}${BOLD}[3]${NC}  ${WHITE}${BOLD}Back to Main Menu${NC}                                         ${GRAY}│${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}└───${NC}"
    echo ""
    
    local MODE_CHOICE=""
    if [ -n "$RUN_CHOICE" ]; then
        MODE_CHOICE="$RUN_CHOICE"
    elif [ ! -t 0 ]; then
        MODE_CHOICE="1"
    else
        echo -ne "  ${CYAN}╭──${NC} ${BOLD}Choose runtime mode [1-3]${NC}: "
        read -r MODE_CHOICE
    fi

    if [ "$MODE_CHOICE" = "3" ]; then
        return
    fi

    if [ "$MODE_CHOICE" != "1" ] && [ "$MODE_CHOICE" != "2" ]; then
        log_error "Invalid selection: '$MODE_CHOICE'"
        sleep 1
        return
    fi
    
    if [ "$TARGET" = "main" ]; then
        print_banner
        echo -e "  ${GRAY}┌──${NC} ${BOLD}CREATE OWNER ACCOUNT${NC} ${GRAY}───────────────────────────────────────┐${NC}"
        echo -e "  ${GRAY}│${NC}  Set login credentials for the primary administrator account: ${GRAY}│${NC}"
        echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
        
        local OWNER_USER=""
        local OWNER_PASS=""
        local OWNER_PASS2=""
        
        if [ -n "$RYZENNC_OWNER_USER" ] && [ -n "$RYZENNC_OWNER_PASS" ]; then
            OWNER_USER="$RYZENNC_OWNER_USER"
            OWNER_PASS="$RYZENNC_OWNER_PASS"
        elif [ ! -t 0 ]; then
            OWNER_USER="owner"
            OWNER_PASS="owner12345"
        else
            while true; do
                echo -ne "  ${CYAN}│${NC}  ${BOLD}Username${NC} (min 3 chars): "
                read -r OWNER_USER
                if [ ${#OWNER_USER} -ge 3 ]; then
                    break
                else
                    echo -e "  ${YELLOW}⚠ Username must be at least 3 characters. Try again.${NC}"
                fi
            done
            
            while true; do
                echo -ne "  ${CYAN}│${NC}  ${BOLD}Password${NC} (min 6 chars): "
                read -r -s OWNER_PASS
                echo ""
                echo -ne "  ${CYAN}│${NC}  ${BOLD}Confirm Password${NC}       : "
                read -r -s OWNER_PASS2
                echo ""
                if [ ${#OWNER_PASS} -lt 6 ]; then
                    echo -e "  ${YELLOW}⚠ Password must be at least 6 characters. Try again.${NC}"
                elif [ "$OWNER_PASS" = "$OWNER_PASS2" ] && [ -n "$OWNER_PASS" ]; then
                    break
                else
                    echo -e "  ${YELLOW}⚠ Passwords do not match or are empty. Try again.${NC}"
                fi
            done
        fi
        echo -e "  ${GRAY}└───${NC}"
        echo ""
        
        export RYZENNC_OWNER_USER="$OWNER_USER"
        export RYZENNC_OWNER_PASS="$OWNER_PASS"
    fi
    
    # Environment Setup
    mkdir -p .data backups
    if [ ! -f ".env" ]; then
        if [ -f ".env.example" ]; then
            cp .env.example .env
        else
            echo "PORT=6767" > .env
            echo "JWT_SECRET=$(head -c 32 /dev/urandom | base64 2>/dev/null || openssl rand -base64 32)" >> .env
        fi
    fi

    print_banner
    echo -e "  ${GRAY}┌──${NC} ${BOLD}INSTALLATION PROGRESS${NC} ${GRAY}───────────────────────────────────┐${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"

    execute_step "System Requirement Check" check_system_deps
    
    if [ "$MODE_CHOICE" = "1" ] || [ "$MODE_CHOICE" = "2" ]; then
        local RUNTIME_ARG="docker"
        if [ "$MODE_CHOICE" = "1" ]; then
            RUNTIME_ARG="docker"
            execute_step "Docker Engine Setup & Check" install_docker
            execute_step "Java Runtime Environment Check" install_java
            execute_step "Node.js & PM2 Environment Setup" setup_node_env "docker"
        else
            RUNTIME_ARG="local"
            execute_step "Java Runtime Environment" install_java
            execute_step "Node.js & PM2 Environment Setup" setup_node_env "local"
        fi
        execute_step "NPM Dependencies Installation" install_dependencies
        if [ "$TARGET" = "main" ]; then
            execute_step "Owner Account Provisioning" setup_owner
            execute_step "Application Production Build" build_application
            execute_step "PM2 Background Service Launch" start_panel_node ryzennc-main
            execute_step "Application Verification (Port 6767)" health_check 6767 pm2 ryzennc-main
        else
            execute_step "Application Production Build" build_application
            execute_step "PM2 Background Service Launch" start_panel_node ryzennc-admin
            execute_step "Application Verification (Port 3000)" health_check 3000 pm2 ryzennc-admin
        fi
    fi
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}└───${NC}"
    echo ""
    
    detect_sys_meta
    echo -e "  ${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════╗"
    echo -e "  ║  ✔  INSTALLATION COMPLETED & VERIFIED SUCCESSFULLY           ║"
    echo -e "  ╠══════════════════════════════════════════════════════════════╣${NC}"
    echo -e "  ║                                                              ║"
    if [ "$TARGET" = "main" ]; then
        echo -e "  ║  • Access URL    : ${CYAN}http://${SYS_IP}:6767${NC}                        "
        echo -e "  ║  • Username      : ${WHITE}${OWNER_USER}${NC}                                  "
        echo -e "  ║  • SFTP Port     : ${YELLOW}2022${NC} (Built-in Web & SFTP Server)         "
    else
        echo -e "  ║  • Access URL    : ${CYAN}http://${SYS_IP}:3000${NC} (Developer Panel)        "
    fi
    echo -e "  ║  • Process       : ${GREEN}Managed via PM2 (Auto-restarts enabled)${NC}      "
    echo -e "  ║                                                              ║"
    echo -e "  ║  ${BOLD}Helpful Commands:${NC}                                          ║"
    echo -e "  ║    pm2 status         - View running panel processes         ║"
    echo -e "  ║    pm2 logs $SERVICE_NAME   - Stream live console logs              ║"
    echo -e "  ║    bash update.sh     - Update panel anytime                 ║"
    echo -e "  ║                                                              ║"
    echo -e "  ${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

update_panel() {
    if [ ! -f "update.sh" ]; then
        log_error "update.sh not found."
        return
    fi
    bash update.sh
}

create_owner_user() {
    print_banner
    echo -e "  ${GRAY}┌──${NC} ${BOLD}SETUP OWNER ACCOUNT${NC} ${GRAY}─────────────────────────────────────────┐${NC}"
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    
    local OWNER_USER=""
    local OWNER_PASS=""
    local OWNER_PASS2=""
    
    while true; do
        echo -ne "  ${CYAN}│${NC}  ${BOLD}Username${NC} (min 3 chars): "
        read -r OWNER_USER
        if [ ${#OWNER_USER} -ge 3 ]; then
            break
        else
            echo -e "  ${YELLOW}⚠ Username must be at least 3 characters. Try again.${NC}"
        fi
    done
    
    while true; do
        echo -ne "  ${CYAN}│${NC}  ${BOLD}Password${NC} (min 6 chars): "
        read -r -s OWNER_PASS
        echo ""
        echo -ne "  ${CYAN}│${NC}  ${BOLD}Confirm Password${NC}       : "
        read -r -s OWNER_PASS2
        echo ""
        if [ ${#OWNER_PASS} -lt 6 ]; then
            echo -e "  ${YELLOW}⚠ Password must be at least 6 characters. Try again.${NC}"
        elif [ "$OWNER_PASS" = "$OWNER_PASS2" ] && [ -n "$OWNER_PASS" ]; then
            break
        else
            echo -e "  ${YELLOW}⚠ Passwords do not match or are empty. Try again.${NC}"
        fi
    done
    echo -e "  ${GRAY}│${NC}                                                               ${GRAY}│${NC}"
    echo -e "  ${GRAY}└───${NC}"
    echo ""
    
    export RYZENNC_OWNER_USER="$OWNER_USER"
    export RYZENNC_OWNER_PASS="$OWNER_PASS"
    execute_step "Setting up Owner Account" setup_owner
    log_success "Owner user setup completed successfully!"
}

uninstall_panel() {
    if [ -f "uninstall.sh" ]; then
        bash uninstall.sh "$@"
        exit 0
    elif [ -n "$PANEL_ROOT" ] && [ -f "$PANEL_ROOT/uninstall.sh" ]; then
        bash "$PANEL_ROOT/uninstall.sh" "$@"
        exit 0
    elif [ -f "/opt/ryzennc/uninstall.sh" ]; then
        bash "/opt/ryzennc/uninstall.sh" "$@"
        exit 0
    elif [ -f "$HOME/Ryzennc/uninstall.sh" ]; then
        bash "$HOME/Ryzennc/uninstall.sh" "$@"
        exit 0
    else
        log_error "uninstall.sh script not found."
        return
    fi
}

# =========================================================
# Cloudflare & Domain Setup
#  - Tunnel + domain (không cần mở port, không cần IP public)
#  - Nginx + DNS Cloudflare (A record, proxied)
#  - Quick Tunnel (link trycloudflare.com tạm thời)
# =========================================================
CF_API="https://api.cloudflare.com/client/v4"
CF_CONF_FILE="$(pwd)/.cloudflare.env"
CF_QUICK_PID_FILE="$(pwd)/.cloudflare_quick.pid"
CF_QUICK_LOG="/tmp/ryzennc_quicktunnel.log"
CF_PM2_NAME="ryzennc-cloudflared"

pause_menu() {
    if [ -t 0 ]; then read -r -p "  Nhấn Enter để tiếp tục..." _ || true; fi
}

cf_api() {
    # cf_api METHOD /path [json-body]
    local method="$1" path="$2" body="${3:-}"
    if [ -n "$body" ]; then
        curl -sS --max-time 30 -X "$method" "${CF_API}${path}" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" --data "$body" 2>/dev/null
    else
        curl -sS --max-time 30 -X "$method" "${CF_API}${path}" \
            -H "Authorization: Bearer ${CF_API_TOKEN}" \
            -H "Content-Type: application/json" 2>/dev/null
    fi
}

cf_ok()  { echo "$1" | jq -e '.success == true' > /dev/null 2>&1; }
cf_err() {
    local m
    m=$(echo "$1" | jq -r '[.errors[]?.message] | join("; ")' 2>/dev/null)
    echo "${m:-Không nhận được phản hồi hợp lệ từ Cloudflare (kiểm tra mạng / token)}"
}

cf_require_tools() {
    local missing=""
    for c in curl jq; do command -v "$c" > /dev/null 2>&1 || missing="$missing $c"; done
    if [ -n "$missing" ]; then
        log_info "Đang cài các gói còn thiếu:$missing"
        if command -v apt-get > /dev/null 2>&1; then
            run_root apt-get update -y -q > /dev/null 2>&1 || true
            run_root apt-get install -y -q $missing > /dev/null 2>&1 || true
        elif command -v dnf > /dev/null 2>&1; then
            run_root dnf install -y $missing > /dev/null 2>&1 || true
        elif command -v yum > /dev/null 2>&1; then
            run_root yum install -y $missing > /dev/null 2>&1 || true
        fi
        for c in $missing; do
            command -v "$c" > /dev/null 2>&1 || { log_error "Thiếu '$c', hãy cài thủ công rồi chạy lại."; return 1; }
        done
    fi
    return 0
}

install_cloudflared() {
    if command -v cloudflared > /dev/null 2>&1; then return 0; fi
    local arch
    case "$(uname -m)" in
        x86_64|amd64)  arch="amd64" ;;
        aarch64|arm64) arch="arm64" ;;
        armv7l|armhf)  arch="arm" ;;
        i386|i686)     arch="386" ;;
        *) log_error "Kiến trúc CPU '$(uname -m)' chưa được hỗ trợ."; return 1 ;;
    esac
    log_info "Đang tải cloudflared (${arch})..."
    local tmp="/tmp/cloudflared_dl_$RANDOM"
    if ! curl -fsSL --max-time 180 "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" -o "$tmp"; then
        rm -f "$tmp"; log_error "Không tải được cloudflared."; return 1
    fi
    run_root install -m 0755 "$tmp" /usr/local/bin/cloudflared
    rm -f "$tmp"
    command -v cloudflared > /dev/null 2>&1 || { log_error "Cài cloudflared thất bại."; return 1; }
    log_success "Đã cài cloudflared $(cloudflared --version 2>/dev/null | head -n1)"
}

cf_prompt_token() {
    if [ -z "${CF_API_TOKEN:-}" ]; then
        echo -e "  ${GRAY}Tạo API Token tại: ${CYAN}https://dash.cloudflare.com/profile/api-tokens${NC}"
        echo -e "  ${GRAY}Quyền cần có:${NC}"
        echo -e "  ${GRAY}  • Account → Cloudflare Tunnel → Edit   (chỉ cần cho chế độ Tunnel)${NC}"
        echo -e "  ${GRAY}  • Zone → DNS → Edit${NC}"
        echo -e "  ${GRAY}  • Zone → Zone → Read${NC}"
        echo ""
        echo -ne "  ${CYAN}▶${NC} ${BOLD}Cloudflare API Token${NC} (ẩn khi nhập): "
        read -r -s CF_API_TOKEN
        echo ""
    fi
    if [ -z "${CF_API_TOKEN:-}" ]; then
        log_error "Token không được để trống."
        return 1
    fi
    return 0
}

cf_prompt_host_port() {
    CF_HOSTNAME=""
    CF_PORT=""
    while true; do
        echo -ne "  ${CYAN}▶${NC} ${BOLD}Tên miền / subdomain${NC} (vd: panel.example.com): "
        read -r CF_HOSTNAME || return 1
        CF_HOSTNAME=$(echo "$CF_HOSTNAME" | tr 'A-Z' 'a-z' | sed -E 's#^https?://##; s#/.*$##; s#^[[:space:]]+|[[:space:]]+$##g')
        if [[ "$CF_HOSTNAME" =~ ^([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z]{2,}$ ]]; then
            break
        fi
        log_warning "Tên miền không hợp lệ, thử lại (hoặc Ctrl+C để thoát)."
    done
    echo -ne "  ${CYAN}▶${NC} ${BOLD}Port của panel${NC} [6767]: "
    read -r CF_PORT || return 1
    CF_PORT="${CF_PORT:-6767}"
    if ! [[ "$CF_PORT" =~ ^[0-9]+$ ]] || [ "$CF_PORT" -lt 1 ] || [ "$CF_PORT" -gt 65535 ]; then
        log_error "Port không hợp lệ: $CF_PORT"
        return 1
    fi
    return 0
}

# Tìm zone chứa hostname (thử bỏ dần subdomain). Gán CF_ZONE_ID / CF_ZONE_NAME / CF_ACCOUNT_ID
cf_find_zone() {
    local candidate="$1" res
    CF_ZONE_ID=""; CF_ZONE_NAME=""; CF_ACCOUNT_ID=""
    while [[ "$candidate" == *.* ]]; do
        res=$(cf_api GET "/zones?name=${candidate}&per_page=1")
        if ! cf_ok "$res"; then
            log_error "Cloudflare API: $(cf_err "$res")"
            return 1
        fi
        if [ "$(echo "$res" | jq '.result | length')" -gt 0 ]; then
            CF_ZONE_ID=$(echo "$res" | jq -r '.result[0].id')
            CF_ZONE_NAME=$(echo "$res" | jq -r '.result[0].name')
            CF_ACCOUNT_ID=$(echo "$res" | jq -r '.result[0].account.id')
            return 0
        fi
        candidate="${candidate#*.}"
    done
    log_error "Không tìm thấy domain này trong tài khoản Cloudflare của token. Hãy thêm domain vào Cloudflare trước."
    return 1
}

# Tạo mới hoặc cập nhật DNS record. cf_upsert_dns TYPE NAME CONTENT
cf_upsert_dns() {
    local type="$1" name="$2" content="$3" res rec_id old_type old_content body
    res=$(cf_api GET "/zones/${CF_ZONE_ID}/dns_records?name=${name}")
    if ! cf_ok "$res"; then log_error "Đọc DNS thất bại: $(cf_err "$res")"; return 1; fi
    rec_id=$(echo "$res" | jq -r '.result[0].id // empty')
    body=$(jq -nc --arg t "$type" --arg n "$name" --arg c "$content" \
        '{type:$t,name:$n,content:$c,proxied:true,ttl:1,comment:"managed by ryzennc installer"}')
    if [ -n "$rec_id" ]; then
        old_type=$(echo "$res" | jq -r '.result[0].type')
        old_content=$(echo "$res" | jq -r '.result[0].content')
        log_warning "Đã có record ${old_type} ${name} → ${old_content}"
        echo -ne "  ${CYAN}▶${NC} Ghi đè record này? [y/N]: "
        local ans; read -r ans || return 1
        case "$ans" in y|Y|yes|YES) ;; *) log_info "Giữ nguyên record cũ, bỏ qua bước DNS."; return 2 ;; esac
        res=$(cf_api PUT "/zones/${CF_ZONE_ID}/dns_records/${rec_id}" "$body")
    else
        res=$(cf_api POST "/zones/${CF_ZONE_ID}/dns_records" "$body")
    fi
    if ! cf_ok "$res"; then log_error "Ghi DNS thất bại: $(cf_err "$res")"; return 1; fi
    log_success "DNS: ${type} ${name} → ${content} (Proxied)"
}

cf_has_systemd() { command -v systemctl > /dev/null 2>&1 && [ -d /run/systemd/system ]; }

cf_save_conf() {
    {
        echo "CF_MODE=\"$1\""
        echo "CF_HOSTNAME=\"$CF_HOSTNAME\""
        echo "CF_PORT=\"$CF_PORT\""
        echo "CF_ZONE_ID=\"$CF_ZONE_ID\""
        echo "CF_ACCOUNT_ID=\"${CF_ACCOUNT_ID:-}\""
        echo "CF_TUNNEL_ID=\"${CF_TUNNEL_ID:-}\""
        echo "CF_RUN_MODE=\"${CF_RUN_MODE:-}\""
    } > "$CF_CONF_FILE"
    chmod 600 "$CF_CONF_FILE" 2>/dev/null || true
}

cf_wait_https() {
    local host="$1" code="" i
    printf "  ${GRAY}│${NC}  Đang kiểm tra https://%s " "$host"
    for i in 1 2 3 4 5 6 7 8; do
        code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 6 "https://${host}" 2>/dev/null)
        case "$code" in 2*|3*|401|403) echo -e "${GREEN}[HTTP $code]${NC}"; return 0 ;; esac
        printf "."
        sleep 3
    done
    echo -e " ${YELLOW}[chưa phản hồi]${NC}"
    log_warning "DNS/tunnel có thể cần thêm 1-2 phút. Hãy thử mở https://${host} sau."
    return 1
}

# ---------------------------------------------------------
# 1) Tunnel + domain
# ---------------------------------------------------------
cf_setup_tunnel_domain() {
    print_banner
    echo -e "  ${BOLD}CLOUDFLARE TUNNEL + DOMAIN${NC}  ${GRAY}(không cần mở port, có HTTPS tự động)${NC}\n"
    cf_require_tools || return 1
    cf_prompt_token || return 1
    cf_prompt_host_port || return 1

    log_info "Đang tìm zone cho ${CF_HOSTNAME}..."
    cf_find_zone "$CF_HOSTNAME" || return 1
    log_success "Zone: ${CF_ZONE_NAME}"

    install_cloudflared || return 1

    local tunnel_name="ryzennc-$(echo "$CF_HOSTNAME" | tr '.' '-')"
    local res body
    CF_TUNNEL_ID=""

    res=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel?name=${tunnel_name}&is_deleted=false")
    if ! cf_ok "$res"; then log_error "Đọc tunnel thất bại: $(cf_err "$res")"; return 1; fi
    CF_TUNNEL_ID=$(echo "$res" | jq -r '.result[0].id // empty')

    if [ -z "$CF_TUNNEL_ID" ]; then
        body=$(jq -nc --arg n "$tunnel_name" '{name:$n,config_src:"cloudflare"}')
        res=$(cf_api POST "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel" "$body")
        if ! cf_ok "$res"; then log_error "Tạo tunnel thất bại: $(cf_err "$res")"; return 1; fi
        CF_TUNNEL_ID=$(echo "$res" | jq -r '.result.id')
        log_success "Đã tạo tunnel: ${tunnel_name}"
    else
        log_info "Dùng lại tunnel có sẵn: ${tunnel_name}"
    fi

    res=$(cf_api GET "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/token")
    if ! cf_ok "$res"; then log_error "Lấy token tunnel thất bại: $(cf_err "$res")"; return 1; fi
    local tunnel_token
    tunnel_token=$(echo "$res" | jq -r '.result')

    body=$(jq -nc --arg h "$CF_HOSTNAME" --arg s "http://localhost:${CF_PORT}" \
        '{config:{ingress:[{hostname:$h,service:$s,originRequest:{}},{service:"http_status:404"}]}}')
    res=$(cf_api PUT "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}/configurations" "$body")
    if ! cf_ok "$res"; then log_error "Cấu hình ingress thất bại: $(cf_err "$res")"; return 1; fi
    log_success "Ingress: ${CF_HOSTNAME} → http://localhost:${CF_PORT}"

    cf_upsert_dns "CNAME" "$CF_HOSTNAME" "${CF_TUNNEL_ID}.cfargotunnel.com"
    [ $? -eq 1 ] && return 1

    # Chạy cloudflared như một service nền
    run_root cloudflared service uninstall > /dev/null 2>&1 || true
    run_pm2 delete "$CF_PM2_NAME" > /dev/null 2>&1 || true
    CF_RUN_MODE=""
    if cf_has_systemd && [ "$(id -u)" -eq 0 -o -n "$(command -v sudo)" ]; then
        if run_root cloudflared service install "$tunnel_token" > /tmp/ryzennc_cf_service.log 2>&1; then
            CF_RUN_MODE="systemd"
            log_success "Đã cài service systemd 'cloudflared' (tự khởi động cùng máy)"
        else
            log_warning "Không cài được service systemd, chuyển sang PM2/nohup."
        fi
    fi
    if [ -z "$CF_RUN_MODE" ]; then
        if run_pm2 start "$(command -v cloudflared)" --name "$CF_PM2_NAME" -- tunnel --no-autoupdate run --token "$tunnel_token" > /dev/null 2>&1; then
            run_pm2 save > /dev/null 2>&1 || true
            CF_RUN_MODE="pm2"
            log_success "Đã chạy cloudflared bằng PM2 (${CF_PM2_NAME})"
        else
            nohup cloudflared tunnel --no-autoupdate run --token "$tunnel_token" > /tmp/ryzennc_cloudflared.log 2>&1 &
            CF_RUN_MODE="nohup"
            log_warning "Chạy bằng nohup — sẽ không tự khởi động lại sau khi reboot."
        fi
    fi

    cf_save_conf "tunnel"
    unset CF_API_TOKEN tunnel_token
    echo ""
    cf_wait_https "$CF_HOSTNAME" || true
    echo -e "\n  ${GREEN}${BOLD}✔ Hoàn tất!${NC} Truy cập panel tại: ${CYAN}https://${CF_HOSTNAME}${NC}\n"
}

# ---------------------------------------------------------
# 2) Nginx reverse proxy + DNS A record
# ---------------------------------------------------------
cf_setup_nginx_domain() {
    print_banner
    echo -e "  ${BOLD}DOMAIN QUA NGINX + CLOUDFLARE DNS${NC}  ${GRAY}(cần VPS có IP public, mở port 80)${NC}\n"
    cf_require_tools || return 1
    cf_prompt_token || return 1
    cf_prompt_host_port || return 1

    log_info "Đang tìm zone cho ${CF_HOSTNAME}..."
    cf_find_zone "$CF_HOSTNAME" || return 1
    log_success "Zone: ${CF_ZONE_NAME}"

    local pub_ip
    pub_ip=$(curl -s --max-time 6 https://api.ipify.org 2>/dev/null)
    if ! [[ "$pub_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then pub_ip=$(get_sys_ip); fi
    echo -ne "  ${CYAN}▶${NC} ${BOLD}IP public của VPS${NC} [${pub_ip}]: "
    local in_ip; read -r in_ip || return 1
    pub_ip="${in_ip:-$pub_ip}"
    if ! [[ "$pub_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then log_error "IP không hợp lệ: $pub_ip"; return 1; fi

    if ! command -v nginx > /dev/null 2>&1; then
        log_info "Đang cài Nginx..."
        if command -v apt-get > /dev/null 2>&1; then
            run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q nginx > /dev/null 2>&1 || { run_root apt-get update -y -q > /dev/null 2>&1; run_root env DEBIAN_FRONTEND=noninteractive apt-get install -y -q nginx > /dev/null 2>&1; }
        elif command -v dnf > /dev/null 2>&1; then run_root dnf install -y nginx > /dev/null 2>&1
        elif command -v yum > /dev/null 2>&1; then run_root yum install -y nginx > /dev/null 2>&1
        fi
        command -v nginx > /dev/null 2>&1 || { log_error "Không cài được Nginx."; return 1; }
    fi

    local conf_dir="/etc/nginx/conf.d"
    local conf="${conf_dir}/ryzennc-${CF_HOSTNAME}.conf"
    local tmp_conf="/tmp/ryzennc_nginx_$RANDOM.conf"
    cat > "$tmp_conf" <<'NGX'
map $http_upgrade $ryzennc_conn_upgrade {
    default upgrade;
    ''      close;
}

server {
    listen 80;
    listen [::]:80;
    server_name __HOST__;

    client_max_body_size 0;

    location / {
        proxy_pass http://127.0.0.1:__PORT__;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $http_x_forwarded_proto;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection $ryzennc_conn_upgrade;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_request_buffering off;
    }
}
NGX
    sed -i "s/__HOST__/${CF_HOSTNAME}/g; s/__PORT__/${CF_PORT}/g" "$tmp_conf"
    run_root mkdir -p "$conf_dir"
    run_root cp "$tmp_conf" "$conf"
    rm -f "$tmp_conf"

    if ! run_root nginx -t > /tmp/ryzennc_nginx_test.log 2>&1; then
        log_error "Cấu hình Nginx lỗi:"; sed 's/^/    /' /tmp/ryzennc_nginx_test.log
        run_root rm -f "$conf"
        return 1
    fi
    if cf_has_systemd; then
        run_root systemctl enable nginx > /dev/null 2>&1 || true
        run_root systemctl restart nginx > /dev/null 2>&1 || run_root nginx -s reload > /dev/null 2>&1
    else
        run_root nginx -s reload > /dev/null 2>&1 || run_root nginx > /dev/null 2>&1
    fi
    log_success "Nginx: ${CF_HOSTNAME} → 127.0.0.1:${CF_PORT}"

    cf_upsert_dns "A" "$CF_HOSTNAME" "$pub_ip"
    [ $? -eq 1 ] && return 1

    echo -e "\n  ${YELLOW}⚠${NC} Cloudflare đang kết nối tới VPS qua HTTP (port 80)."
    echo -ne "  ${CYAN}▶${NC} Đặt SSL/TLS mode của zone ${BOLD}${CF_ZONE_NAME}${NC} = Flexible để HTTPS hoạt động? ${GRAY}(ảnh hưởng cả zone)${NC} [y/N]: "
    local ans; read -r ans || true
    case "$ans" in
        y|Y|yes|YES)
            local r; r=$(cf_api PATCH "/zones/${CF_ZONE_ID}/settings/ssl" '{"value":"flexible"}')
            if cf_ok "$r"; then log_success "SSL mode = Flexible"; else log_warning "Không đổi được SSL mode: $(cf_err "$r")"; fi
            ;;
        *) log_info "Giữ nguyên SSL mode. Nếu gặp lỗi redirect loop, hãy chỉnh SSL/TLS trong dashboard Cloudflare." ;;
    esac

    CF_TUNNEL_ID=""; CF_RUN_MODE="nginx"
    cf_save_conf "nginx"
    unset CF_API_TOKEN
    echo ""
    cf_wait_https "$CF_HOSTNAME" || true
    echo -e "\n  ${GREEN}${BOLD}✔ Hoàn tất!${NC} Truy cập panel tại: ${CYAN}https://${CF_HOSTNAME}${NC}"
    echo -e "  ${GRAY}Nhớ mở port 80 trên firewall / security group của VPS.${NC}\n"
}

# ---------------------------------------------------------
# 3) Quick Tunnel (link tạm thời, không cần tài khoản)
# ---------------------------------------------------------
cf_quick_tunnel() {
    print_banner
    echo -e "  ${BOLD}QUICK TUNNEL${NC}  ${GRAY}(link *.trycloudflare.com tạm thời, không cần domain)${NC}\n"
    cf_require_tools || return 1
    install_cloudflared || return 1

    echo -ne "  ${CYAN}▶${NC} ${BOLD}Port của panel${NC} [6767]: "
    local port; read -r port || return 1
    port="${port:-6767}"
    if ! [[ "$port" =~ ^[0-9]+$ ]]; then log_error "Port không hợp lệ."; return 1; fi

    if [ -f "$CF_QUICK_PID_FILE" ] && kill -0 "$(cat "$CF_QUICK_PID_FILE" 2>/dev/null)" 2>/dev/null; then
        kill "$(cat "$CF_QUICK_PID_FILE")" 2>/dev/null || true
        sleep 1
    fi
    : > "$CF_QUICK_LOG"
    nohup cloudflared tunnel --no-autoupdate --url "http://localhost:${port}" > "$CF_QUICK_LOG" 2>&1 &
    echo $! > "$CF_QUICK_PID_FILE"

    local url="" i
    printf "  ${GRAY}│${NC}  Đang tạo tunnel "
    for i in $(seq 1 30); do
        url=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$CF_QUICK_LOG" 2>/dev/null | head -n1)
        [ -n "$url" ] && break
        printf "."
        sleep 1
    done
    echo ""
    if [ -z "$url" ]; then
        log_error "Không lấy được URL. Log:"; tail -n 15 "$CF_QUICK_LOG" | sed 's/^/    /'
        return 1
    fi
    echo -e "\n  ${GREEN}${BOLD}✔ Quick Tunnel đang chạy:${NC} ${CYAN}${url}${NC}"
    echo -e "  ${GRAY}Link đổi mỗi lần chạy lại và dừng khi tắt máy. Dùng tuỳ chọn [1] để có domain cố định.${NC}\n"
}

# ---------------------------------------------------------
# 4) Trạng thái
# ---------------------------------------------------------
cf_status() {
    print_banner
    echo -e "  ${BOLD}TRẠNG THÁI CLOUDFLARE${NC}\n"
    if command -v cloudflared > /dev/null 2>&1; then
        log_success "cloudflared: $(cloudflared --version 2>/dev/null | head -n1)"
    else
        log_warning "cloudflared chưa được cài."
    fi
    if [ -f "$CF_CONF_FILE" ]; then
        # shellcheck disable=SC1090
        . "$CF_CONF_FILE"
        echo -e "  ${GRAY}Chế độ  :${NC} ${WHITE}${CF_MODE}${NC} (${CF_RUN_MODE})"
        echo -e "  ${GRAY}Domain  :${NC} ${CYAN}https://${CF_HOSTNAME}${NC}"
        echo -e "  ${GRAY}Port    :${NC} ${WHITE}${CF_PORT}${NC}"
        [ -n "$CF_TUNNEL_ID" ] && echo -e "  ${GRAY}Tunnel  :${NC} ${WHITE}${CF_TUNNEL_ID}${NC}"
        case "$CF_RUN_MODE" in
            systemd) systemctl is-active --quiet cloudflared 2>/dev/null && log_success "Service cloudflared: active" || log_error "Service cloudflared: không chạy" ;;
            pm2)     run_pm2 list 2>/dev/null | grep -q "${CF_PM2_NAME}.*online" && log_success "PM2 ${CF_PM2_NAME}: online" || log_error "PM2 ${CF_PM2_NAME}: không chạy" ;;
            nginx)   (command -v nginx > /dev/null 2>&1 && run_root nginx -t > /dev/null 2>&1) && log_success "Nginx: cấu hình OK" || log_error "Nginx: lỗi cấu hình" ;;
        esac
        local code; code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 8 "https://${CF_HOSTNAME}" 2>/dev/null)
        echo -e "  ${GRAY}HTTPS   :${NC} HTTP ${code:-N/A}"
    else
        log_info "Chưa cấu hình domain nào."
    fi
    if [ -f "$CF_QUICK_PID_FILE" ] && kill -0 "$(cat "$CF_QUICK_PID_FILE" 2>/dev/null)" 2>/dev/null; then
        local qurl; qurl=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$CF_QUICK_LOG" 2>/dev/null | head -n1)
        log_success "Quick Tunnel đang chạy: ${qurl:-không rõ URL}"
    fi
    echo ""
}

# ---------------------------------------------------------
# 5) Gỡ cấu hình
# ---------------------------------------------------------
cf_remove() {
    print_banner
    echo -e "  ${BOLD}GỠ CẤU HÌNH CLOUDFLARE${NC}\n"
    if [ -f "$CF_QUICK_PID_FILE" ]; then
        kill "$(cat "$CF_QUICK_PID_FILE" 2>/dev/null)" 2>/dev/null || true
        rm -f "$CF_QUICK_PID_FILE"
        log_success "Đã dừng Quick Tunnel"
    fi
    if [ ! -f "$CF_CONF_FILE" ]; then
        log_info "Không có cấu hình domain nào để gỡ."
        return 0
    fi
    # shellcheck disable=SC1090
    . "$CF_CONF_FILE"
    echo -e "  ${GRAY}Sẽ gỡ cấu hình cho:${NC} ${CYAN}${CF_HOSTNAME}${NC} (${CF_MODE})"
    echo -ne "  ${CYAN}▶${NC} Tiếp tục? [y/N]: "
    local ans; read -r ans || return 1
    case "$ans" in y|Y|yes|YES) ;; *) log_info "Đã huỷ."; return 0 ;; esac

    case "$CF_RUN_MODE" in
        systemd) run_root cloudflared service uninstall > /dev/null 2>&1 || true; log_success "Đã gỡ service cloudflared" ;;
        pm2)     run_pm2 delete "$CF_PM2_NAME" > /dev/null 2>&1 || true; run_pm2 save > /dev/null 2>&1 || true; log_success "Đã dừng PM2 ${CF_PM2_NAME}" ;;
        nohup)   pkill -f "cloudflared tunnel" 2>/dev/null || true; log_success "Đã dừng cloudflared" ;;
        nginx)
            run_root rm -f "/etc/nginx/conf.d/ryzennc-${CF_HOSTNAME}.conf"
            run_root nginx -s reload > /dev/null 2>&1 || true
            log_success "Đã xoá cấu hình Nginx"
            ;;
    esac

    echo -ne "  ${CYAN}▶${NC} Xoá luôn DNS record${CF_TUNNEL_ID:+ và tunnel} trên Cloudflare? (cần API Token) [y/N]: "
    read -r ans || true
    case "$ans" in
        y|Y|yes|YES)
            cf_require_tools || return 1
            cf_prompt_token || return 1
            local res rec_id
            res=$(cf_api GET "/zones/${CF_ZONE_ID}/dns_records?name=${CF_HOSTNAME}")
            rec_id=$(echo "$res" | jq -r '.result[0].id // empty' 2>/dev/null)
            if [ -n "$rec_id" ]; then
                res=$(cf_api DELETE "/zones/${CF_ZONE_ID}/dns_records/${rec_id}")
                cf_ok "$res" && log_success "Đã xoá DNS record" || log_warning "Xoá DNS thất bại: $(cf_err "$res")"
            fi
            if [ -n "$CF_TUNNEL_ID" ]; then
                sleep 3
                res=$(cf_api DELETE "/accounts/${CF_ACCOUNT_ID}/cfd_tunnel/${CF_TUNNEL_ID}")
                cf_ok "$res" && log_success "Đã xoá tunnel" || log_warning "Xoá tunnel thất bại: $(cf_err "$res")"
            fi
            unset CF_API_TOKEN
            ;;
    esac
    rm -f "$CF_CONF_FILE"
    log_success "Đã gỡ cấu hình Cloudflare local."
}

cloudflare_menu() {
    while true; do
        print_banner
        echo -e "  ${EMERALD}${BOLD}╭──${NC} ${BOLD}${WHITE}CLOUDFLARE & DOMAIN${NC} ${EMERALD}${BOLD}$(printf '─%.0s' $(seq 1 39))╮${NC}"
        menu_item 1 "$GREEN"  "Tunnel + Domain"       "Khuyên dùng · HTTPS tự động"
        menu_item 2 "$CYAN"   "Nginx + Cloudflare DNS" "VPS có IP public · port 80"
        menu_item 3 "$AMBER"  "Quick Tunnel"          "Link tạm, không cần domain"
        menu_item 4 "$BLUE"   "Xem trạng thái"        "Domain · tunnel · HTTPS"
        menu_item 5 "$RED"    "Gỡ cấu hình"           "Dừng tunnel / xoá Nginx / DNS"
        menu_item 0 "$GRAY"   "Quay lại"              "Về menu chính"
        echo -e "  ${EMERALD}${BOLD}╰$(printf '─%.0s' $(seq 1 62))╯${NC}\n"
        echo -ne "  ${EMERALD}▶${NC} ${BOLD}Chọn [0-5]${NC}: "
        local c
        if ! read -r c; then echo ""; return 0; fi
        case "$c" in
            1) cf_setup_tunnel_domain; pause_menu ;;
            2) cf_setup_nginx_domain;  pause_menu ;;
            3) cf_quick_tunnel;        pause_menu ;;
            4) cf_status;              pause_menu ;;
            5) cf_remove;              pause_menu ;;
            0|q|back) return 0 ;;
            *) log_error "Lựa chọn không hợp lệ: '$c'"; sleep 1.2 ;;
        esac
    done
}

# Direct invocation support: bash install.sh main / dev / cloudflare
if [ "$1" = "main" ]; then
    install_panel "main"
    exit 0
elif [ "$1" = "dev" ]; then
    install_panel "dev"
    exit 0
elif [ "$1" = "cloudflare" ] || [ "$1" = "cf" ]; then
    cloudflare_menu
    exit 0
fi

while true; do
    print_banner
    echo -e "  ${EMERALD}${BOLD}╭──${NC} ${BOLD}${WHITE}CONTROL MENU${NC} ${EMERALD}${BOLD}$(printf '─%.0s' $(seq 1 46))╮${NC}"
    menu_item 1 "$GREEN"  "Initialize Main Panel"   "Production Mode (:6767)"
    menu_item 2 "$CYAN"   "Initialize Dev Panel"    "Developer Mode (:3000)"
    menu_item 3 "$AMBER"  "Update & Auto-Repair"    "Self-Healing Requirement Check"
    menu_item 4 "$VIOLET" "Create / Reset Owner"    "Setup Administrator Account"
    menu_item 5 "$BLUE"   "System & Service Status" "Live Port, RAM & Health"
    menu_item 6 "$ORANGE" "Cloudflare & Domain"     "Tunnel · Domain · HTTPS"
    menu_item 7 "$RED"    "Uninstall RYZENNC Panel" "Clean Removal & Service Wipe"
    menu_item 0 "$GRAY"   "Exit Installer"          "Close this terminal menu"
    echo -e "  ${EMERALD}${BOLD}╰$(printf '─%.0s' $(seq 1 62))╯${NC}"
    echo ""
    echo -ne "  ${EMERALD}▶${NC} ${BOLD}Choose option [0-7]${NC}: "
    if ! read -r CHOICE; then
        echo ""
        break
    fi
    case "$CHOICE" in
        1)
            install_panel "main"
            if [ -t 0 ]; then read -p "  Press Enter to continue..." || true; fi
            ;;
        2)
            install_panel "dev"
            if [ -t 0 ]; then read -p "  Press Enter to continue..." || true; fi
            ;;
        3)
            update_panel
            if [ -t 0 ]; then read -p "  Press Enter to continue..." || true; fi
            ;;
        4)
            create_owner_user
            if [ -t 0 ]; then read -p "  Press Enter to continue..." || true; fi
            ;;
        5)
            show_status
            if [ -t 0 ]; then read -p "  Press Enter to return to main menu..." || true; fi
            ;;
        6)
            cloudflare_menu
            ;;
        7)
            uninstall_panel
            exit 0
            ;;
        0|exit|q)
            echo -e "\n  ${GREEN}✔ Goodbye! Have a great time managing your Minecraft servers.${NC}\n"
            exit 0
            ;;
        *)
            log_error "Invalid option selected: '$CHOICE'"
            sleep 1.2
            ;;
    esac
done
