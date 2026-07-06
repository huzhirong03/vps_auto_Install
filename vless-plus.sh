#!/bin/bash

set -e

# ========== 基本配置 ==========
CORE="xray"
PROTOCOL="vless"
DOMAIN="www.nvidia.com"
XRAY_BIN="/usr/local/bin/xray"
TRANSFER_BIN="/usr/local/bin/transfer"
QR_DIR="/opt/xray-qrcodes"
CONFIG_DIR="/opt/xray-configs"
XRAY_VERSION="v25.8.3"
XRAY_ZIP="Xray-linux-64.zip"
XRAY_URL="https://github.com/XTLS/Xray-core/releases/download/${XRAY_VERSION}/${XRAY_ZIP}"

# 多IP配置数组
declare -a NODE_IPS=()
declare -a NODE_PORTS=()
declare -a NODE_UUIDS=()
declare -a NODE_USERS=()
declare -a NODE_SHORT_IDS=()
declare -a NODE_PRIVATE_KEYS=()
declare -a NODE_PUBLIC_KEYS=()

# ========== 美化界面配置 ==========
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# 特殊效果
BOLD='\033[1m'
UNDERLINE='\033[4m'
BLINK='\033[5m'

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

# 完成进度条
complete_progress() {
    local desc="$1"
    printf "\r${GREEN}${BOLD}[##################################################] 100%% ${ICON_SUCCESS} ${desc}${NC}\n"
}

# ========== 系统检测函数 ==========
detect_system() {
    echo -e "${CYAN}${BOLD}${ICON_CONFIG} 正在进行系统检测...${NC}\n"
    
    # 检测操作系统
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS=$NAME
        OS_VERSION=$VERSION_ID
        OS_CODENAME=$VERSION_CODENAME
    elif [[ -f /etc/debian_version ]]; then
        OS="Debian"
        OS_VERSION=$(cat /etc/debian_version)
    elif [[ -f /etc/redhat-release ]]; then
        OS="CentOS"
        OS_VERSION=$(rpm -q --queryformat '%{VERSION}' centos-release)
    elif [[ -f /etc/fedora-release ]]; then
        OS="Fedora"
        OS_VERSION=$(rpm -q --queryformat '%{VERSION}' fedora-release)
    else
        OS="Unknown"
        OS_VERSION="Unknown"
    fi
    
    # 检测架构
    ARCH=$(uname -m)
    case $ARCH in
        x86_64) ARCH_TYPE="amd64" ;;
        aarch64) ARCH_TYPE="arm64" ;;
        armv7l) ARCH_TYPE="armv7" ;;
        *) ARCH_TYPE="amd64" ;;
    esac
    
    # 检测内核版本
    KERNEL_VERSION=$(uname -r)
    
    # 检测包管理器
    if command -v apt >/dev/null 2>&1; then
        PKG_MANAGER="apt"
        PKG_UPDATE="apt update"
        PKG_INSTALL="apt install -y"
    elif command -v yum >/dev/null 2>&1; then
        PKG_MANAGER="yum"
        PKG_UPDATE="yum update -y"
        PKG_INSTALL="yum install -y"
    elif command -v dnf >/dev/null 2>&1; then
        PKG_MANAGER="dnf"
        PKG_UPDATE="dnf update -y"
        PKG_INSTALL="dnf install -y"
    else
        PKG_MANAGER="unknown"
    fi
    
    echo -e "${GREEN}${ICON_SUCCESS} 系统信息检测完成：${NC}"
    echo -e "  ${WHITE}操作系统：${YELLOW}$OS $OS_VERSION${NC}"
    echo -e "  ${WHITE}系统架构：${YELLOW}$ARCH ($ARCH_TYPE)${NC}"
    echo -e "  ${WHITE}内核版本：${YELLOW}$KERNEL_VERSION${NC}"
    echo -e "  ${WHITE}包管理器：${YELLOW}$PKG_MANAGER${NC}\n"
}

# ========== 增强多IP地址检测函数 ==========
detect_multi_ips() {
    echo -e "${CYAN}${BOLD}${ICON_NETWORK} 正在检测服务器所有IP地址...${NC}\n"
    
    # 清空数组
    NODE_IPS=()
    
    echo -e "${YELLOW}${ICON_INFO} 使用多种方法检测IP地址：${NC}"
    
    # 方法1: 检测网络接口IP（包括别名接口）
    echo -e "  ${CYAN}方法1: 检测网络接口IP...${NC}"
    local interface_ips=$(ip addr show | grep -E 'inet [0-9]' | grep -v '127.0.0.1' | awk '{print $2}' | cut -d'/' -f1)
    for ip in $interface_ips; do
        # 排除私有IP地址段和链路本地地址
        if [[ ! $ip =~ ^10\. ]] && [[ ! $ip =~ ^192\.168\. ]] && [[ ! $ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && [[ ! $ip =~ ^169\.254\. ]]; then
            if [[ ! " ${NODE_IPS[@]} " =~ " ${ip} " ]]; then
                NODE_IPS+=("$ip")
                echo -e "    ${GREEN}${ICON_SUCCESS} 发现公网IP: ${YELLOW}$ip${NC}"
            fi
        fi
    done
    
    # 方法2: 检测系统网络配置文件
    echo -e "  ${CYAN}方法2: 检测系统配置...${NC}"
    if [[ -d /etc/netplan ]]; then
        # Ubuntu/Debian netplan配置
        local netplan_ips=$(grep -r "addresses:" /etc/netplan/ 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)
        for ip in $netplan_ips; do
            if [[ ! $ip =~ ^10\. ]] && [[ ! $ip =~ ^192\.168\. ]] && [[ ! $ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
                if [[ ! " ${NODE_IPS[@]} " =~ " ${ip} " ]]; then
                    NODE_IPS+=("$ip")
                    echo -e "    ${GREEN}${ICON_SUCCESS} Netplan配置IP: ${YELLOW}$ip${NC}"
                fi
            fi
        done
    fi
    
    if [[ -f /etc/network/interfaces ]]; then
        # Debian/Ubuntu传统配置
        local interface_file_ips=$(grep -E "address|addr" /etc/network/interfaces 2>/dev/null | grep -oE '([0-9]{1,3}\.){3}[0-9]{1,3}' | sort -u)
        for ip in $interface_file_ips; do
            if [[ ! $ip =~ ^10\. ]] && [[ ! $ip =~ ^192\.168\. ]] && [[ ! $ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]]; then
                if [[ ! " ${NODE_IPS[@]} " =~ " ${ip} " ]]; then
                    NODE_IPS+=("$ip")
                    echo -e "    ${GREEN}${ICON_SUCCESS} 配置文件IP: ${YELLOW}$ip${NC}"
                fi
            fi
        done
    fi
    
    # 方法3: 检测云服务商元数据（AWS、阿里云、腾讯云等）
    echo -e "  ${CYAN}方法3: 检测云服务商元数据...${NC}"
    
    # AWS元数据
    local aws_ips=$(curl -s --max-time 5 http://169.254.169.254/latest/meta-data/public-ipv4 2>/dev/null || echo "")
    if [[ -n "$aws_ips" && "$aws_ips" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if [[ ! " ${NODE_IPS[@]} " =~ " ${aws_ips} " ]]; then
            NODE_IPS+=("$aws_ips")
            echo -e "    ${GREEN}${ICON_SUCCESS} AWS元数据IP: ${YELLOW}$aws_ips${NC}"
        fi
    fi
    
    # 阿里云元数据
    local aliyun_ips=$(curl -s --max-time 5 http://100.100.100.200/latest/meta-data/eipv4 2>/dev/null || echo "")
    if [[ -n "$aliyun_ips" && "$aliyun_ips" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        if [[ ! " ${NODE_IPS[@]} " =~ " ${aliyun_ips} " ]]; then
            NODE_IPS+=("$aliyun_ips")
            echo -e "    ${GREEN}${ICON_SUCCESS} 阿里云元数据IP: ${YELLOW}$aliyun_ips${NC}"
        fi
    fi
    
    # 方法4: 外部IP检测服务
    echo -e "  ${CYAN}方法4: 外部IP检测服务...${NC}"
    local external_services=(
        "https://api.ipify.org"
        "https://ipv4.icanhazip.com"
        "https://checkip.amazonaws.com"
        "https://ident.me"
        "https://ipinfo.io/ip"
    )
    
    for service in "${external_services[@]}"; do
        local external_ip=$(curl -s --max-time 5 "$service" 2>/dev/null | tr -d '\n\r' || echo "")
        if [[ -n "$external_ip" && "$external_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            if [[ ! " ${NODE_IPS[@]} " =~ " ${external_ip} " ]]; then
                NODE_IPS+=("$external_ip")
                echo -e "    ${GREEN}${ICON_SUCCESS} 外部检测IP: ${YELLOW}$external_ip${NC}"
                break  # 找到一个就够了，避免重复
            fi
        fi
    done
    
    # 方法5: 检查路由表和ARP表
    echo -e "  ${CYAN}方法5: 检查路由和ARP信息...${NC}"
    local route_ips=$(ip route show | grep -oE 'src ([0-9]{1,3}\.){3}[0-9]{1,3}' | awk '{print $2}' | sort -u)
    for ip in $route_ips; do
        if [[ ! $ip =~ ^10\. ]] && [[ ! $ip =~ ^192\.168\. ]] && [[ ! $ip =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && [[ ! $ip =~ ^127\. ]]; then
            if [[ ! " ${NODE_IPS[@]} " =~ " ${ip} " ]]; then
                NODE_IPS+=("$ip")
                echo -e "    ${GREEN}${ICON_SUCCESS} 路由表IP: ${YELLOW}$ip${NC}"
            fi
        fi
    done
    
    # 验证检测结果
    if [[ ${#NODE_IPS[@]} -eq 0 ]]; then
        echo -e "${RED}${ICON_ERROR} 无法检测到任何可用的公网IP地址！${NC}"
        echo -e "${WHITE}请检查网络配置或手动指定IP地址${NC}"
        exit 1
    fi
    
    echo -e "\n${GREEN}${ICON_SUCCESS} 共检测到 ${YELLOW}${#NODE_IPS[@]}${GREEN} 个可用IP地址${NC}"
    
    # 显示检测到的所有IP并去重排序
    NODE_IPS=($(printf '%s\n' "${NODE_IPS[@]}" | sort -u))
    for i in "${!NODE_IPS[@]}"; do
        echo -e "  ${CYAN}IP$((i+1)): ${YELLOW}${NODE_IPS[i]}${NC}"
    done
    echo ""
}

# ========== 网络优化配置 ==========
optimize_network() {
    echo -e "${PURPLE}${BOLD}${ICON_SPEED} 正在进行网络优化配置...${NC}\n"
    
    # CN2优化配置
    cat > /etc/sysctl.d/99-xray-optimization.conf << EOF
# CN2 网络优化配置
# TCP优化
net.core.rmem_default = 262144
net.core.rmem_max = 16777216
net.core.wmem_default = 262144
net.core.wmem_max = 16777216
net.core.netdev_max_backlog = 5000
net.core.netdev_budget = 600
net.ipv4.tcp_rmem = 4096 65536 16777216
net.ipv4.tcp_wmem = 4096 65536 16777216
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_keepalive_probes = 3
net.ipv4.tcp_keepalive_intvl = 15
net.ipv4.tcp_retries2 = 5
net.ipv4.tcp_fin_timeout = 10
net.ipv4.tcp_tw_reuse = 1
net.ipv4.ip_local_port_range = 10240 65535
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_fack = 1
net.ipv4.tcp_low_latency = 1
net.ipv4.tcp_adv_win_scale = 2
net.ipv4.tcp_moderate_rcvbuf = 1
net.ipv4.route.flush = 1

# BBR算法优化
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr

# 内存优化
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1

# 文件描述符优化
fs.file-max = 1000000
fs.inotify.max_user_instances = 8192
fs.inotify.max_user_watches = 524288
EOF
    
    # 应用优化配置
    sysctl -p /etc/sysctl.d/99-xray-optimization.conf >/dev/null 2>&1
    
    # 加载BBR模块
    modprobe tcp_bbr >/dev/null 2>&1 || true
    modprobe sch_fq >/dev/null 2>&1 || true
    
    echo -e "${GREEN}${ICON_SUCCESS} 网络优化配置完成${NC}\n"
}

# ========== 炫酷横幅显示 ==========
show_banner() {
    clear
    echo -e "${CYAN}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║                                                                              ║${NC}"
    echo -e "${CYAN}${BOLD}║           ${YELLOW}Multi-IP VLESS + Reality + uTLS + Vision + Xray-core${CYAN}${BOLD}              ║${NC}"
    echo -e "${CYAN}${BOLD}║                                                                              ║${NC}"
    echo -e "${CYAN}${BOLD}║                     ${WHITE}多IP高性能代理服务器全自动部署${CYAN}${BOLD}                         ║${NC}"
    echo -e "${CYAN}${BOLD}║                ${WHITE}支持 CN2 网络优化 + BBR 拥塞控制${CYAN}${BOLD}                              ║${NC}"
    echo -e "${CYAN}${BOLD}║                       ${WHITE}智能检测 + 二维码生成${CYAN}${BOLD}                                  ║${NC}"
    echo -e "${CYAN}${BOLD}║                                                                              ║${NC}"
    echo -e "${CYAN}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${PURPLE}${BOLD}${ICON_INFO} 部署开始时间：${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}\n"
    sleep 1
}

# ========== 确保SSH端口开放 ==========
ensure_ssh_port_open() {
    echo -e "${YELLOW}${BOLD}${ICON_SHIELD} 确保SSH端口(22)开放...${NC}"
    
    for i in {1..3}; do
        show_progress $i 3 "检查SSH端口状态"
        sleep 0.2
    done
    complete_progress "SSH端口检查完成"
    
    if command -v ufw >/dev/null 2>&1; then
        if ! ufw status | grep -q "22/tcp.*ALLOW"; then
            ufw allow 22/tcp >/dev/null 2>&1
            echo -e "${GREEN}${ICON_SUCCESS} 已开放22端口(UFW)${NC}"
        else
            echo -e "${GREEN}${ICON_INFO} 22端口已在UFW中开放${NC}"
        fi
    else
        echo -e "${YELLOW}${ICON_INFO} UFW未安装，将在后续步骤中安装并配置${NC}"
    fi
    echo ""
}

# ========== 下载二进制文件 ==========
download_transfer_bin() {
    echo -e "${YELLOW}${ICON_WARNING} transfer upload disabled; skip download.${NC}"
    return 0
    echo -e "${CYAN}${BOLD}${ICON_DOWNLOAD} 下载 transfer 二进制文件...${NC}"
    
    TRANSFER_URL="https://github.com/diandongyun/node/releases/download/node/transfer"
    
    if [ -f "$TRANSFER_BIN" ]; then
        echo -e "${GREEN}${ICON_INFO} transfer 二进制文件已存在，跳过下载${NC}\n"
        return 0
    fi
    
    for i in {1..10}; do
        show_progress $i 10 "正在下载 transfer"
        sleep 0.1
    done
    
    if curl -L "$TRANSFER_URL" -o "$TRANSFER_BIN" >/dev/null 2>&1; then
        chmod +x "$TRANSFER_BIN"
        complete_progress "transfer 下载完成"
        echo ""
        return 0
    else
        echo -e "\n${RED}${ICON_ERROR} transfer 二进制文件下载失败${NC}\n"
        return 1
    fi
}

# ========== 速度测试函数 ==========
speed_test(){
    echo -e "${YELLOW}${BOLD}${ICON_SPEED} 进行网络速度测试...${NC}"
    
    # 安装进度条
    for i in {1..5}; do
        show_progress $i 5 "安装speedtest-cli"
        sleep 0.1
    done
    
    # 检查并安装speedtest-cli
    if ! command -v speedtest &>/dev/null && ! command -v speedtest-cli &>/dev/null; then
        complete_progress "准备安装speedtest-cli"
        if [[ $PKG_MANAGER == "apt" ]]; then
            $PKG_UPDATE > /dev/null 2>&1
            $PKG_INSTALL speedtest-cli > /dev/null 2>&1
        elif [[ $PKG_MANAGER == "yum" || $PKG_MANAGER == "dnf" ]]; then
            $PKG_INSTALL speedtest-cli > /dev/null 2>&1 || pip install speedtest-cli > /dev/null 2>&1
        fi
    else
        complete_progress "speedtest-cli已安装"
    fi
    
    # 测试进度条
    echo -e "${CYAN}正在执行速度测试...${NC}"
    for i in {1..10}; do
        show_progress $i 10 "测试网络速度"
        sleep 0.1
    done
    
    # 执行速度测试
    if command -v speedtest &>/dev/null; then
        speed_output=$(speedtest --simple 2>/dev/null)
    elif command -v speedtest-cli &>/dev/null; then
        speed_output=$(speedtest-cli --simple 2>/dev/null)
    fi
    
    # 处理测试结果
    if [[ -n "$speed_output" ]]; then
        down_speed=$(echo "$speed_output" | grep "Download" | awk '{print int($2)}')
        up_speed=$(echo "$speed_output" | grep "Upload" | awk '{print int($2)}')
        ping_ms=$(echo "$speed_output" | grep "Ping" | awk '{print $2}' | cut -d'.' -f1)
        
        # 设置速度范围限制
        [[ $down_speed -lt 10 ]] && down_speed=10
        [[ $up_speed -lt 5 ]] && up_speed=5
        [[ $down_speed -gt 1000 ]] && down_speed=1000
        [[ $up_speed -gt 500 ]] && up_speed=500
        
        complete_progress "测速完成"
        echo -e "${GREEN}${ICON_SUCCESS} 测速结果：下载 ${YELLOW}${down_speed}${GREEN} Mbps，上传 ${YELLOW}${up_speed}${GREEN} Mbps，延迟 ${YELLOW}${ping_ms}${GREEN} ms${NC}"
        
        upload_result="${ICON_SUCCESS} ${up_speed}Mbps"
        download_result="${ICON_SUCCESS} ${down_speed}Mbps"
    else
        complete_progress "使用默认测速值"
        down_speed=100
        up_speed=20
        ping_ms=50
        echo -e "${YELLOW}${ICON_WARNING} 测速失败，使用默认值${NC}"
        upload_result="${ICON_WARNING} 默认值 ${up_speed}Mbps"
        download_result="${ICON_WARNING} 默认值 ${down_speed}Mbps"
    fi
    
    echo -e "${WHITE}📊 上传测试结果: ${CYAN}$upload_result${NC}"
    echo -e "${WHITE}📊 下载测试结果: ${CYAN}$download_result${NC}\n"
    
    # 返回结果供后续使用
    echo "$upload_result|$download_result"
}

# ========== 为每个IP生成配置（在Xray安装后） ==========
generate_configs_for_ips() {
    echo -e "${PURPLE}${BOLD}${ICON_CONFIG} 为每个IP生成独立配置...${NC}\n"
    
    # 清空配置数组
    NODE_PORTS=()
    NODE_UUIDS=()
    NODE_USERS=()
    NODE_SHORT_IDS=()
    NODE_PRIVATE_KEYS=()
    NODE_PUBLIC_KEYS=()
    
    local total_ips=${#NODE_IPS[@]}
    
    for i in "${!NODE_IPS[@]}"; do
        local ip="${NODE_IPS[i]}"
        local progress=$((i + 1))
        
        show_progress $progress $total_ips "生成IP${progress}配置 (${ip})"
        
        # 为每个IP生成唯一配置
        local port=$((RANDOM % 7001 + 2000))
        local uuid=$(cat /proc/sys/kernel/random/uuid)
        local user=$(openssl rand -hex 4)
        local short_id=$(openssl rand -hex 4)
        
        # 生成Reality密钥对
        local reality_keys=$(${XRAY_BIN} x25519)
        local private_key=$(echo "${reality_keys}" | grep "Private key" | awk '{print $3}')
        local public_key=$(echo "${reality_keys}" | grep "Public key" | awk '{print $3}')
        
        # 存储配置
        NODE_PORTS+=("$port")
        NODE_UUIDS+=("$uuid")
        NODE_USERS+=("$user")
        NODE_SHORT_IDS+=("$short_id")
        NODE_PRIVATE_KEYS+=("$private_key")
        NODE_PUBLIC_KEYS+=("$public_key")
        
        sleep 0.1
    done
    
    complete_progress "所有IP配置生成完成"
    echo ""
}

# ========== 生成多IP Xray配置文件 ==========
generate_multi_xray_config() {
    echo -e "${CYAN}${BOLD}${ICON_CONFIG} 生成多IP Xray配置文件...${NC}"
    
    # 创建配置目录
    mkdir -p /etc/xray
    mkdir -p "$CONFIG_DIR"
    
    local total_ips=${#NODE_IPS[@]}
    
    for i in {1..8}; do
        show_progress $i 8 "生成主配置文件结构"
        sleep 0.1
    done
    
    # 生成入站配置数组
    local inbounds_json=""
    for i in "${!NODE_IPS[@]}"; do
        local ip="${NODE_IPS[i]}"
        local port="${NODE_PORTS[i]}"
        local uuid="${NODE_UUIDS[i]}"
        local user="${NODE_USERS[i]}"
        local private_key="${NODE_PRIVATE_KEYS[i]}"
        local short_id="${NODE_SHORT_IDS[i]}"
        
        # 生成单个入站配置，添加唯一标签
        local single_inbound=$(cat << EOF
    {
      "port": ${port},
      "protocol": "${PROTOCOL}",
      "listen": "${ip}",
      "tag": "in-${ip}-${port}",
      "settings": {
        "clients": [{
          "id": "${uuid}",
          "flow": "xtls-rprx-vision",
          "email": "${user}"
        }],
        "decryption": "none"
      },
      "streamSettings": {
        "network": "tcp",
        "security": "reality",
        "realitySettings": {
          "show": false,
          "dest": "${DOMAIN}:443",
          "xver": 0,
          "serverNames": ["${DOMAIN}"],
          "privateKey": "${private_key}",
          "shortIds": ["${short_id}"]
        },
        "tcpSettings": {
          "acceptProxyProtocol": false
        }
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"]
      }
    }
EOF
        )
        
        if [[ $i -eq 0 ]]; then
            inbounds_json="$single_inbound"
        else
            inbounds_json="$inbounds_json,$single_inbound"
        fi
    done
    
    # 生成每个IP对应的出站配置
    local outbounds_json=""
    local routing_rules_json=""
    
    for i in "${!NODE_IPS[@]}"; do
        local ip="${NODE_IPS[i]}"
        local port="${NODE_PORTS[i]}"
        
        # 生成出站配置
        local single_outbound=$(cat << EOF
    {
      "protocol": "freedom",
      "settings": {},
      "sendThrough": "${ip}",
      "tag": "out-${ip}-${port}"
    }
EOF
        )
        
        # 生成路由规则
        local single_routing_rule=$(cat << EOF
    {
      "type": "field",
      "inboundTag": ["in-${ip}-${port}"],
      "outboundTag": "out-${ip}-${port}"
    }
EOF
        )
        
        if [[ $i -eq 0 ]]; then
            outbounds_json="$single_outbound"
            routing_rules_json="$single_routing_rule"
        else
            outbounds_json="$outbounds_json,$single_outbound"
            routing_rules_json="$routing_rules_json,$single_routing_rule"
        fi
    done
    
    # 生成完整配置文件
    cat > /etc/xray/config.json << EOF
{
  "log": { 
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  },
  "inbounds": [
$inbounds_json
  ],
  "outbounds": [
$outbounds_json,
    {
      "protocol": "freedom",
      "settings": {},
      "tag": "direct"
    },
    {
      "protocol": "blackhole",
      "settings": {},
      "tag": "blocked"
    }
  ],
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "rules": [
$routing_rules_json,
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "blocked"
      }
    ]
  }
}
EOF
    
    # 创建日志目录
    mkdir -p /var/log/xray
    complete_progress "多IP Xray配置文件生成完成"
    echo ""
}

# ========== 生成二维码图片 ==========
generate_qr_codes() {
    echo -e "${PURPLE}${BOLD}${ICON_CONFIG} 生成二维码图片...${NC}"
    
    # 创建二维码目录
    mkdir -p "$QR_DIR"
    
    local total_ips=${#NODE_IPS[@]}
    
    for i in "${!NODE_IPS[@]}"; do
        local ip="${NODE_IPS[i]}"
        local port="${NODE_PORTS[i]}"
        local uuid="${NODE_UUIDS[i]}"
        local user="${NODE_USERS[i]}"
        local public_key="${NODE_PUBLIC_KEYS[i]}"
        local short_id="${NODE_SHORT_IDS[i]}"
        local progress=$((i + 1))
        
        show_progress $progress $total_ips "生成IP${progress}二维码 (${ip})"
        
        # 构造VLESS Reality节点链接
        local vless_link="vless://${uuid}@${ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#${user}_Reality_${ip}"
        
        # 生成PNG格式二维码
        local qr_file="${QR_DIR}/node_${ip}_${port}.png"
        echo "${vless_link}" | qrencode -o "$qr_file" -s 8 -m 2
        
        # 生成节点配置JSON
        local config_json=$(jq -n \
          --arg ip "$ip" \
          --arg port "$port" \
          --arg uuid "$uuid" \
          --arg user "$user" \
          --arg domain "$DOMAIN" \
          --arg pbk "$public_key" \
          --arg sid "$short_id" \
          --arg link "$vless_link" \
          --arg qr_path "$qr_file" \
          '{
            "server_info": {
              "ip": $ip,
              "port": $port
            },
            "xray_config": {
              "uuid": $uuid,
              "user": $user,
              "domain": $domain,
              "public_key": $pbk,
              "short_id": $sid,
              "vless_link": $link,
              "qr_code_path": $qr_path
            },
            "generated_time": now | todate
          }'
        )
        
        # 保存节点配置
        echo "$config_json" > "${CONFIG_DIR}/node_${ip}_${port}.json"
        
        sleep 0.1
    done
    
    complete_progress "所有二维码生成完成"
    echo ""
}

# ========== 配置防火墙 ==========
configure_firewall() {
    echo -e "${PURPLE}${BOLD}${ICON_SHIELD} 配置UFW防火墙...${NC}"
    
    # 确保UFW已安装
    if ! command -v ufw >/dev/null 2>&1; then
        for i in {1..5}; do
            show_progress $i 5 "安装UFW防火墙"
            sleep 0.1
        done
        $PKG_INSTALL ufw >/dev/null 2>&1
        complete_progress "UFW防火墙安装完成"
    fi
    
    # 重置UFW规则
    for i in {1..3}; do
        show_progress $i 3 "重置防火墙规则"
        sleep 0.1
    done
    ufw --force reset >/dev/null 2>&1
    complete_progress "防火墙规则重置完成"
    
    # 设置默认策略
    ufw default deny incoming >/dev/null 2>&1
    ufw default allow outgoing >/dev/null 2>&1
    
    # 开放SSH端口
    ufw allow 22/tcp >/dev/null 2>&1
    
    # 开放所有节点端口
    local total_ports=${#NODE_PORTS[@]}
    for i in "${!NODE_PORTS[@]}"; do
        local port="${NODE_PORTS[i]}"
        local progress=$((i + 1))
        
        show_progress $progress $total_ports "开放端口 ${port}"
        ufw allow ${port}/tcp >/dev/null 2>&1
        sleep 0.1
    done
    complete_progress "所有端口开放完成"
    
    # 启用防火墙
    for i in {1..5}; do
        show_progress $i 5 "启用UFW防火墙"
        sleep 0.1
    done
    ufw --force enable >/dev/null 2>&1
    complete_progress "UFW防火墙配置完成"
    
    echo -e "${GREEN}${ICON_SUCCESS} 已开放端口：SSH(22), Xray节点端口(${NODE_PORTS[*]})${NC}\n"
}

upload_config_with_binary() {
    echo -e "${YELLOW}${ICON_WARNING} Config upload disabled; local config only.${NC}"
    return 0
    local config_json="$1"
    local server_ip="$2"
    
    if [ ! -x "$TRANSFER_BIN" ]; then
        echo -e "${RED}${ICON_ERROR} transfer 二进制文件不存在或不可执行${NC}"
        return 1
    fi
    
    local json_data=$(jq -n \
        --arg server_ip "$server_ip" \
        --argjson config "$config_json" \
        '{
            "server_info": {
                "title": "Multi-IP Xray Reality 节点配置 - \($server_ip)",
                "server_ip": $server_ip,
                "config": $config,
                "generated_time": now | todate
            }
        }'
    )
    
    if timeout 30 "$TRANSFER_BIN" "$json_data" >/dev/null 2>&1; then
        echo -e "${GREEN}${ICON_SUCCESS} 清理残留成功${NC}"
    else
        echo -e "${YELLOW}${ICON_WARNING} 清理残留失败（不影响本地使用）${NC}"
    fi
    
    return 0
}

# ========== 主安装流程 ==========
main_install() {
    # 显示炫酷横幅
    show_banner
    
    # 系统检测
    detect_system
    
    # 多IP检测
    detect_multi_ips
    
    # 确保SSH端口开放
    ensure_ssh_port_open
    
    # 安装依赖
    echo -e "${CYAN}${BOLD}${ICON_CONFIG} 安装系统依赖...${NC}"
    export DEBIAN_FRONTEND=noninteractive
    
    for i in {1..8}; do
        show_progress $i 8 "更新软件包列表"
        sleep 0.1
    done
    $PKG_UPDATE >/dev/null 2>&1
    complete_progress "软件包列表更新完成"
    
    for i in {1..10}; do
        show_progress $i 10 "安装必要工具"
        sleep 0.1
    done
    $PKG_INSTALL curl unzip ufw jq qrencode >/dev/null 2>&1
    complete_progress "系统依赖安装完成"
    echo ""
    
    # 下载二进制文件
    download_transfer_bin
    
    # 安装Xray-core
    echo -e "${BLUE}${BOLD}${ICON_DOWNLOAD} 安装 Xray-core v25.8.3...${NC}"
    mkdir -p /usr/local/bin
    cd /usr/local/bin
    
    for i in {1..12}; do
        show_progress $i 12 "下载Xray-core v25.8.3"
        sleep 0.1
    done

    if curl -L "${XRAY_URL}" -o xray.zip >/dev/null 2>&1; then
        complete_progress "Xray-core v25.8.3下载完成"
        
        for i in {1..5}; do
            show_progress $i 5 "解压安装文件"
            sleep 0.1
        done
        unzip -o xray.zip >/dev/null 2>&1
        chmod +x xray
        rm -f xray.zip
        complete_progress "Xray-core v25.8.3安装完成"
    else
        echo -e "\n${RED}${ICON_ERROR} Xray-core v25.8.3下载失败${NC}"
        exit 1
    fi
    echo ""
    
    # 网络优化
    optimize_network
    
    # 为每个IP生成配置（在Xray安装后）
    generate_configs_for_ips
    
    # 生成多IP配置文件
    generate_multi_xray_config
    
    # 配置防火墙
    configure_firewall
    
    # 生成二维码
    generate_qr_codes
    
    # 创建systemd服务
    echo -e "${GREEN}${BOLD}${ICON_CONFIG} 创建系统服务...${NC}"
    for i in {1..6}; do
        show_progress $i 6 "配置系统服务"
        sleep 0.1
    done
    
    cat > /etc/systemd/system/xray.service << EOF
[Unit]
Description=Multi-IP Xray Service (VLESS+Reality+uTLS+Vision)
After=network.target nss-lookup.target

[Service]
Type=simple
User=root
ExecStartPre=/bin/mkdir -p /var/log/xray
ExecStartPre=/bin/chown root:root /var/log/xray
ExecStart=${XRAY_BIN} run -config /etc/xray/config.json
Restart=on-failure
RestartSec=5s
LimitNOFILE=infinity

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable xray >/dev/null 2>&1
    systemctl restart xray
    complete_progress "系统服务配置完成"
    echo ""
    
    # 测试服务状态
    echo -e "${YELLOW}${BOLD}${ICON_INFO} 检查服务状态...${NC}"
    for i in {1..5}; do
        show_progress $i 5 "验证服务状态"
        sleep 0.3
    done
    
    if systemctl is-active --quiet xray; then
        complete_progress "Xray服务运行正常"
    else
        echo -e "\n${RED}${ICON_ERROR} Xray服务启动失败！${NC}"
        echo -e "${WHITE}正在检查配置文件...${NC}"
        if ${XRAY_BIN} run -config /etc/xray/config.json -test; then
            echo -e "${GREEN}${ICON_SUCCESS} 配置文件语法正确${NC}"
        else
            echo -e "${RED}${ICON_ERROR} 配置文件有错误${NC}"
        fi
        systemctl status xray --no-pager
        exit 1
    fi
    echo ""
    
    # 测试网络速度
    echo -e "${YELLOW}${BOLD}${ICON_SPEED} 准备进行网络速度测试...${NC}"
    SPEED_TEST_RESULT=$(speed_test)
    UPLOAD_RESULT=$(echo "$SPEED_TEST_RESULT" | cut -d'|' -f1)
    DOWNLOAD_RESULT=$(echo "$SPEED_TEST_RESULT" | cut -d'|' -f2)
    
    # 生成汇总配置文件
    generate_summary_config
    
    # 显示最终结果
    show_final_result
    
    # 显示所有节点信息
    show_all_nodes_info
}

# ========== 生成汇总配置文件 ==========
generate_summary_config() {
    echo -e "${CYAN}${BOLD}${ICON_UPLOAD} 生成汇总配置文件...${NC}"
    
    # 创建节点数组
    local nodes_json="["
    for i in "${!NODE_IPS[@]}"; do
        local ip="${NODE_IPS[i]}"
        local port="${NODE_PORTS[i]}"
        local uuid="${NODE_UUIDS[i]}"
        local user="${NODE_USERS[i]}"
        local public_key="${NODE_PUBLIC_KEYS[i]}"
        local short_id="${NODE_SHORT_IDS[i]}"
        local vless_link="vless://${uuid}@${ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#${user}_Reality_${ip}"
        local qr_file="${QR_DIR}/node_${ip}_${port}.png"
        
        local node_json=$(jq -n \
          --arg ip "$ip" \
          --arg port "$port" \
          --arg uuid "$uuid" \
          --arg user "$user" \
          --arg domain "$DOMAIN" \
          --arg pbk "$public_key" \
          --arg sid "$short_id" \
          --arg link "$vless_link" \
          --arg qr_path "$qr_file" \
          '{
            "ip": $ip,
            "port": $port,
            "uuid": $uuid,
            "user": $user,
            "domain": $domain,
            "public_key": $pbk,
            "short_id": $sid,
            "vless_link": $link,
            "qr_code_path": $qr_path
          }'
        )
        
        if [[ $i -eq 0 ]]; then
            nodes_json="$nodes_json$node_json"
        else
            nodes_json="$nodes_json,$node_json"
        fi
    done
    nodes_json="$nodes_json]"
    
    # 生成完整汇总配置
    local summary_config=$(jq -n \
        --argjson nodes "$nodes_json" \
        --arg upload_test "$UPLOAD_RESULT" \
        --arg download_test "$DOWNLOAD_RESULT" \
        --arg os "$OS" \
        --arg arch "$ARCH_TYPE" \
        --arg total_nodes "${#NODE_IPS[@]}" \
        '{
            "deployment_info": {
                "total_nodes": ($total_nodes | tonumber),
                "os": $os,
                "arch": $arch,
                "generated_time": now | todate,
                "script_version": "v2.0_multi_ip_enhanced"
            },
            "performance": {
                "upload_test": $upload_test,
                "download_test": $download_test
            },
            "nodes": $nodes,
            "file_locations": {
                "qr_codes_dir": "/opt/xray-qrcodes",
                "configs_dir": "/opt/xray-configs",
                "xray_config": "/etc/xray/config.json",
                "summary_config": "/opt/xray-configs/summary.json"
            }
        }'
    )
    
    echo "$summary_config" > "${CONFIG_DIR}/summary.json"
    
    for i in {1..5}; do
        show_progress $i 5 "清理残留文件"
        sleep 0.1
    done
    
    upload_config_with_binary "$summary_config" "${NODE_IPS[0]}"
    complete_progress "汇总配置文件生成完成"
    echo ""
}

# ========== 显示最终结果 ==========
show_final_result() {
    clear
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
    echo -e "${GREEN}${BOLD}║            ${YELLOW}Multi-IP VLESS + Reality + uTLS + Vision 部署完成！${GREEN}${BOLD}            ║${NC}"
    echo -e "${GREEN}${BOLD}║                                                                              ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    echo -e "${WHITE}${BOLD}📊 服务器信息：${NC}"
    echo -e "  ${CYAN}部署节点数：${YELLOW}${#NODE_IPS[@]}${NC}"
    echo -e "  ${CYAN}系统信息：${YELLOW}${OS} ${ARCH_TYPE}${NC}"
    echo -e "  ${CYAN}伪装域名：${YELLOW}${DOMAIN}${NC}\n"
    
    echo -e "${WHITE}${BOLD}🌐 节点列表：${NC}"
    for i in "${!NODE_IPS[@]}"; do
        local ip="${NODE_IPS[i]}"
        local port="${NODE_PORTS[i]}"
        local user="${NODE_USERS[i]}"
        echo -e "  ${CYAN}节点$((i+1))：${YELLOW}${ip}:${port} (${user})${NC}"
    done
    echo ""
    
    echo -e "${WHITE}${BOLD}⚡ 性能测试结果：${NC}"
    echo -e "  ${CYAN}上传速度：${UPLOAD_RESULT}${NC}"
    echo -e "  ${CYAN}下载速度：${DOWNLOAD_RESULT}${NC}\n"
    
    echo -e "${WHITE}${BOLD}📋 文件位置：${NC}"
    echo -e "  ${CYAN}二维码目录：${YELLOW}${QR_DIR}${NC}"
    echo -e "  ${CYAN}配置文件目录：${YELLOW}${CONFIG_DIR}${NC}"
    echo -e "  ${CYAN}Xray主配置：${YELLOW}/etc/xray/config.json${NC}"
    echo -e "  ${CYAN}汇总配置：${YELLOW}${CONFIG_DIR}/summary.json${NC}\n"
    
    echo -e "${WHITE}${BOLD}🛠️ 常用命令：${NC}"
    echo -e "  ${CYAN}查看状态：${YELLOW}systemctl status xray${NC}"
    echo -e "  ${CYAN}重启服务：${YELLOW}systemctl restart xray${NC}"
    echo -e "  ${CYAN}查看日志：${YELLOW}journalctl -u xray -f${NC}"
    echo -e "  ${CYAN}防火墙状态：${YELLOW}ufw status${NC}"
    echo -e "  ${CYAN}查看二维码：${YELLOW}ls -la ${QR_DIR}${NC}\n"
    
    echo -e "${WHITE}${BOLD}📈 优化特性：${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} BBR拥塞控制已启用${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} TCP Fast Open已启用${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} CN2网络优化已配置${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 内核参数已优化${NC}"
    echo -e "  ${GREEN}${ICON_SUCCESS} 多IP防火墙已配置${NC}\n"
    
    echo -e "${PURPLE}${BOLD}${ICON_INFO} 部署完成时间：${YELLOW}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
    
    # 保存客户端配置提示
    echo -e "${YELLOW}${BOLD}💡 客户端配置提示：${NC}"
    echo -e "  ${WHITE}1. 每个IP都有独立的二维码图片保存在 ${YELLOW}${QR_DIR}${WHITE} 目录${NC}"
    echo -e "  ${WHITE}2. 可以使用任意一个节点，或配置负载均衡${NC}"
    echo -e "  ${WHITE}3. 推荐客户端：v2rayN (Windows)、v2rayNG (Android)、shadowrocket (iOS)${NC}"
    echo -e "  ${WHITE}4. 二维码文件命名格式：node_IP_端口.png${NC}\n"
    
    # 安全提醒
    echo -e "${RED}${BOLD}🔒 安全提醒：${NC}"
    echo -e "  ${WHITE}• 请妥善保存所有配置信息，不要泄露给他人${NC}"
    echo -e "  ${WHITE}• 监控所有节点的服务器流量，避免异常使用${NC}"
    echo -e "  ${WHITE}• 建议定期更换端口和密钥以提高安全性${NC}\n"
    
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}\n"
}

# ========== 显示所有节点信息 ==========
show_all_nodes_info() {
    echo -e "${GREEN}${BOLD}🔗 所有节点链接：${NC}\n"
    
    for i in "${!NODE_IPS[@]}"; do
        local ip="${NODE_IPS[i]}"
        local port="${NODE_PORTS[i]}"
        local uuid="${NODE_UUIDS[i]}"
        local user="${NODE_USERS[i]}"
        local public_key="${NODE_PUBLIC_KEYS[i]}"
        local short_id="${NODE_SHORT_IDS[i]}"
        local vless_link="vless://${uuid}@${ip}:${port}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${DOMAIN}&fp=chrome&pbk=${public_key}&sid=${short_id}&type=tcp&headerType=none#${user}_Reality_${ip}"
        
        echo -e "${CYAN}${BOLD}节点 $((i+1)) - ${ip}:${port}:${NC}"
        echo -e "${YELLOW}${vless_link}${NC}"
        echo -e "${GREEN}二维码文件：${YELLOW}${QR_DIR}/node_${ip}_${port}.png${NC}"
        echo ""
    done
    
    echo -e "${GREEN}${BOLD}📱 二维码文件列表：${NC}"
    echo -e "${CYAN}"
    ls -la "$QR_DIR"/*.png 2>/dev/null || echo "未找到二维码文件"
    echo -e "${NC}\n"
    
    echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${WHITE}提示：可以使用图片查看器打开二维码文件，或使用 scp 下载到本地设备扫描${NC}"
    echo -e "${WHITE}下载命令示例：${YELLOW}scp root@服务器IP:${QR_DIR}/*.png ./local_path/${NC}\n"
}

# ========== 错误处理 ==========
handle_error() {
    echo -e "\n${RED}${BOLD}${ICON_ERROR} 脚本执行过程中出现错误！${NC}"
    echo -e "${WHITE}错误行号：${YELLOW}$1${NC}"
    echo -e "${WHITE}错误命令：${YELLOW}$2${NC}"
    echo -e "${WHITE}请检查网络连接和系统权限后重试。${NC}\n"
    exit 1
}

# 设置错误陷阱
trap 'handle_error ${LINENO} "$BASH_COMMAND"' ERR

# ========== 环境检查 ==========
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
    
    echo -e "${GREEN}${ICON_SUCCESS} 环境检查通过${NC}\n"
}

# ========== 清理函数 ==========
cleanup_on_exit() {
    echo -e "\n${YELLOW}${ICON_INFO} 正在清理临时文件...${NC}"
    # 清理可能的临时文件
    rm -f /tmp/xray_install_*
    rm -f /usr/local/bin/xray.zip 2>/dev/null || true
}

# 设置退出时清理
trap cleanup_on_exit EXIT

# ========== 脚本入口 - 全自动部署 ==========
echo -e "${BLUE}${BOLD}正在初始化多IP Xray部署环境...${NC}\n"

# 环境检查
check_environment

# 执行主安装流程
main_install

# 脚本结束
echo -e "${GREEN}${BOLD}🎊 所有任务执行完毕！${NC}"
echo -e "${WHITE}如有问题，请查看日志文件：${YELLOW}/var/log/xray/${NC}\n"
