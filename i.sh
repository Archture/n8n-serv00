#!/bin/bash
set -e

USER_HOME="/home/$(whoami)"
PROFILE="$USER_HOME/.bash_profile"

# 推荐的兼容版本列表（避开 zod 冲突）
declare -A N8N_VERSIONS=(
    ["1"]="1.56.2"  # 最稳定，内存占用最小
    ["2"]="1.58.0"  # 平衡版本
    ["3"]="1.60.1"  # 较新功能
    ["4"]="custom"  # 自定义版本
)

# 颜色输出函数
log() {
    echo -e "\033[32m[INFO] $1\033[0m"
}

error() {
    echo -e "\033[31m[ERROR] $1\033[0m"
    exit 1
}

warn() {
    echo -e "\033[33m[WARN] $1\033[0m"
}

# 选择 N8N 版本
select_n8n_version() {
    log "=== 选择 N8N 版本 ==="
    log "Serv00 RAM: 512MB，建议使用较低版本以确保稳定运行"
    echo ""
    log "推荐版本（已验证兼容性）："
    log "1) v${N8N_VERSIONS[1]} - 最稳定，内存占用最小（强烈推荐）"
    log "2) v${N8N_VERSIONS[2]} - 平衡版本"
    log "3) v${N8N_VERSIONS[3]} - 较新功能"
    log "4) 自定义版本（高级用户）"
    echo ""
    
    while true; do
        read -r -p "请选择版本 [1-4，默认1]: " version_choice
        version_choice=${version_choice:-1}
        
        case $version_choice in
            1|2|3)
                N8N_VERSION="${N8N_VERSIONS[$version_choice]}"
                log "已选择 N8N v${N8N_VERSION}"
                break
                ;;
            4)
                read -r -p "请输入 N8N 版本号（如 1.56.2）: " custom_version
                if [[ $custom_version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                    N8N_VERSION="$custom_version"
                    warn "自定义版本可能存在兼容性问题，建议使用推荐版本"
                    break
                else
                    warn "版本号格式错误，请重新输入"
                fi
                ;;
            *)
                warn "请输入 1-4 之间的数字"
                ;;
        esac
    done
}

set_url() {
    local username
    username=$(whoami)
    read -r -p "是否使用默认的 ${username}.serv00.net 作为 WEBHOOK_URL? [Y/n] " yn
    case $yn in
        [Yy]* | "" ) WEBHOOK_URL="${username}.serv00.net";;
        [Nn]* ) 
            read -r -p "请输入 WEBHOOK_URL: " WEBHOOK_URL
            if [[ ! $WEBHOOK_URL =~ ^https?:// ]]; then
                error "URL 格式错误，必须以 http:// 或 https:// 开头"
            fi
            ;;
    esac
    log "WEBHOOK_URL 设置为: ${WEBHOOK_URL}"
}

set_www() {
    log "重置网站..."
    log "删除网站 ${WEBHOOK_URL}"
    devil www del "${WEBHOOK_URL}" 2>/dev/null || true
    ADD_WWW_OUTPUT=$(devil www add "${WEBHOOK_URL}" proxy localhost "$N8N_PORT")
    if echo "$ADD_WWW_OUTPUT" | grep -q "Domain added succesfully"; then
        log "网站 ${WEBHOOK_URL} 成功重置。"
    else
        warn "新建网站失败，可自行在网页端后台进行设置"
    fi
}

set_port() {
    log "当前可用端口列表："
    devil port list
    
    while true; do
        read -r -p "请输入列表中的端口号 或 输入'add'来新增端口: " N8N_PORT
        if [[ $N8N_PORT == "add" ]]; then
            devil port add tcp random
            log "当前可用端口列表："
            devil port list
            read -r -p "请输入新增端口号(必须在列表中): " N8N_PORT
            break
        elif [[ $N8N_PORT =~ ^[0-9]+$ ]] && [ "$N8N_PORT" -ge 1024 ] && [ "$N8N_PORT" -le 65535 ]; then
            if devil port list | grep -q "^$N8N_PORT"; then
                break
            else
                error "端口 $N8N_PORT 不在可用端口列表中"
            fi
        else
            warn "请输入有效的端口号(1024-65535)或'add'"
        fi
    done
    log "N8N_PORT 设置为: ${N8N_PORT}"
}

set_db() {
    log "数据库配置..."
    log "1) SQLite (推荐，内存占用最小)"
    log "2) PostgreSQL (功能更多，但占用更多内存)"
    
    while true; do
        read -r -p "请选择数据库类型 [1/2，默认1]: " db_choice
        db_choice=${db_choice:-1}
        case $db_choice in
            1)
                DB_TYPE=sqlite
                log "已选择 SQLite 数据库（最优选择）"
                break
                ;;
            2)
                DB_TYPE=postgresdb
                warn "PostgreSQL 会占用更多内存，512MB RAM 可能不够用"
                read -r -p "确认继续使用 PostgreSQL? [y/N] " confirm
                case $confirm in
                    [Yy]* )
                        set_postgres
                        break
                        ;;
                    *)
                        log "已切换到 SQLite"
                        DB_TYPE=sqlite
                        break
                        ;;
                esac
                ;;
            *)
                warn "请输入 1 或 2"
                ;;
        esac
    done
}

set_postgres() {
    log "配置 PostgreSQL 数据库..."
    
    log "当前数据库列表："
    devil pgsql list
    
    read -r -p "是否使用已有数据库? [Y/n] " yn
    case $yn in
        [Yy]* | "" ) 
            log "使用已有数据库"
            warn "请自行修改 $PROFILE 文件中的数据库配置"
            return;;
        [Nn]* ) 
            while true; do
                read -r -p "请输入新的数据库名称（仅允许字母、数字和下划线）: " DATABASE_NAME
                if [[ $DATABASE_NAME =~ ^[a-zA-Z0-9_]+$ ]]; then
                    break
                else
                    warn "数据库名称只能包含字母、数字和下划线"
                fi
            done
            ;;
    esac
    
    log "创建数据库: ${DATABASE_NAME}..."
    devil pgsql db del "${DATABASE_NAME}" 2>/dev/null || true
    
    log "请在接下来的提示中输入数据库密码: 8位以上要有大小写、数字及特殊字符"
    DB_INFO=$(devil pgsql db add "${DATABASE_NAME}")
    
    DB_Database=$(echo "$DB_INFO" | grep "Database:" | sed 's/^[[:space:]]*Database:[[:space:]]*\(.*\)[[:space:]]*$/\1/')
    DB_HOST=$(echo "$DB_INFO" | grep "Host:" | sed 's/^[[:space:]]*Host:[[:space:]]*\(.*\)[[:space:]]*$/\1/')
    
    if [[ -z "$DB_Database" || -z "$DB_HOST" ]]; then
        DB_Database=$(echo "$DB_INFO" | grep -o 'p[0-9]*_[a-zA-Z0-9_]*')
        DB_HOST=$(echo "$DB_INFO" | grep -o 'pgsql[0-9]*\.serv00\.com')
        
        if [[ -z "$DB_Database" || -z "$DB_HOST" ]]; then
            error "无法获取数据库信息，请检查输出并手动设置环境变量"
        fi
    fi
    
    read -r -p "请再输入一次刚才设置的数据库密码: " DB_PASSWORD

    DB_User="${DB_Database}"
    log "数据库信息："
    log "DB_User: ${DB_User}"
    log "DB_Database: ${DB_Database}"
    log "DB_Host: ${DB_HOST}"
    
    log "配置数据库扩展..."
    for ext in pgcrypto pg_trgm; do
        devil pgsql extensions "${DB_Database}" "$ext" || warn "扩展 $ext 配置失败"
    done
    
    if ! PGPASSWORD="${DB_PASSWORD}" psql -h "${DB_HOST}" -U "${DB_User}" -d "${DB_Database}" -c '\q' >/dev/null 2>&1; then
        warn "数据库连接测试失败，请检查数据库配置"
        devil pgsql db list
        exit 1
    fi
    unset PGPASSWORD
}

# 更新环境配置
update_profile() {
    if ! grep -q "^export PATH=.*\.npm-global/bin" "$PROFILE"; then
        echo "export PATH=\"\$HOME/.npm-global/bin:\$HOME/bin:\$PATH\"" >> "$PROFILE"
    fi
    
    cat << EOF >> "$PROFILE"

# N8N 配置 (优化版)
export N8N_PORT=${N8N_PORT}
export WEBHOOK_URL="https://${WEBHOOK_URL}"
export N8N_HOST=0.0.0.0
export N8N_PROTOCOL=https
export GENERIC_TIMEZONE=Asia/Shanghai
export N8N_SECURE_COOKIE=false
export N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN=true

# 性能优化配置
export N8N_METRICS=false
export N8N_DIAGNOSTICS_ENABLED=false
export QUEUE_HEALTH_CHECK_ACTIVE=false
export N8N_PAYLOAD_SIZE_MAX=32
export EXECUTIONS_DATA_PRUNE=true
export EXECUTIONS_DATA_MAX_AGE=168

# 数据库配置
export DB_TYPE=${DB_TYPE}
EOF

    if [[ $DB_TYPE == "postgresdb" ]]; then
        cat << EOF >> "$PROFILE"
export DB_POSTGRESDB_HOST=${DB_HOST}
export DB_POSTGRESDB_PORT=5432
export DB_POSTGRESDB_USER=${DB_User}
export DB_POSTGRESDB_PASSWORD=${DB_PASSWORD}
export DB_POSTGRESDB_DATABASE=${DB_Database}
EOF
    fi
    
    cat << EOF >> "$PROFILE"

# 用户文件夹
export N8N_USER_FOLDER=${USER_HOME}/n8n-serv00/n8n
export N8N_ENCRYPTION_KEY="n8n8n8n"

# 允许使用内置模块
export NODE_FUNCTION_ALLOW_BUILTIN=*
export NODE_FUNCTION_ALLOW_EXTERNAL=*

# 内存限制 (关键优化)
export NODE_OPTIONS="--max-old-space-size=256"
export UV_THREADPOOL_SIZE=2

EOF
    log "环境变量配置已更新"
}

re_source() {
    if [[ -f "$PROFILE" ]]; then
        source "$PROFILE"
    fi
    if [[ -f "$USER_HOME/.bashrc" ]]; then
        source "$USER_HOME/.bashrc"
    fi
    log "环境变量已重新加载"
}

create_log_dir() {
    if [[ ! -d "${USER_HOME}/n8n-serv00/n8n/logs" ]]; then
        mkdir -p "${USER_HOME}/n8n-serv00/n8n/logs"
    fi
}

install_pnpm() {
    mkdir -p "$USER_HOME/.npm-global" "$USER_HOME/bin"
    
    log "配置 npm..."
    npm config set prefix "$USER_HOME/.npm-global"
    ln -fs /usr/local/bin/node20 "$USER_HOME/bin/node"
    ln -fs /usr/local/bin/npm20 "$USER_HOME/bin/npm"
    
    echo "export PATH=\"\$HOME/.npm-global/bin:\$HOME/bin:\$PATH\"" >> "$PROFILE"
    re_source
    
    log "安装 pnpm..."
    rm -rf "$USER_HOME/.local/share/pnpm"
    rm -rf "$USER_HOME/.npm-global/lib/node_modules/pnpm"
    
    # 使用较低版本的 pnpm 以减少内存占用
    npm install -g pnpm@8.15.0 || error "pnpm 安装失败"
    
    pnpm setup
    
    if ! grep -q "PNPM_HOME" "$PROFILE"; then
        echo "export PNPM_HOME=\"\$HOME/.local/share/pnpm\"" >> "$PROFILE"
        echo "export PATH=\"\$PNPM_HOME:\$PATH\"" >> "$PROFILE"
    fi
    re_source
}

# 优化的 N8N 安装函数
install_n8n_optimized() {
    log "=== 开始安装 N8N v${N8N_VERSION} ==="
    
    # 设置 pnpm 配置
    pnpm config set store-dir "$USER_HOME/.local/share/pnpm/store"
    pnpm config set global-dir "$USER_HOME/.local/share/pnpm/global"
    pnpm config set state-dir "$USER_HOME/.local/share/pnpm/state"
    pnpm config set cache-dir "$USER_HOME/.local/share/pnpm/cache"
    
    # 关键：限制安装时的并发和内存
    pnpm config set network-concurrency 1
    pnpm config set child-concurrency 1
    
    export PNPM_HOME="$USER_HOME/.local/share/pnpm"
    export PATH="$PNPM_HOME:$PATH"
    
    # 设置 Node.js 内存限制（移除无效的 gc-interval 参数）
    export NODE_OPTIONS="--max-old-space-size=384"
    
    log "正在安装 N8N v${N8N_VERSION}..."
    log "这可能需要 5-10 分钟，请耐心等待..."
    
    # 分步安装，减少内存压力
    if pnpm install -g "n8n@${N8N_VERSION}" --reporter=silent --no-optional 2>&1 | tee /tmp/n8n_install.log; then
        log "N8N 安装成功！"
    else
        error "N8N 安装失败，请查看日志: /tmp/n8n_install.log"
    fi
    
    # 验证安装
    if n8n -v >/dev/null 2>&1; then
        log "N8N 版本验证成功: $(n8n -v)"
    else
        warn "N8N 命令验证失败，但可能已安装成功"
    fi
}

check_status() {
    if pgrep -f "n8n start" > /dev/null 2>&1; then
        log "n8n 正在运行"
        return 0
    else
        warn "n8n 未在运行"
        return 1
    fi
}

start_n8n() {
    create_log_dir
    
    if check_status; then
        log "N8N 已在运行中"
        return 0
    fi
    
    log "启动 N8N..."
    
    # 重新加载环境变量确保 PATH 正确
    re_source
    
    # 查找 n8n 可执行文件
    local N8N_BIN=""
    if [[ -f "$USER_HOME/.local/share/pnpm/n8n" ]]; then
        N8N_BIN="$USER_HOME/.local/share/pnpm/n8n"
    elif [[ -f "$USER_HOME/.npm-global/bin/n8n" ]]; then
        N8N_BIN="$USER_HOME/.npm-global/bin/n8n"
    elif command -v n8n >/dev/null 2>&1; then
        N8N_BIN=$(command -v n8n)
    else
        error "无法找到 n8n 执行文件，请检查安装"
    fi
    
    log "N8N 路径: $N8N_BIN"
    
    # 应用内存限制（移除无效的 gc-interval 参数）
    export NODE_OPTIONS="--max-old-space-size=256"
    export UV_THREADPOOL_SIZE=2
    
    # 使用绝对路径启动 n8n
    cd "$USER_HOME" || error "无法切换到用户目录"
    nohup "$N8N_BIN" start >> "${USER_HOME}/n8n-serv00/n8n/logs/n8n.log" 2>&1 &
    
    log "等待 N8N 启动（60秒）..."
    sleep 60
    
    if check_status; then
        log "N8N 启动成功！"
        log "日志文件: ${USER_HOME}/n8n-serv00/n8n/logs/n8n.log"
    else
        warn "N8N 启动失败，显示最后 20 行日志："
        tail -n 20 "${USER_HOME}/n8n-serv00/n8n/logs/n8n.log"
        error "请检查上述日志信息"
    fi
}

stop_n8n() {
    log "停止 N8N..."
    if pgrep -f "n8n" > /dev/null; then
        pkill -f "n8n"
        sleep 3
        if pgrep -f "n8n" > /dev/null; then
            pkill -9 -f "n8n"
        fi
        log "N8N 已停止"
    else
        log "N8N 未在运行"
    fi
}

restart_n8n() {
    stop_n8n
    sleep 2
    start_n8n
}

set_crontab() {
    if crontab -l 2>/dev/null | grep -q "i.sh cronjob"; then
        warn "定时任务已存在，跳过设置"
        return 0
    fi
    
    if ! (crontab -l 2>/dev/null; echo "*/1 * * * * bash $USER_HOME/n8n-serv00/i.sh cronjob") | crontab -; then
        error "设置定时任务失败"
    fi
    log "定时任务已设置"
}

show_completion_message() {
    log "=== 🎉 安装完成 ==="
    log "N8N v${N8N_VERSION} 已成功安装并启动"
    log ""
    log "访问信息："
    log "  地址: https://${WEBHOOK_URL}"
    log "  端口: ${N8N_PORT}"
    log ""
    log "配置信息："
    log "  数据库: ${DB_TYPE}"
    log "  配置文件: $PROFILE"
    log "  日志文件: ${USER_HOME}/n8n-serv00/n8n/logs/n8n.log"
    log ""
    log "⚠️  重要提示："
    warn "1. 请运行以下命令使环境变量生效："
    warn "   source ~/.bash_profile && source ~/.bashrc"
    warn ""
    warn "2. 内存优化已启用，如遇问题请查看日志"
    warn ""
    log "详细使用方法请参考项目 README.md"
}

uninstall_old_n8n() {
    if ! n8n -v > /dev/null 2>&1; then
        if [[ -f "./uninstall.sh" ]]; then
            bash ./uninstall.sh
        fi
    else
        warn "检测到旧版本 N8N"
        read -r -p "是否卸载旧版本? [Y/n] " yn
        case $yn in
            [Yy]* | "" ) 
                if [[ -f "./uninstall.sh" ]]; then
                    bash ./uninstall.sh
                else
                    warn "未找到卸载脚本，跳过卸载"
                fi
                ;;
            * ) log "保留旧版本，继续安装";;
        esac
    fi
}

cronjob() {
    create_log_dir
    {
        echo "当前时间: $(date)"
        echo "n8n 状态检查..."
    } >> "${USER_HOME}/n8n-serv00/n8n/logs/cronjob.log"
    
    # 重新加载环境变量
    re_source
    
    if check_status; then
        echo "N8N 运行正常" >> "${USER_HOME}/n8n-serv00/n8n/logs/cronjob.log"
    else
        echo "N8N 未运行，尝试重启..." >> "${USER_HOME}/n8n-serv00/n8n/logs/cronjob.log"
        start_n8n >> "${USER_HOME}/n8n-serv00/n8n/logs/cronjob.log" 2>&1
    fi
    
    echo "============" >> "${USER_HOME}/n8n-serv00/n8n/logs/cronjob.log"
}

# 主安装流程
main() {
    log "=== Serv00 N8N 优化安装脚本 v2.0 ==="
    log "针对 512MB RAM 环境优化"
    echo ""
    
    select_n8n_version
    uninstall_old_n8n
    set_port
    set_url
    set_www
    set_db
    
    log "开始安装..."
    
    devil binexec on || error "无法设置 binexec"
    re_source
    
    install_pnpm
    install_n8n_optimized
    
    update_profile
    re_source
    
    create_log_dir
    
    if check_status; then
        stop_n8n
    fi
    
    start_n8n
    
    sleep 10
    if check_status; then
        log "N8N 已成功启动"
        set_crontab
        show_completion_message
    else
        error "N8N 启动失败，请查看日志: ${USER_HOME}/n8n-serv00/n8n/logs/n8n.log"
    fi
}

usage() {
    cat << EOF
Serv00 N8N 优化安装脚本 v2.0

使用方法:
    bash i.sh [command]

可用命令:
    install     安装 N8N (默认)
    start       启动 N8N
    stop        停止 N8N
    restart     重启 N8N
    status      查看 N8N 状态
    cronjob     定时任务（保持运行）
    help        显示帮助信息

示例:
    bash i.sh              # 完整安装
    bash i.sh start        # 启动 N8N
    bash i.sh stop         # 停止 N8N
    bash i.sh restart      # 重启 N8N
EOF
}

# 主程序入口
case "${1:-install}" in
    install)
        main
        ;;
    start)
        start_n8n
        ;;
    stop)
        stop_n8n
        ;;
    restart)
        restart_n8n
        ;;
    status)
        check_status
        ;;
    cronjob)
        cronjob
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        error "未知命令: $1 (使用 --help 查看帮助)"
        ;;
esac
