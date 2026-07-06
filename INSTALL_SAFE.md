# VPS 一键部署安全安装文档

本文档适用于本仓库的安全版脚本：

```text
https://github.com/huzhirong03/vps_auto_Install
```

本仓库已经禁用原脚本中的 `transfer` 配置上传流程。请不要再使用原作者 `diandongyun/node` 的 raw 链接。

## 1. 新系统基础检查

SSH 登录 VPS 后，先确认系统状态：

```bash
uptime
who -b
cloud-init status
ip a
```

检查是否存在旧的上传程序或旧节点服务：

```bash
ls -l /opt/transfer /usr/local/bin/transfer 2>/dev/null
systemctl list-units --type=service --all | grep -Ei 'xray|hysteria|tuic|wireguard|wg-quick|transfer'
ls -ld /etc/xray /etc/hysteria /etc/tuic /etc/wireguard 2>/dev/null
```

正常的新系统通常不会输出 `transfer` 文件，也不会有旧的 `xray`、`hysteria`、`tuic`、`wireguard` 服务。

## 2. 更新系统组件

推荐新系统先执行：

```bash
apt update
apt upgrade -y
apt install -y curl wget sudo ca-certificates gnupg lsb-release
reboot
```

如果系统提示是否替换 `/etc/cloud/cloud.cfg`，建议选择默认值 `N`，保留云厂商当前配置。

重启后重新 SSH 登录。

如果只想快速部署，至少执行：

```bash
apt update
apt install -y curl wget sudo ca-certificates
```

## 3. 运行安全版一键部署脚本

Hysteria2：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/huzhirong03/vps_auto_Install/main/hysteria2.sh)
```

TUIC：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/huzhirong03/vps_auto_Install/main/tuic.sh)
```

VLESS Reality：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/huzhirong03/vps_auto_Install/main/vless.sh)
```

VLESS Reality 多 IP：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/huzhirong03/vps_auto_Install/main/vless-plus.sh)
```

WireGuard：

```bash
bash <(curl -Ls https://raw.githubusercontent.com/huzhirong03/vps_auto_Install/main/wireguard.sh)
```

## 4. 部署前检查脚本来源

运行前可以先检查 raw 脚本内容是否来自你的仓库，并确认没有 JsonBin 标记：

```bash
curl -Ls https://raw.githubusercontent.com/huzhirong03/vps_auto_Install/main/vless.sh | grep -Ei 'transfer upload disabled|jsonbin|X-Access-Key|X-Bin-Private|diandongyun'
```

安全版应出现 `transfer upload disabled`，不应出现 `jsonbin`、`X-Access-Key`、`X-Bin-Private`。

## 5. 部署后安全检查

部署完成后，检查是否下载了 `transfer`：

```bash
ls -l /opt/transfer /usr/local/bin/transfer 2>/dev/null
```

没有任何输出是正常结果。

检查是否存在 JsonBin 上传相关标记：

```bash
grep -R "jsonbin\|X-Access-Key\|X-Bin-Private" /etc /opt /usr/local/bin 2>/dev/null
```

没有任何输出是正常结果。

检查相关服务状态：

```bash
systemctl list-units --type=service --all | grep -Ei 'xray|hysteria|tuic|wireguard|wg-quick'
```

根据你部署的协议，应该只看到对应服务。例如 VLESS 通常是 `xray`。

## 6. 如果发现 transfer 文件

如果下面命令发现文件存在：

```bash
ls -l /opt/transfer /usr/local/bin/transfer 2>/dev/null
```

例如输出：

```text
/usr/local/bin/transfer
```

说明这台机器可能运行过原始上传脚本。最稳妥的处理是重装系统。

临时删除命令：

```bash
rm -f /opt/transfer /usr/local/bin/transfer
```

但仅删除文件不能证明机器完全干净。如果该文件曾以 root 权限运行过，建议直接重装 VPS，然后只运行本仓库的安全版脚本。

## 7. 常用排查命令

查看 Xray 日志：

```bash
journalctl -u xray -n 100 --no-pager
tail -n 100 /var/log/xray/error.log 2>/dev/null
```

查看 Hysteria2 日志：

```bash
journalctl -u hysteria-server -n 100 --no-pager
```

查看 TUIC 日志：

```bash
journalctl -u tuic -n 100 --no-pager
```

查看 WireGuard 状态：

```bash
wg show
systemctl status wg-quick@wg0 --no-pager
```

查看防火墙：

```bash
ufw status
```
