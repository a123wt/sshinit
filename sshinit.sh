#!/bin/bash

# 默认配置
admin_username="admin"
ssh_public_key="ssh_public_key"
max_password_attempts=6
unlock_time=3600
max_ssh_attempts=6

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
            sudo id "$admin_username"
            sudo passwd "$admin_username"
        else
            # 用户不存在，创建用户并设置密码
            echo "创建用户 $admin_username 并设置密码"
            sudo useradd -m -s /bin/bash "$admin_username"
            sudo passwd "$admin_username"
        fi
        ;;
    2)
        echo "为 root 用户配置 ssh 公钥"
        read -p "请输入要添加的 SSH 公钥: " ssh_public_key
        # 创建或追加 root 用户的 SSH 公钥
        root_authorized_keys="/root/.ssh/authorized_keys"
        if [ -f "$root_authorized_keys" ]; then
            # 检查是否已存在相同的公钥
            if ! sudo grep -q "$ssh_public_key" "$root_authorized_keys"; then
                # 追加新的公钥
                echo "$ssh_public_key" | sudo tee -a "$root_authorized_keys" >/dev/null
                echo "已成功追加 SSH 公钥到 root 用户"
            else
                echo "SSH 公钥已存在于 root 用户的授权密钥文件中"
            fi
        else
            # 检查是否存在.ssh路径
            if [ ! -d "/root/.ssh" ];then
                sudo mkdir "/root/.ssh"
            fi

            # 创建新的文件并写入公钥
            echo "$ssh_public_key" | sudo tee "$root_authorized_keys" >/dev/null
            sudo chown root:root "$root_authorized_keys"
            sudo chmod 600 "$root_authorized_keys"
            echo "已成功创建 SSH 公钥文件并写入到 root 用户"
            sudo grep "$ssh_public_key" "$root_authorized_keys"
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
            if ! sudo grep -q "$ssh_public_key" "$admin_authorized_keys"; then
                # 追加新的公钥
                echo "$ssh_public_key" | sudo tee -a "$admin_authorized_keys" >/dev/null
                echo "已成功追加 SSH 公钥到 admin 用户"
            else
                echo "SSH 公钥已存在于 admin 用户的授权密钥文件中"
            fi
        else
            # 检查是否存在.ssh路径
            if [ ! -d "/home/$admin_username/.ssh" ];then
                sudo mkdir "/home/$admin_username/.ssh"
            fi

            # 创建新的文件并写入公钥
            echo "$ssh_public_key" | sudo tee "$admin_authorized_keys" >/dev/null
            sudo chown "$admin_username:$admin_username" "$admin_authorized_keys"
            sudo chmod 600 "$admin_authorized_keys"
            echo "已成功创建 SSH 公钥文件并写入到 admin 用户"
            sudo grep "$ssh_public_key" "$admin_authorized_keys"
        fi
        ;;
    4)
        # 配置 root 用户仅通过密钥登录 SSH
        echo "查找 /etc/ssh/sshd_config 中相关配置："
        if sudo grep  "^PermitRootLogin" /etc/ssh/sshd_config; then
            sudo sed -i "/^PermitRootLogin/c\PermitRootLogin without-password # 禁止root用户通过口令" /etc/ssh/sshd_config
            echo "已成功配置 root 用户仅通过密钥登录 SSH, 重启sshd生效"
            sudo grep "^PermitRootLogin" /etc/ssh/sshd_config
        elif sudo grep  "^#PermitRootLogin" /etc/ssh/sshd_config; then
            sudo sed -i "/^#PermitRootLogin/c\PermitRootLogin without-password # 禁止root用户通过口令" /etc/ssh/sshd_config
            echo "已成功配置 root 用户仅通过密钥登录 SSH, 重启sshd生效"
            sudo grep "^PermitRootLogin" /etc/ssh/sshd_config
        else
            echo "未在/etc/ssh/sshd_config 中找到对应配置, 请手动完成"
        fi
        ;;
    5)
        # 配置 fail2ban 最大口令尝试次数
        # 检查是否安装 fail2ban
        if sudo systemctl status fail2ban &> /dev/null; then  
            echo "fail2ban 已安装"
            echo "使用 fail2ban-client status 或 fail2ban-client status sshd 查看状态"

        else  
            echo "fail2ban 未安装"
            echo "正在运行sudo apt-get update 和 sudo apt-get install -y fail2ban, 若长时间无响应请手动安装"
            sudo apt-get update &> /dev/null
            sudo apt-get install -y fail2ban &> /dev/null
            if sudo systemctl status fail2ban |grep "active (running)" &> /dev/null; then
                echo "fail2ban 运行成功"
                echo "使用 fail2ban-client status 或 fail2ban-client status sshd 查看状态"
            else
                echo "fail2ban 安装或启动失败"
                exit 1
            fi
        fi

        # read -p "请输入 fail2ban 最大口令尝试次数 (默认: $max_password_attempts): " input_max_password_attempts
        # max_password_attempts="${input_max_password_attempts:-$max_password_attempts}"
        # read -p "请输入 fail2ban 失败锁定时间 (默认: $unlock_time 秒): " input_unlock_time
        # unlock_time="${input_unlock_time:-$unlock_time}"

        # # 配置 fail2ban 最大口令尝试次数
        # sed -i "/^maxretry/c\bantime =$max_password_attempts" /etc/fail2ban/jail.conf
        # sed -i "/^bantime/c\bantime =$unlock_time" /etc/fail2ban/jail.conf
        # echo "已成功配置fail2ban最大口令尝试次数"
        # sudo grep  "^maxretry" /etc/fail2ban/jail.conf
        # sudo grep  "^bantime" /etc/fail2ban/jail.conf
        ;;
    6)
        # 配置 PAM 最大口令尝试次数
        echo "不推荐, 会拒绝全局登录而非根据IP识别, Ctrl C 退出"
        read -p "请输入 PAM 最大口令尝试次数 (默认: $max_password_attempts): " input_max_password_attempts
        max_password_attempts="${input_max_password_attempts:-$max_password_attempts}"
        read -p "请输入 PAM 失败锁定时间 (默认: $unlock_time 秒): " input_unlock_time
        unlock_time="${input_unlock_time:-$unlock_time}"

        # 配置 PAM 最大口令尝试次数
        echo "查找 /etc/pam.d/common-auth 中相关配置："
        if sudo grep  "^auth required pam_tally2.so " /etc/pam.d/common-auth; then
            echo "已存在最大口令尝试次数配置, 如需更改请手动编辑 /etc/pam.d/common-auth"
        elif sudo grep  "# here are the per-package modules" /etc/pam.d/common-auth; then
            sudo sed -i "/# here are the per-package modules/a\auth required pam_tally2.so onerr=fail deny=$max_password_attempts unlock_time=$unlock_time  even_deny_root root_unlock_time=$unlock_time # 设置最大口令尝试次数" /etc/pam.d/common-auth
            echo "已成功配置 PAM 最大口令尝试次数"
            sudo grep "auth required pam_tally2.so " /etc/pam.d/common-auth
        else
            echo "未在/etc/pam.d/common-auth 中找到对应配置, 请手动完成"
        fi
        ;;
        
    7)
        # 配置 SSH 最大口令尝试次数
        echo "不推荐, 会拒绝全局登录而非根据IP识别, Ctrl C 退出"
        read -p "请输入 SSH 最大口令尝试次数 (默认: $max_ssh_attempts): " input_max_ssh_attempts
        max_ssh_attempts="${input_max_ssh_attempts:-$max_ssh_attempts}"
        
        # 配置 SSH 最大口令尝试次数
        if sudo grep "^MaxAuthTries" /etc/ssh/sshd_config; then
            echo "已存在最大口令尝试次数配置, 如需更改请手动编辑 /etc/ssh/sshd_config"
        else
            echo "MaxAuthTries $max_ssh_attempts  # 设置SSH最大口令尝试次数" | sudo tee -a /etc/ssh/sshd_config >/dev/null
            echo "已成功配置 SSH 最大口令尝试次数"
            sudo grep "^MaxAuthTries" /etc/ssh/sshd_config
        fi
        ;;
    *)
        echo "无效的选择"
        ;;
esac