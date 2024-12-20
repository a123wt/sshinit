#!/bin/bash

# 默认配置
admin_username="admin"
ssh_public_key="ssh_public_key"
max_password_attempts=6
unlock_time=3600
max_ssh_attempts=6

# 检测是否是 root 用户
is_root=false
if [ "$EUID" -eq 0 ]; then
    is_root=true
fi

function run_command() {
    if $is_root; then
        "$@"
    else
        sudo "$@"
    fi
}

echo "ubuntu ssh 快捷配置"
# 检查是否以sudo身份运行脚本
if [ "$EUID" -ne 0 ]; then
    echo "请以sudo权限运行此脚本"
    exit 1
fi

# 显示菜单并接收用户选择
echo "请选择要执行的操作:"
echo "1. 修改或创建 admin 用户"
echo "2. 为 root 用户配置 ssh 公钥"
echo "3. 为 admin 用户配置 ssh 公钥"
echo "4. 配置 root 用户仅通过密钥登录 SSH"
echo "5. 防暴力破解, 通过 fail2ban"
echo "5.1 增加配置并重启 fail2ban"
echo "6. 防暴力破解, 通过 PAM(不推荐)"
echo "7. 防暴力破解, 通过 SSH(不推荐)"

read choice

# 处理用户选择
case $choice in
    1)
        read -p "请输入 admin 用户名 (默认: $admin_username): " input_admin_username
        admin_username="${input_admin_username:-$admin_username}"
        
        # 修改或创建 admin 用户
        if id "$admin_username" &>/dev/null; then
            # 用户已存在，只修改密码
            echo "用户 $admin_username 已存在，仅修改密码"
            run_command id "$admin_username"
            run_command passwd "$admin_username"
        else
            # 用户不存在，创建用户并设置密码
            echo "创建用户 $admin_username 并设置密码"
            run_command useradd -m -s /bin/bash "$admin_username"
            run_command passwd "$admin_username"
        fi
        ;;
    2)
        echo "为 root 用户配置 ssh 公钥"
        read -p "请输入要添加的 SSH 公钥: " ssh_public_key
        # 创建或追加 root 用户的 SSH 公钥
        root_authorized_keys="/root/.ssh/authorized_keys"
        if [ -f "$root_authorized_keys" ]; then
            # 检查是否已存在相同的公钥
            if ! grep -q "$ssh_public_key" "$root_authorized_keys"; then
                # 追加新的公钥
                echo "$ssh_public_key" | run_command tee -a "$root_authorized_keys" >/dev/null
                echo "已成功追加 SSH 公钥到 root 用户"
            else
                echo "SSH 公钥已存在于 root 用户的授权密钥文件中"
            fi
        else
            # 检查是否存在.ssh路径
            if [ ! -d "/root/.ssh" ]; then
                run_command mkdir "/root/.ssh"
            fi

            # 创建新的文件并写入公钥
            echo "$ssh_public_key" | run_command tee "$root_authorized_keys" >/dev/null
            run_command chown root:root "$root_authorized_keys"
            run_command chmod 600 "$root_authorized_keys"
            echo "已成功创建 SSH 公钥文件并写入到 root 用户"
        fi
        ;;
    3)
        echo "为 admin 用户配置 ssh 公钥"

        # 输入要配置的用户名
        read -p "请输入 admin 用户名 (默认: $admin_username): " input_admin_username
        admin_username="${input_admin_username:-$admin_username}"
        if ! id "$admin_username" &>/dev/null; then
            echo "用户 $admin_username 不存在"
            exit 1
        fi
        
        read -p "请输入要添加的 SSH 公钥: " ssh_public_key
        # 创建或追加 admin 用户的 SSH 公钥
        admin_authorized_keys="/home/$admin_username/.ssh/authorized_keys"
        if [ -f "$admin_authorized_keys" ]; then
            # 检查是否已存在相同的公钥
            if ! grep -q "$ssh_public_key" "$admin_authorized_keys"; then
                # 追加新的公钥
                echo "$ssh_public_key" | run_command tee -a "$admin_authorized_keys" >/dev/null
                echo "已成功追加 SSH 公钥到 admin 用户"
            else
                echo "SSH 公钥已存在于 admin 用户的授权密钥文件中"
            fi
        else
            # 检查是否存在.ssh路径
            if [ ! -d "/home/$admin_username/.ssh" ]; then
                run_command mkdir "/home/$admin_username/.ssh"
            fi

            # 创建新的文件并写入公钥
            echo "$ssh_public_key" | run_command tee "$admin_authorized_keys" >/dev/null
            run_command chown "$admin_username:$admin_username" "$admin_authorized_keys"
            run_command chmod 600 "$admin_authorized_keys"
            echo "已成功创建 SSH 公钥文件并写入到 admin 用户"
        fi
        ;;
    4)
        echo "配置 root 用户仅通过密钥登录 SSH"
        ssh_config="/etc/ssh/sshd_config"
        if grep -q "^PermitRootLogin" "$ssh_config"; then
            run_command sed -i "/^PermitRootLogin/c\\PermitRootLogin without-password # 禁止root用户通过口令" "$ssh_config"
        else
            echo "PermitRootLogin without-password" | run_command tee -a "$ssh_config" >/dev/null
        fi
        echo "已成功配置 root 用户仅通过密钥登录 SSH, 重启sshd生效"
        ;;
    5)
        echo "配置 fail2ban 最大口令尝试次数"
        if run_command systemctl status fail2ban &>/dev/null; then
            echo "fail2ban 已安装"
            echo "启动 fail2ban 服务"
            run_command systemctl start fail2ban
        else
            echo "安装 fail2ban"
            run_command apt-get update && run_command apt-get install -y fail2ban
            run_command systemctl start fail2ban
        fi
        ;;
    5.1)
        echo "增加配置并重启 fail2ban"
        fail2ban_config="/etc/fail2ban/jail.local"
        echo "[DEFAULT]" | run_command tee "$fail2ban_config" >/dev/null
        echo "bantime = 3600" | run_command tee -a "$fail2ban_config" >/dev/null
        echo "findtime = 600" | run_command tee -a "$fail2ban_config" >/dev/null
        echo "maxretry = 5" | run_command tee -a "$fail2ban_config" >/dev/null
        echo "[sshd]" | run_command tee -a "$fail2ban_config" >/dev/null
        echo "enabled = true" | run_command tee -a "$fail2ban_config" >/dev/null
        echo "配置完成，重启 fail2ban 服务"
        run_command systemctl restart fail2ban
        ;;
    6)
        echo "配置 PAM 最大口令尝试次数"
        read -p "请输入 PAM 最大口令尝试次数 (默认: $max_password_attempts): " input_max_password_attempts
        max_password_attempts="${input_max_password_attempts:-$max_password_attempts}"
        read -p "请输入 PAM 失败锁定时间 (默认: $unlock_time 秒): " input_unlock_time
        unlock_time="${input_unlock_time:-$unlock_time}"

        if grep -q "pam_tally2.so" /etc/pam.d/common-auth; then
            echo "PAM 配置已存在"
        else
            echo "auth required pam_tally2.so onerr=fail deny=$max_password_attempts unlock_time=$unlock_time" | run_command tee -a /etc/pam.d/common-auth >/dev/null
        fi
        ;;
    7)
        echo "配置 SSH 最大口令尝试次数"
        read -p "请输入 SSH 最大口令尝试次数 (默认: $max_ssh_attempts): " input_max_ssh_attempts
        max_ssh_attempts="${input_max_ssh_attempts:-$max_ssh_attempts}"

        if grep -q "^MaxAuthTries" "$ssh_config"; then
            echo "SSH 配置已存在"
        else
            echo "MaxAuthTries $max_ssh_attempts" | run_command tee -a "$ssh_config" >/dev/null
        fi
        ;;
    *)
        echo "无效的选择"
        ;;
esac
