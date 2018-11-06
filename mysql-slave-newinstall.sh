#!/bin/bash
#mysql主从设置,master设置,centos6
#mysql 5.7.23


#环境设置:u 不存在的变量报错;e 发生错误退出;pipefail 管道有错退出
set -euo pipefail

START_TIME=`date +%s`

#########要更改变的变量#######
IP=`ifconfig|sed -n '/inet addr/s/^[^:]*:\([0-9.]\{7,15\}\) .*/\1/p'|head -1`

###MYSQL版本
MYSQL_VERSION="5.7.23"
MAJOR=`echo "${MYSQL_VERSION}"|awk '{print substr('${MYSQL_VERSION}',1,3)}'`

#MYSQL登录信息,新安装则更改为此密码;为了安全,用户名应不为root
MYSQL_USER="chenzl"
MYSQL_PASS='fokefZk7ch6$RnOD'

###MYSQL参数
MYSQL_CNF="/etc/my.cnf"

###版本改动的配置


###MYSQL新装参数
PORT="3306"
USER="mysql"
BASE_DIR="/usr"
DIR_PRE="/cache1/mysql";
DATA_DIR="${DIR_PRE}/data"
SOCKET="${DIR_PRE}/mysql.sock"
LOG_ERROR="${DIR_PRE}/mysql_error.err"
PID_FILE="${DIR_PRE}/mysqld.pid"
SLOW_DIR="${DIR_PRE}/slowlog"
###MYSQL新装参数,不新装则可更改的参数
LOG_BIN="${DIR_PRE}/binlog"
RELAY_LOG="${DIR_PRE}/relaybinlog"

###BINLOG参数
###IP后两位
SERVER_ID=`echo "${IP}"|awk -F "." '{print $3$4}'`
###BINLOG保留天数
EXPIRE_DAYS=5

###组提交参数:延迟可以让多个事务在用一时刻提交;等待延迟提交的最大事务数
GROUP_DELAY=1000000
GROUP_COUNT=20

###SLAVE参数
WORKERS=16

###INNODE参数
###data的路径,分布在多盘
DATA_FILE_PATH="ibdata1:200M;/cache1/mysql/data/ibdata2:12M:autoextend"
TMP_FILE_PATH="/cache1/mysql/data/ibtmp1:12M:autoextend:max:50G"
###innodb缓存空间，不超过内存的2/3
POOL_SIZE=6G
###innodb写log的缓存，上限4G
LOG_SIZE=256M
###对于io的能力预估,hdd为200，hdd+raid0为400，ssd为20000
IO_CAP=200

##双1设置
###多少个BINLOG时刷磁盘,0为由系统决定;1最安全;100 性能
SYNC_BINLOG=0
###innodb刷新模式，1最安全也最慢，0代表mysql崩溃可能导致丢失事务，2代表linux崩溃，一般建议2
FLUSH_TRX=2

###是否禁用密码策略:off 禁用
MYSQL_PASS_POLICY="off"

#slow_log目录不存,则新建
if [ ! -d ${SLOW_DIR} ];then
    mkdir -p ${SLOW_DIR}
fi

###下载地址
DOWN_URL=""


if [ -n "${DOWN_URL}" ]; then
    SERVER_URL="${DOWN_URL}/mysql/mysql-community-server-${MYSQL_VERSION}-1.el6.x86_64.rpm"
    CLIENT_URL="${DOWN_URL}/mysql/mysql-community-client-${MYSQL_VERSION}-1.el6.x86_64.rpm"
    DEVEL_URL="${DOWN_URL}/mysql/mysql-community-devel-${MYSQL_VERSION}-1.el6.x86_64.rpm"
    LIB_URL="${DOWN_URL}/mysql/mysql-community-libs-${MYSQL_VERSION}-1.el6.x86_64.rpm"
    COMMON_URL="${DOWN_URL}/mysql/mysql-community-common-${MYSQL_VERSION}-1.el6.x86_64.rpm"
    COMPAT_URL="${DOWN_URL}/mysql/mysql-community-libs-compat-${MYSQL_VERSION}-1.el6.x86_64.rpm"
    XTRABACK24_URL="${DOWN_URL}/percona-xtrabackup-24-2.4.1-1.el6.x86_64.rpm"
    XTRABACK22_URL="${DOWN_URL}/percona-xtrabackup-2.2.9-5067.el6.x86_64.rpm"
    XTRABACK16_URL="${DOWN_URL}/xtrabackup-1.6.7-356.rhel6.x86_64.rpm"
    LIBEV_URL="${DOWN_URL}/libev-4.03-3.el6.x86_64.rpm"
else
    SITE_URL="http://mirrors.ustc.edu.cn/mysql-ftp/Downloads/MySQL-$MAJOR"
    PERCONA_URL="https://www.percona.com/downloads/XtraBackup"
    SERVER_URL="${SITE_URL}/mysql-community-server-${MYSQL_VERSION}-1.el6.x86_64.rpm"
    CLIENT_URL="${SITE_URL}/mysql-community-client-${MYSQL_VERSION}-1.el6.x86_64.rpm"
    DEVEL_URL="${SITE_URL}/mysql-community-devel-${MYSQL_VERSION}-1.el6.x86_64.rpm"
    LIB_URL="${SITE_URL}/mysql-community-libs-${MYSQL_VERSION}-1.el6.x86_64.rpm"
    COMMON_URL="${SITE_URL}/mysql-community-common-${MYSQL_VERSION}-1.el6.x86_64.rpm"
    COMPAT_URL="${SITE_URL}/mysql-community-libs-compat-${MYSQL_VERSION}-1.el6.x86_64.rpm"
    XTRABACK24_URL="${PERCONA_URL}/Percona-XtraBackup-2.4.12/binary/redhat/6/x86_64/percona-xtrabackup-24-2.4.12-1.el6.x86_64.rpm"
    XTRABACK22_URL="${PERCONA_URL}/XtraBackup-2.2.9/binary/redhat/6/x86_64/percona-xtrabackup-2.2.9-5067.el6.x86_64.rpm"
    XTRABACK16_URL="${PERCONA_URL}/XtraBackup-1.6.7/RPM/rhel6/x86_64/xtrabackup-1.6.7-356.rhel6.x86_64.rpm"
    LIBEV_URL="http://dl.fedoraproject.org/pub/epel/6/x86_64/Packages/l/libev-4.03-3.el6.x86_64.rpm"

fi

##############################
#新建binlog
if [ ! -d ${LOG_BIN} ];then
    mkdir -p ${LOG_BIN}
fi

#slave新建relaylog

if [ ! -d ${RELAY_LOG} ];then
    mkdir -p ${RELAY_LOG}
fi

echo "==========MYSQL安装=========="
###下载
cd /var/tmp
if [ ! -f "mysql-community-server-${MYSQL_VERSION}-1.el6.x86_64.rpm" ]; then
    wget ${SERVER_URL}
    wget ${CLIENT_URL}
    wget ${DEVEL_URL}
    wget ${LIB_URL}
    wget ${COMMON_URL}
    wget ${COMPAT_URL}
fi

###安装numactl
if [ ! -f "/usr/bin/numactl" ]; then
    yum -y install numactl
fi

###设置账号
grep "mysql" /etc/passwd && ISSET="true" || ISSET="false"
if [  "$ISSET" == "false" ]; then
    groupadd mysql
    useradd -M -s /sbin/nologin -g mysql mysql
fi

###安装
if [ ! -f "/usr/sbin/mysqld" ]; then
    rpm -Uvh --replacefiles mysql-community*
fi

###创建DIR_PRE
if [ ! -d "${DIR_PRE}" ]; then
    mkdir -p ${DIR_PRE}
    chown -R $USER:$USER ${DIR_PRE}
fi

###创建LOG_ERROR
if [ -f "${LOG_ERROR}" ]; then
    rm -f "${LOG_ERROR}"
fi

touch "${LOG_ERROR}"
chown -R $USER:$USER ${DIR_PRE}


###新建datadir
if [ ! -d ${DATA_DIR} ];then
    mkdir -p ${DATA_DIR}
    chown -R $USER:$USER ${DIR_PRE}
else
    rm -rf ${DATA_DIR}/*
    chown -R $USER:$USER ${DIR_PRE}
fi

###关闭selinux,否则mysql创建文件夹报没权限
echo "#########关闭selinux#######"
grep 'SELINUX=disabled' /etc/selinux/config && ISSET="true" || ISSET="false"
if [ "$ISSET" == "false" ]; then
    echo "#########关闭selinux#########"
    sed -i 's;SELINUX=enforcing;SELINUX=disabled;'  /etc/selinux/config
    setenforce 0
else
    echo "#########selinux 已关闭#########"
fi


#清理默认文件
set +e
rm -f /root/.mysql_secret
rm -rf /var/lib/mysql
rm -f /root/.mysql_history
rm -f /etc/my.cnf.rpmnew
rm -f /var/log/mysqld.log
set -e

echo "==========设置master的MY.CNF=========="
cat > ${MYSQL_CNF} <<EOF
[client]
port=$PORT
[mysql]
socket=$SOCKET
default-character-set = utf8
no_auto_rehash
[mysqld]
user = $USER
port=$PORT
basedir=${BASE_DIR}
datadir=${DATA_DIR}
socket=$SOCKET
log-error=${LOG_ERROR}
pid-file=${PID_FILE}
slow_query_log=1
long_query_time=3
slow_query_log_file=${SLOW_DIR}/slow_query.log
default_password_lifetime=0
server_id=${SERVER_ID}
log-bin=${LOG_BIN}/mysql-bin 
expire_logs_days=${EXPIRE_DAYS}
binlog_format=ROW
sync_binlog=${SYNC_BINLOG}
binlog-row-image=minimal
binlog_group_commit_sync_delay=1000
binlog_group_commit_sync_no_delay_count=20
relay_log=${RELAY_LOG}/mysql-relay-bin
slave-parallel-type=LOGICAL_CLOCK
slave-parallel-workers=${WORKERS}
master_info_repository=TABLE
relay_log_info_repository=TABLE
relay_log_recovery=ON
gtid_mode=on
enforce_gtid_consistency=on
#log-slave-updates=1
skip-character-set-client-handshake
wait_timeout=1800
interactive_timeout=1800
character-set-server = utf8
collation-server = utf8_general_ci
symbolic-links=0
explicit_defaults_for_timestamp=1 
max_connections=1000
max_connect_errors = 30
skip_external_locking 
#skip_name_resolve
read_only=0
event_scheduler=0
query_cache_type=1
query_cache_size=64M
default-storage-engine=INNODB
innodb_large_prefix=1
innodb_strict_mode=1 
innodb_file_per_table=1
innodb_buffer_pool_size=${POOL_SIZE}
innodb_io_capacity=${IO_CAP}
innodb_flush_neighbors=1
innodb_log_file_size=${LOG_SIZE}
innodb_flush_log_at_trx_commit=${FLUSH_TRX}
innodb_stats_on_metadata=0
innodb_data_home_dir=
innodb_data_file_path=${DATA_FILE_PATH}
innodb_temp_data_file_path =${TMP_FILE_PATH}
transaction_isolation=READ-COMMITTED
key_buffer_size=256M
max_allowed_packet=16M
sort_buffer_size=2M
read_buffer_size=2M
read_rnd_buffer_size=2M
join_buffer_size=2M
sql_mode=NO_ENGINE_SUBSTITUTION,STRICT_TRANS_TABLES
tmp_table_size=128M
max_heap_table_size=128M
group_concat_max_len=64K
table_open_cache=2048
thread_cache_size=1024
character_set_server=utf8
log_bin_trust_function_creators=1
open_files_limit=60000
lower_case_table_names=1
secure_file_priv=
[mysqld_multi]
mysqld=/usr/bin/mysqld_safe
mysqladmin=/usr/bin/mysqladmin
[mysqldump]
quick
[myisamchk]
key_buffer_size = 20M
sort_buffer_size = 20M
read_buffer = 2M
write_buffer = 2M
[mysqlhotcopy]
interactive-timeout
[mysqld_safe]
pid-file=${PID_FILE}
EOF

echo "==========启动,更改默认密码=========="
set +e
service mysqld start
TEM_PASS=`sed '/A temporary password/!d;s/.*: //' ${LOG_ERROR}`
echo "初始密码是:"${TEM_PASS}
###初始修改root密码
echo "mysql -uroot -P${PORT} -p"${TEM_PASS}" --connect-expired-password  -e \"SET PASSWORD = PASSWORD('"${MYSQL_PASS}"');\""
mysql -uroot -P${PORT} -p"${TEM_PASS}" --connect-expired-password  -e "SET PASSWORD = PASSWORD('"${MYSQL_PASS}"');"
###设置密码不过期
echo "mysql -uroot -P${PORT} -p"${MYSQL_PASS}" --connect-expired-password  -e \"update mysql.user set password_expired='N' where user='root';\""
mysql -uroot -P${PORT} -p"${MYSQL_PASS}" --connect-expired-password  -e "update mysql.user set password_expired='N' where user='root';"

###修改root用户名
if [ "${MYSQL_USER}" != "root" ]; then
    echo "mysql -uroot -P${PORT} -p'${MYSQL_PASS}' --connect-expired-password  -e \"UPDATE mysql.user set user='"${MYSQL_USER}"'  where user='root';flush privileges;\""
    mysql -uroot -P${PORT} -p"${MYSQL_PASS}" --connect-expired-password  -e "UPDATE mysql.user set user='"${MYSQL_USER}"'  where user='root';flush privileges;"
fi
set -e

if [ "${MYSQL_PASS_POLICY}" == "off" ]; then
    echo "==========关闭密码策略=========="
    sed -i "/default_password_lifetime/a\validate_password=off"  ${MYSQL_CNF}
    service mysqld restart
fi

echo "==========mysql安装完成=========="

echo "=====运行时间为====="
END_TIME=`date +%s`
dif=$[ END_TIME - START_TIME ] 
echo $dif "秒"
