#!/usr/bin/env bash
set -euo pipefail

# ========== 基本配置 ==========
WG_PORT=$((RANDOM % 55536 + 10000))  # 随机端口
WG_INTERFACE="wg0"
WG_CONFIG_PATH="/etc/wireguard"
OUTPUT_DIR="/opt/wireguard_configs"  # 配置文件输出目录
CLIENT_COUNT=10
SERVER_WG_IPV4="10.66.66.1"
SERVER_WG_IPV6="fd42:42:42::1"
WG_NET="10.66.66.0/24"
WG_NET_IPV6="fd42:42:42::/64"

# ========== 美化界面配置 ==========
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'
BOLD='\033[1m'

# 图标定义
ICON_SUCCESS="✅"
ICON_ERROR="❌"
ICON_WARNING="⚠️"
ICON_INFO="ℹ️"
ICON_ROCKET="🚀"
ICON_FIRE="🔥"
ICON_STAR="⭐"
ICON_SHIELD="🛡️"
ICON_NETWORK="🌐"
ICON_SPEED="⚡"
ICON_CONFIG="⚙️"
ICON_DOWNLOAD="📥"
ICON_UPLOAD="📤"
ICON_KEY="🔐"
ICON_SERVER="🖥️"
ICON_CLIENT="📱"

# ========== 日志函数 ==========
log() { echo -e "${GREEN}${BOLD}[INFO ]${NC} ${WHITE}$*${NC}"; }
err() { echo -e "${RED}${BOLD}[ERROR]${NC} ${WHITE}$*${NC}"; exit 1; }
warn() { echo -e "${YELLOW}${BOLD}[WARN ]${NC} ${WHITE}$*${NC}"; }
info() { echo -e "${BLUE}${BOLD}[INFO ]${NC} ${WHITE}$*${NC}"; }

# ========== 进度条函数 ==========
show_progress() {
    local current=$1
    local total=$2
    local desc="$3"
    local percent=$((current * 100 / total))
    local filled=$((percent / 2))
    local empty=$((50 - filled))
    
    printf "\r${CYAN}${BOLD}[${NC}"
    printf "%${filled}s" | tr ' ' '#'
    printf "%${empty}s" | tr ' ' '-'
    printf "${CYAN}${BOLD}] ${percent}%% ${WHITE}${desc}${NC}"
}

complete_progress() {
    local desc="$1"
    printf "\r${GREEN}${BOLD}[##################################################] 100%% ${ICON_SUCCESS} ${desc}${NC}\n"
}

# ========== transfer工具下载函数 ==========
download_transfer() {
    warn "transfer upload disabled; skip download"
    return 1
}

upload_configs() {
    warn "Config upload disabled; local config only"
    return 0
}

# ========== 炫酷横幅显示 ==========
show_banner() {
    clear
    echo -e "${PURPLE}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}${BOLD}║                                                                              ║${NC}"
    echo -e "${PURPLE}${BOLD}║              ${YELLOW}${ICON_ROCKET} WireGuard VPN 自动化部署脚本 ${ICON_ROCKET}${PURPLE}${BOLD}                              ║${NC}"
    echo -e "${PURPLE}${BOLD}║                                                                              ║${NC}"
    echo -e "${PURPLE}${BOLD}║              ${WHITE}${ICON_STAR} 高性能安全VPN服务器部署工具 ${ICON_STAR}${PURPLE}${BOLD}                                 ║${NC}"
    echo -e "${PURPLE}${BOLD}║            ${WHITE}${ICON_FIRE} 随机端口 + BBR优化 + 美化界面 ${ICON_FIRE}${PURPLE}${BOLD}                               ║${NC}"
    echo -e "${PURPLE}${BOLD}║                                                                              ║${NC}"
    echo -e "${PURPLE}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${BLUE}${BOLD}${ICON_INFO} 部署开始时间：${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${YELLOW}${BOLD}${ICON_NETWORK} 随机生成端口：${CYAN}$WG_PORT${NC}\n"
    sleep 2
}

# ========== 系统检测函数 ==========
detect_system() {
    echo -e "${CYAN}${BOLD}${ICON_CONFIG} 正在进行系统检测...${NC}\n"
    
    # 检测操作系统
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        OS_VERSION=$VERSION_ID
        OS_CODENAME=${VERSION_CODENAME:-"N/A"}
    else
        err "不支持的操作系统"
    fi
    
    # 检测架构
    ARCH=$(uname -m)
    KERNEL_VERSION=$(uname -r)
    
    # 检查Ubuntu版本
    if ! grep -q "Ubuntu" /etc/os-release; then
        err "此脚本仅支持Ubuntu系统"
    fi
    
    echo -e "${GREEN}${ICON_SUCCESS} 系统检测完成：${NC}"
    echo -e "  ${WHITE}操作系统：${YELLOW}$OS $OS_VERSION ($OS_CODENAME)${NC}"
    echo -e "  ${WHITE}系统架构：${YELLOW}$ARCH${NC}"
    echo -e "  ${WHITE}内核版本：${YELLOW}$KERNEL_VERSION${NC}\n"
}

# ========== IPv4地址检测函数 (移除网络连通性检查) ==========
detect_ipv4_forced() {
    echo -e "${CYAN}${BOLD}${ICON_NETWORK} 正在检测IPv4地址...${NC}"
    
    local ip=""
    
    # 方法1: 尝试外部检测 (如果可用)
    ip=$(timeout 5 curl -4 -s ipv4.icanhazip.com 2>/dev/null || echo "")
    
    # 方法2: 备用检测
    if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$(timeout 5 curl -4 -s ifconfig.me 2>/dev/null || echo "")
    fi
    
    # 方法3: 第三个备用源
    if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$(timeout 5 curl -4 -s api.ipify.org 2>/dev/null || echo "")
    fi
    
    # 方法4: 本地路由检测
    if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$(ip route get 8.8.8.8 2>/dev/null | grep -oP 'src \K\S+' 2>/dev/null || echo "")
    fi
    
    # 方法5: 从网络接口获取
    if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '^127\.' | head -1)
    fi
    
    # 方法6: 使用hostname命令
    if [[ -z "$ip" || ! "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        ip=$(hostname -I | awk '{print $1}' 2>/dev/null || echo "")
    fi
    
    if [[ -n "$ip" && "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        PUBLIC_IPV4="$ip"
        echo -e "${GREEN}${ICON_SUCCESS} 检测到IPv4地址：${YELLOW}$ip${NC}"
    else
        # 如果所有方法都失败，使用默认值
        PUBLIC_IPV4="127.0.0.1"
        warn "无法获取有效的IPv4地址，使用默认值: $PUBLIC_IPV4"
        warn "请手动配置客户端时修改服务器地址"
    fi
    echo ""
}

# ========== 网络接口检测 ==========
detect_interface() {
    echo -e "${CYAN}${BOLD}${ICON_NETWORK} 正在检测网络接口...${NC}"
    
    for i in {1..5}; do
        show_progress $i 5 "检测主网络接口"
        sleep 0.2
    done
    
    # 获取默认路由接口
    MAIN_INTERFACE=$(ip -4 route | grep default | head -1 | awk '{print $5}' 2>/dev/null || echo "")
    
    # 备用检测方法
    if [[ -z "$MAIN_INTERFACE" ]]; then
        MAIN_INTERFACE=$(ip route show default | head -1 | awk '/default/ {print $5}' 2>/dev/null || echo "")
    fi
    
    # 最后尝试
    if [[ -z "$MAIN_INTERFACE" ]]; then
        MAIN_INTERFACE=$(ip link show | grep -E "ens|eth|enp" | head -1 | awk -F: '{print $2}' | tr -d ' ' 2>/dev/null || echo "")
    fi
    
    # 如果仍然无法检测，使用第一个可用接口
    if [[ -z "$MAIN_INTERFACE" ]]; then
        MAIN_INTERFACE=$(ip link show | grep -E "^[0-9]+:" | grep -v "lo:" | head -1 | awk -F: '{print $2}' | tr -d ' ' 2>/dev/null || echo "")
    fi
    
    if [[ -z "$MAIN_INTERFACE" ]] || ! ip link show "$MAIN_INTERFACE" >/dev/null 2>&1; then
        echo -e "\n${RED}${ICON_ERROR} 无法检测到有效的网络接口${NC}"
        echo -e "${WHITE}可用网络接口：${NC}"
        ip link show | grep -E "^[0-9]" || true
        
        # 尝试使用常见接口名
        for interface in eth0 ens3 ens33 enp0s3 enp0s8; do
            if ip link show "$interface" >/dev/null 2>&1; then
                MAIN_INTERFACE="$interface"
                warn "使用接口: $interface"
                break
            fi
        done
        
        if [[ -z "$MAIN_INTERFACE" ]]; then
            err "网络接口检测失败"
        fi
    fi
    
    complete_progress "检测到主网络接口: $MAIN_INTERFACE"
    echo ""
}

# ========== 网络性能优化 ==========
optimize_network() {
    echo -e "${PURPLE}${BOLD}${ICON_SPEED} 正在进行网络性能优化...${NC}\n"
    
    for i in {1..10}; do
        show_progress $i 10 "配置网络优化参数"
        sleep 0.1
    done
    
    # WireGuard + 网络优化配置
    cat > /etc/sysctl.d/99-wireguard-optimization.conf << 'SYSCTL_EOF'
# WireGuard网络优化配置

# 启用IP转发
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# 网络性能优化
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 增加网络缓冲区大小
net.core.rmem_max = 134217728
net.core.wmem_max = 134217728
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728

# UDP优化（WireGuard基于UDP）
net.core.netdev_max_backlog = 10000
net.core.netdev_budget = 600
net.ipv4.udp_rmem_min = 8192
net.ipv4.udp_wmem_min = 8192

# 连接优化
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fastopen = 3

# 安全优化
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_syn_backlog = 2048
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_syn_retries = 5

# IPv6优化
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
SYSCTL_EOF

    # 应用配置
    sysctl --system >/dev/null 2>&1 || true
    
    # 加载BBR模块
    modprobe tcp_bbr >/dev/null 2>&1 || true
    echo "tcp_bbr" >> /etc/modules-load.d/modules.conf 2>/dev/null || true
    
    complete_progress "网络性能优化配置完成"
    echo ""
}

# ========== 安装依赖 ==========
install_dependencies() {
    echo -e "${CYAN}${BOLD}${ICON_DOWNLOAD} 安装系统依赖...${NC}"
    
    export DEBIAN_FRONTEND=noninteractive
    export NEEDRESTART_MODE=a
    
    for i in {1..8}; do
        show_progress $i 8 "更新软件包列表"
        sleep 0.1
    done
    
    # 更新软件包列表，增加重试机制
    local update_success=false
    for attempt in {1..3}; do
        if timeout 30 apt update -q >/dev/null 2>&1; then
            update_success=true
            break
        else
            warn "软件包列表更新失败，重试第 $attempt 次..."
            sleep 2
        fi
    done
    
    if [[ "$update_success" != "true" ]]; then
        warn "软件包列表更新失败，但继续安装..."
    fi
    complete_progress "软件包列表更新完成"
    
    for i in {1..12}; do
        show_progress $i 12 "安装必要软件包"
        sleep 0.1
    done
    
    # 分阶段安装软件包，避免依赖冲突
    log "安装基础工具..."
    if ! timeout 60 apt install -y software-properties-common curl wget gnupg lsb-release >/dev/null 2>&1; then
        warn "基础工具安装失败，尝试修复..."
        apt --fix-broken install -y >/dev/null 2>&1 || true
        dpkg --configure -a >/dev/null 2>&1 || true
        if ! timeout 60 apt install -y software-properties-common curl wget gnupg lsb-release >/dev/null 2>&1; then
            err "基础工具安装失败，请检查系统状态"
        fi
    fi
    
    log "安装WireGuard..."
    if ! timeout 60 apt install -y wireguard wireguard-tools >/dev/null 2>&1; then
        warn "WireGuard安装失败，尝试其他方法..."
        # 尝试从官方仓库安装
        add-apt-repository ppa:wireguard/wireguard -y >/dev/null 2>&1 || true
        timeout 30 apt update -q >/dev/null 2>&1 || true
        if ! timeout 60 apt install -y wireguard wireguard-tools >/dev/null 2>&1; then
            err "WireGuard安装失败，请检查系统版本"
        fi
    fi
    
    log "安装防火墙和辅助工具..."
    if ! timeout 60 apt install -y ufw iptables-persistent >/dev/null 2>&1; then
        warn "防火墙工具安装失败，使用基础iptables..."
        timeout 60 apt install -y iptables >/dev/null 2>&1 || true
    fi
    
    # QR码生成工具（可选）
    timeout 60 apt install -y qrencode >/dev/null 2>&1 || warn "QR码工具安装失败（可选功能）"
    
    complete_progress "系统依赖安装完成"
    
    # 验证关键组件
    if ! command -v wg >/dev/null; then
        err "WireGuard安装失败，wg命令不可用"
    fi
    
    log "WireGuard安装验证成功"
    echo ""
}

# ========== 防火墙配置 ==========
setup_firewall() {
    echo -e "${PURPLE}${BOLD}${ICON_SHIELD} 配置防火墙...${NC}"
    
    for i in {1..8}; do
        show_progress $i 8 "配置防火墙规则"
        sleep 0.1
    done
    
    # 检查UFW是否可用
    if command -v ufw >/dev/null 2>&1; then
        log "使用UFW配置防火墙..."
        
        # 重置防火墙规则
        ufw --force reset >/dev/null 2>&1 || true
        
        # 设置默认策略
        ufw default deny incoming >/dev/null 2>&1 || true
        ufw default allow outgoing >/dev/null 2>&1 || true
        
        # 开放SSH端口
        ufw allow 22/tcp >/dev/null 2>&1 || true
        
        # 开放WireGuard端口
        ufw allow $WG_PORT/udp >/dev/null 2>&1 || true
        
        # 启用防火墙
        if echo "y" | ufw enable >/dev/null 2>&1; then
            complete_progress "UFW防火墙配置完成"
        else
            warn "UFW启用失败，使用iptables替代"
            setup_iptables_backup
            complete_progress "iptables防火墙配置完成"
        fi
    else
        warn "UFW不可用，使用iptables配置防火墙"
        setup_iptables_backup
        complete_progress "iptables防火墙配置完成"
    fi
    
    echo -e "${GREEN}${ICON_SUCCESS} 已开放端口：SSH(22), WireGuard($WG_PORT)${NC}\n"
}

# ========== iptables备用配置 ==========
setup_iptables_backup() {
    # 清空现有规则
    iptables -F >/dev/null 2>&1 || true
    iptables -X >/dev/null 2>&1 || true
    iptables -t nat -F >/dev/null 2>&1 || true
    iptables -t nat -X >/dev/null 2>&1 || true
    
    # 设置基本规则
    iptables -P INPUT DROP
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT
    iptables -A INPUT -i lo -j ACCEPT
    iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
    iptables -A INPUT -p tcp --dport 22 -j ACCEPT
    iptables -A INPUT -p udp --dport $WG_PORT -j ACCEPT
    
    # 保存规则
    iptables-save > /etc/iptables/rules.v4 2>/dev/null || true
}

# ========== 生成密钥对 ==========
generate_keys() {
    echo -e "${CYAN}${BOLD}${ICON_KEY} 生成密钥对...${NC}"
    
    for i in {1..6}; do
        show_progress $i 6 "生成服务器密钥"
        sleep 0.2
    done
    
    # 创建目录
    mkdir -p $WG_CONFIG_PATH $OUTPUT_DIR
    chmod 700 $WG_CONFIG_PATH $OUTPUT_DIR
    
    # 生成服务器密钥
    SERVER_PRIVATE_KEY=$(wg genkey)
    SERVER_PUBLIC_KEY=$(echo "$SERVER_PRIVATE_KEY" | wg pubkey)
    
    complete_progress "服务器密钥生成完成"
    echo ""
}

# ========== 创建服务器配置 ==========
create_server_config() {
    echo -e "${GREEN}${BOLD}${ICON_SERVER} 创建服务器配置...${NC}"
    
    for i in {1..8}; do
        show_progress $i 8 "生成服务器配置文件"
        sleep 0.1
    done
    
    cat > $WG_CONFIG_PATH/$WG_INTERFACE.conf << SERVER_CONF_EOF
[Interface]
# WireGuard服务器配置
# 生成时间: $(date)
# 服务器私钥
PrivateKey = $SERVER_PRIVATE_KEY

# 服务器地址
Address = $SERVER_WG_IPV4/24, $SERVER_WG_IPV6/64

# 监听端口
ListenPort = $WG_PORT

# MTU优化
MTU = 1420

# 启动和关闭时执行的命令
PostUp = iptables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE
PostUp = ip6tables -t nat -A POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE
PostUp = iptables -A FORWARD -i $WG_INTERFACE -j ACCEPT
PostUp = iptables -A FORWARD -o $WG_INTERFACE -j ACCEPT
PostUp = ip6tables -A FORWARD -i $WG_INTERFACE -j ACCEPT
PostUp = ip6tables -A FORWARD -o $WG_INTERFACE -j ACCEPT

PostDown = iptables -t nat -D POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE
PostDown = ip6tables -t nat -D POSTROUTING -o $MAIN_INTERFACE -j MASQUERADE
PostDown = iptables -D FORWARD -i $WG_INTERFACE -j ACCEPT
PostDown = iptables -D FORWARD -o $WG_INTERFACE -j ACCEPT
PostDown = ip6tables -D FORWARD -i $WG_INTERFACE -j ACCEPT
PostDown = ip6tables -D FORWARD -o $WG_INTERFACE -j ACCEPT

SERVER_CONF_EOF

    chmod 600 $WG_CONFIG_PATH/$WG_INTERFACE.conf
    
    # 复制到输出目录
    cp $WG_CONFIG_PATH/$WG_INTERFACE.conf $OUTPUT_DIR/server_config.conf
    
    complete_progress "服务器配置文件创建完成"
    echo ""
}

# ========== 生成客户端配置 ==========
generate_client_configs() {
    echo -e "${BLUE}${BOLD}${ICON_CLIENT} 生成客户端配置...${NC}"
    
    # 创建客户端配置目录
    mkdir -p $WG_CONFIG_PATH/clients $OUTPUT_DIR/clients
    chmod 700 $WG_CONFIG_PATH/clients $OUTPUT_DIR/clients
    
    # 创建客户端信息汇总文件
    cat > $OUTPUT_DIR/clients_info.txt << INFO_EOF
WireGuard客户端配置信息
生成时间: $(date)
服务器IP: $PUBLIC_IPV4
服务器端口: $WG_PORT
==================================================

INFO_EOF
    
    for i in $(seq 1 $CLIENT_COUNT); do
        show_progress $i $CLIENT_COUNT "生成客户端配置 client$i"
        
        CLIENT_NAME="client$i"
        CLIENT_IPV4="10.66.66.$((i+1))"
        CLIENT_IPV6="fd42:42:42::$((i+1))"
        
        # 生成客户端密钥
        CLIENT_PRIVATE_KEY=$(wg genkey)
        CLIENT_PUBLIC_KEY=$(echo "$CLIENT_PRIVATE_KEY" | wg pubkey)
        PRESHARED_KEY=$(wg genpsk)
        
        # 创建客户端配置文件
        cat > $WG_CONFIG_PATH/clients/$CLIENT_NAME.conf << CLIENT_CONF_EOF
[Interface]
# 客户端配置: $CLIENT_NAME
# 生成时间: $(date)
PrivateKey = $CLIENT_PRIVATE_KEY
Address = $CLIENT_IPV4/24, $CLIENT_IPV6/64
DNS = 1.1.1.1, 1.0.0.1, 2606:4700:4700::1111
MTU = 1420

[Peer]
# 服务器信息
PublicKey = $SERVER_PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
Endpoint = $PUBLIC_IPV4:$WG_PORT
AllowedIPs = 0.0.0.0/0, ::/0
PersistentKeepalive = 25
CLIENT_CONF_EOF

        chmod 600 $WG_CONFIG_PATH/clients/$CLIENT_NAME.conf
        
        # 复制到输出目录
        cp $WG_CONFIG_PATH/clients/$CLIENT_NAME.conf $OUTPUT_DIR/clients/
        
        # 添加到服务器配置
        cat >> $WG_CONFIG_PATH/$WG_INTERFACE.conf << PEER_CONF_EOF

[Peer]
# 客户端: $CLIENT_NAME ($CLIENT_IPV4)
PublicKey = $CLIENT_PUBLIC_KEY
PresharedKey = $PRESHARED_KEY
AllowedIPs = $CLIENT_IPV4/32, $CLIENT_IPV6/128

PEER_CONF_EOF
        
        # 添加到信息文件
        cat >> $OUTPUT_DIR/clients_info.txt << CLIENT_INFO_EOF
客户端: $CLIENT_NAME
  IPv4地址: $CLIENT_IPV4
  IPv6地址: $CLIENT_IPV6
  配置文件: $OUTPUT_DIR/clients/$CLIENT_NAME.conf
  
CLIENT_INFO_EOF
        
        sleep 0.1
    done
    
    complete_progress "所有客户端配置生成完成"
    
    # 更新服务器配置到输出目录
    cp $WG_CONFIG_PATH/$WG_INTERFACE.conf $OUTPUT_DIR/server_config.conf
    
    log "客户端配置文件已保存到: $OUTPUT_DIR/clients/"
    echo ""
}

# ========== 生成QR码 ==========
generate_qr_codes() {
    echo -e "${CYAN}${BOLD}${ICON_CONFIG} 生成QR码...${NC}"
    
    mkdir -p $OUTPUT_DIR/qrcodes
    
    for i in $(seq 1 $CLIENT_COUNT); do
        show_progress $i $CLIENT_COUNT "生成QR码 client$i"
        
        CLIENT_NAME="client$i"
        if command -v qrencode >/dev/null; then
            qrencode -t ansiutf8 < $OUTPUT_DIR/clients/$CLIENT_NAME.conf > $OUTPUT_DIR/qrcodes/$CLIENT_NAME.qr 2>/dev/null || true
            qrencode -t png -o $OUTPUT_DIR/qrcodes/$CLIENT_NAME.png < $OUTPUT_DIR/clients/$CLIENT_NAME.conf 2>/dev/null || true
        fi
        sleep 0.1
    done
    
    complete_progress "QR码生成完成"
    log "QR码已保存到: $OUTPUT_DIR/qrcodes/"
    echo ""
}

# ========== 启动WireGuard服务 ==========
start_wireguard() {
    echo -e "${YELLOW}${BOLD}${ICON_ROCKET} 启动WireGuard服务...${NC}"
    
    for i in {1..8}; do
        show_progress $i 8 "启动WireGuard接口"
        sleep 0.2
    done
    
    # 停止可能已存在的接口
    wg-quick down $WG_INTERFACE >/dev/null 2>&1 || true
    
    # 启动接口
    if wg-quick up $WG_INTERFACE >/dev/null 2>&1; then
        complete_progress "WireGuard接口启动成功"
    else
        echo -e "\n${RED}${ICON_ERROR} WireGuard接口启动失败${NC}"
        wg-quick up $WG_INTERFACE
        err "WireGuard启动失败"
    fi
    
    # 添加防火墙规则
    if command -v ufw >/dev/null 2>&1; then
        ufw allow in on $WG_INTERFACE >/dev/null 2>&1 || true
        ufw allow out on $WG_INTERFACE >/dev/null 2>&1 || true
    fi
    
    # 设置开机自启
    systemctl enable wg-quick@$WG_INTERFACE >/dev/null 2>&1 || warn "开机自启设置失败"
    
    # 验证服务状态
    sleep 2
    if wg show $WG_INTERFACE >/dev/null 2>&1; then
        log "WireGuard服务运行正常"
    else
        warn "WireGuard服务状态异常"
    fi
    echo ""
}

# ========== 创建管理脚本 ==========
create_management_script() {
    echo -e "${CYAN}${BOLD}${ICON_CONFIG} 创建管理脚本...${NC}"
    
    for i in {1..6}; do
        show_progress $i 6 "生成管理脚本"
        sleep 0.1
    done
    
    cat > /usr/local/bin/wg-manager << 'MGMT_SCRIPT_EOF'
#!/bin/bash

# WireGuard管理脚本
# 美化版本

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

WG_INTERFACE="wg0"
WG_CONFIG_PATH="/etc/wireguard"
OUTPUT_DIR="/opt/wireguard_configs"

log() { echo -e "${GREEN}[INFO]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err() { echo -e "${RED}[ERROR]${NC} $*"; }

show_banner() {
    echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         🚀 WireGuard 管理工具 🚀         ║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
    echo ""
}

case "$1" in
    status)
        show_banner
        echo -e "${BLUE}📊 WireGuard状态:${NC}"
        wg show
        echo ""
        echo -e "${BLUE}🔧 服务状态:${NC}"
        systemctl status wg-quick@$WG_INTERFACE --no-pager
        ;;
    restart)
        show_banner
        log "重启WireGuard服务..."
        wg-quick down $WG_INTERFACE 2>/dev/null || true
        wg-quick up $WG_INTERFACE && log "✅ 重启成功"
        ;;
    stop)
        show_banner
        log "停止WireGuard服务..."
        wg-quick down $WG_INTERFACE && log "✅ 停止成功"
        ;;
    start)
        show_banner
        log "启动WireGuard服务..."
        wg-quick up $WG_INTERFACE && log "✅ 启动成功"
        ;;
    clients)
        show_banner
        echo -e "${BLUE}📱 客户端配置文件:${NC}"
        if [[ -d "$OUTPUT_DIR/clients" ]]; then
            ls -la $OUTPUT_DIR/clients/
            echo ""
            echo -e "${YELLOW}配置信息文件: $OUTPUT_DIR/clients_info.txt${NC}"
        else
            warn "客户端配置目录不存在"
        fi
        ;;
    qr)
        show_banner
        if [[ -n "$2" ]]; then
            if [[ -f "$OUTPUT_DIR/clients/$2.conf" ]]; then
                echo -e "${BLUE}📱 客户端 $2 的QR码:${NC}"
                if [[ -f "$OUTPUT_DIR/qrcodes/$2.qr" ]]; then
                    cat $OUTPUT_DIR/qrcodes/$2.qr
                else
                    qrencode -t ansiutf8 < $OUTPUT_DIR/clients/$2.conf
                fi
            else
                err "客户端配置文件不存在: $2"
            fi
        else
            echo -e "${YELLOW}用法: wg-manager qr <客户端名称>${NC}"
            echo -e "${BLUE}可用客户端:${NC}"
            ls $OUTPUT_DIR/clients/*.conf 2>/dev/null | sed 's/.*\/\(.*\)\.conf/\1/' || echo "暂无客户端配置"
        fi
        ;;
    configs)
        show_banner
        echo -e "${BLUE}📁 配置文件位置:${NC}"
        echo -e "  ${GREEN}输出目录:${NC} $OUTPUT_DIR"
        echo -e "  ${GREEN}服务器配置:${NC} $OUTPUT_DIR/server_config.conf"
        echo -e "  ${GREEN}客户端配置:${NC} $OUTPUT_DIR/clients/"
        echo -e "  ${GREEN}QR码目录:${NC} $OUTPUT_DIR/qrcodes/"
        echo -e "  ${GREEN}客户端信息:${NC} $OUTPUT_DIR/clients_info.txt"
        echo -e "  ${GREEN}配置JSON:${NC} $OUTPUT_DIR/wireguard_configs.json"
        ;;
    *)
        show_banner
        echo -e "${BLUE}🛠️ WireGuard管理脚本${NC}"
        echo -e "${YELLOW}用法: $0 {status|start|stop|restart|clients|qr|configs}${NC}"
        echo ""
        echo -e "${BLUE}命令说明:${NC}"
        echo -e "  ${GREEN}status${NC}   - 显示WireGuard状态"
        echo -e "  ${GREEN}start${NC}    - 启动WireGuard服务"
        echo -e "  ${GREEN}stop${NC}     - 停止WireGuard服务"
        echo -e "  ${GREEN}restart${NC}  - 重启WireGuard服务"
        echo -e "  ${GREEN}clients${NC}  - 列出客户端配置文件"
        echo -e "  ${GREEN}qr${NC}       - 显示客户端配置的QR码"
        echo -e "  ${GREEN}configs${NC}  - 显示配置文件位置"
        ;;
esac
MGMT_SCRIPT_EOF

    chmod +x /usr/local/bin/wg-manager
    
    # 创建详细信息文件
    cat > $OUTPUT_DIR/deployment_info.json << JSON_EOF
{
  "deployment_info": {
    "generated_time": "$(date -Iseconds)",
    "server_ip": "$PUBLIC_IPV4",
    "wireguard_port": $WG_PORT,
    "server_internal_ipv4": "$SERVER_WG_IPV4",
    "server_internal_ipv6": "$SERVER_WG_IPV6",
    "network_interface": "$MAIN_INTERFACE",
    "client_count": $CLIENT_COUNT,
    "config_directory": "$OUTPUT_DIR",
    "management_script": "/usr/local/bin/wg-manager"
  },
  "network_optimization": {
    "bbr_enabled": true,
    "udp_optimized": true,
    "mtu_size": 1420,
    "congestion_control": "bbr"
  },
  "security_features": {
    "preshared_keys": true,
    "firewall": "ufw",
    "ip_forwarding": true
  }
}
JSON_EOF
    
    complete_progress "管理脚本创建完成"
    log "管理脚本路径: /usr/local/bin/wg-manager"
    echo ""
}

# ========== 显示最终结果 ==========
show_final_result() {
    clear
    echo -e "${PURPLE}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}${BOLD}║                                                                              ║${NC}"
    echo -e "${PURPLE}${BOLD}║              ${YELLOW}${ICON_ROCKET} WireGuard VPN 服务器部署完成！${ICON_ROCKET}${PURPLE}${BOLD}                             ║${NC}"
    echo -e "${PURPLE}${BOLD}║                                                                              ║${NC}"
    echo -e "${PURPLE}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}📊 服务器信息：${NC}"
    echo -e "  ${CYAN}服务器IP：${YELLOW}${PUBLIC_IPV4}${NC}"
    echo -e "  ${CYAN}WireGuard端口：${YELLOW}${WG_PORT} ${GREEN}(随机生成)${NC}"
    echo -e "  ${CYAN}内网IPv4：${YELLOW}${SERVER_WG_IPV4}/24${NC}"
    echo -e "  ${CYAN}内网IPv6：${YELLOW}${SERVER_WG_IPV6}/64${NC}"
    echo -e "  ${CYAN}网络接口：${YELLOW}${MAIN_INTERFACE}${NC}"
    echo -e "  ${CYAN}客户端数量：${YELLOW}${CLIENT_COUNT}${NC}\n"
    
    echo -e "${WHITE}${BOLD}📁 配置文件位置：${NC}"
    echo -e "  ${CYAN}输出目录：${YELLOW}${OUTPUT_DIR}${NC}"
    echo -e "  ${CYAN}服务器配置：${YELLOW}${OUTPUT_DIR}/server_config.conf${NC}"
    echo -e "  ${CYAN}客户端配置：${YELLOW}${OUTPUT_DIR}/clients/client1.conf ~ client${CLIENT_COUNT}.conf${NC}"
    echo -e "  ${CYAN}QR码文件：${YELLOW}${OUTPUT_DIR}/qrcodes/client1.qr ~ client${CLIENT_COUNT}.qr${NC}"
    echo -e "  ${CYAN}客户端信息：${YELLOW}${OUTPUT_DIR}/clients_info.txt${NC}"
    echo -e "  ${CYAN}部署信息：${YELLOW}${OUTPUT_DIR}/deployment_info.json${NC}"
    echo -e "  ${CYAN}配置JSON：${YELLOW}${OUTPUT_DIR}/wireguard_configs.json${NC}\n"
    
    echo -e "${WHITE}${BOLD}🛠️ 管理命令：${NC}"
    echo -e "  ${CYAN}查看状态：${YELLOW}wg-manager status${NC}"
    echo -e "  ${CYAN}重启服务：${YELLOW}wg-manager restart${NC}"
    echo -e "  ${CYAN}查看客户端：${YELLOW}wg-manager clients${NC}"
    echo -e "  ${CYAN}显示QR码：${YELLOW}wg-manager qr client1${NC}"
    echo -e "  ${CYAN}配置位置：${YELLOW}wg-manager configs${NC}\n"
    
    echo -e "${GREEN}${BOLD}🚀 快速使用指南：${NC}"
    echo -e "${WHITE}1. 客户端配置导入：${NC}"
    echo -e "   ${WHITE}• 方法一：扫描QR码 ${YELLOW}wg-manager qr client1${NC}"
    echo -e "   ${WHITE}• 方法二：导入配置文件 ${YELLOW}${OUTPUT_DIR}/clients/client1.conf${NC}\n"
    
    echo -e "${WHITE}2. 支持的客户端：${NC}"
    echo -e "   ${WHITE}• ${CYAN}Android：${NC} WireGuard官方应用"
    echo -e "   ${WHITE}• ${CYAN}iOS：${NC} WireGuard官方应用"
    echo -e "   ${WHITE}• ${CYAN}Windows：${NC} WireGuard官方客户端"
    echo -e "   ${WHITE}• ${CYAN}macOS：${NC} WireGuard官方客户端"
    echo -e "   ${WHITE}• ${CYAN}Linux：${NC} wg-quick命令行工具\n"
    
    echo -e "${WHITE}3. 客户端配置参数：${NC}"
    echo -e "   ${WHITE}• ${CYAN}服务器地址：${NC}${PUBLIC_IPV4}:${WG_PORT}"
    echo -e "   ${WHITE}• ${CYAN}客户端IP范围：${NC}10.66.66.2-10.66.66.11"
    echo -e "   ${WHITE}• ${CYAN}DNS服务器：${NC}1.1.1.1, 1.0.0.1"
    echo -e "   ${WHITE}• ${CYAN}MTU大小：${NC}1420"
    echo -e "   ${WHITE}• ${CYAN}保活间隔：${NC}25秒\n"
    
    echo -e "${GREEN}${BOLD}🔧 优化特性：${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} BBR拥塞控制已启用${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} UDP网络参数已优化${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 预共享密钥增强安全${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 防火墙规则已配置${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} IPv4/IPv6双栈支持${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 随机端口防止封锁${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 自动启动已设置${NC}"
    
    echo -e "${RED}${BOLD}🔒 安全提醒：${NC}"
    echo -e "  ${WHITE}• 请妥善保管配置文件，不要泄露给他人${NC}"
    echo -e "  ${WHITE}• 定期更新系统和WireGuard版本${NC}"
    echo -e "  ${WHITE}• 监控服务器资源使用情况${NC}"
    echo -e "  ${WHITE}• 配置文件包含敏感信息，注意权限管理${NC}\n"
    
    # 特别提醒IP地址
    if [[ "$PUBLIC_IPV4" == "127.0.0.1" ]]; then
        echo -e "${RED}${BOLD}⚠️ 重要提醒：${NC}"
        echo -e "  ${WHITE}• 无法自动获取公网IP，当前使用默认值: ${YELLOW}$PUBLIC_IPV4${NC}"
        echo -e "  ${WHITE}• 请手动修改客户端配置中的Endpoint地址为您的实际服务器IP${NC}"
        echo -e "  ${WHITE}• 客户端配置文件位置: ${YELLOW}$OUTPUT_DIR/clients/${NC}\n"
    fi
    
    echo -e "${BLUE}${BOLD}${ICON_INFO} 部署完成时间：${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${GREEN}${BOLD}🎉 WireGuard VPN服务器部署成功！${NC}"
    echo -e "${WHITE}所有配置文件已保存到 ${YELLOW}${OUTPUT_DIR}${WHITE} 目录${NC}\n"
    
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}"
}

# ========== 错误处理 ==========
handle_error() {
    local exit_code=$?
    local line_number=$1
    local command="$2"
    
    echo -e "\n${RED}${BOLD}${ICON_ERROR} 脚本执行过程中出现错误！${NC}"
    echo -e "${WHITE}错误代码：${YELLOW}$exit_code${NC}"
    echo -e "${WHITE}错误行号：${YELLOW}$line_number${NC}"
    echo -e "${WHITE}错误命令：${YELLOW}$command${NC}"
    echo -e "${WHITE}常见解决方案：${NC}"
    echo -e "  ${WHITE}1. 检查系统权限和磁盘空间${NC}"
    echo -e "  ${WHITE}2. 确保系统支持WireGuard${NC}"
    echo -e "  ${WHITE}3. 查看系统日志：journalctl -xe${NC}"
    echo -e "  ${WHITE}4. 检查防火墙设置${NC}\n"
    
    # 尝试清理
    wg-quick down $WG_INTERFACE 2>/dev/null || true
    
    exit 1
}

# 设置错误陷阱
trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR

# ========== 环境检查 (移除网络检查) ==========
check_environment() {
    echo -e "${BLUE}${BOLD}${ICON_INFO} 检查运行环境...${NC}"
    
    # 检查是否为root用户
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}${ICON_ERROR} 此脚本需要root权限运行！${NC}"
        echo -e "${WHITE}请使用：${YELLOW}sudo bash $0${NC}"
        exit 1
    fi
    
    # 检查磁盘空间
    available_space=$(df / | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 1048576 ]]; then  # 1GB = 1048576KB
        echo -e "${RED}${ICON_ERROR} 磁盘空间不足（需要至少1GB可用空间）！${NC}"
        echo -e "${WHITE}当前可用空间：${YELLOW}$(($available_space/1024))MB${NC}"
        exit 1
    fi
    
    # 检查系统时间（确保配置生成正常）
    current_year=$(date +%Y)
    if [[ $current_year -lt 2020 || $current_year -gt 2030 ]]; then
        warn "系统时间可能不正确，可能影响配置生成"
        echo -e "${WHITE}当前时间：${YELLOW}$(date)${NC}"
    fi
    
    echo -e "${GREEN}${ICON_SUCCESS} 环境检查通过${NC}\n"
}

# ========== 清理函数 ==========
cleanup_on_exit() {
    local exit_code=$?
    
    # 只在正常退出时清理
    if [[ $exit_code -eq 0 ]]; then
        echo -e "\n${YELLOW}${ICON_INFO} 正在清理临时文件...${NC}"
        rm -f /tmp/wireguard_install_* 2>/dev/null || true
        rm -f /tmp/wireguard_temp.json 2>/dev/null || true
    fi
}

# 设置退出时清理
trap cleanup_on_exit EXIT

# ========== 主安装流程 ==========
main_install() {
    show_banner
    check_environment
    detect_system
    detect_ipv4_forced
    detect_interface
    
    install_dependencies
    optimize_network
    setup_firewall
    
    generate_keys
    create_server_config
    generate_client_configs
    generate_qr_codes
    
    start_wireguard
    create_management_script
    
    upload_configs
    
    show_final_result
}

# ========== 脚本入口 ==========
echo -e "${BLUE}${BOLD}正在初始化WireGuard部署脚本...${NC}\n"

# 执行主安装流程
main_install

echo -e "${GREEN}${BOLD}🎊 所有任务执行完毕！${NC}"
echo -e "${WHITE}服务状态检查：${YELLOW}wg-manager status${NC}"
echo -e "${WHITE}配置文件位置：${YELLOW}${OUTPUT_DIR}${NC}"
echo -e "${WHITE}配置JSON文件：${YELLOW}${OUTPUT_DIR}/wireguard_configs.json${NC}"
echo -e "${WHITE}如有问题，请查看日志：${YELLOW}journalctl -u wg-quick@${WG_INTERFACE} -f${NC}\n"
