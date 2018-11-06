#!/bin/bash
#xtrabackup 主从

#环境设置:u 不存在的变量报错;e 发生错误退出;pipefail 管道有错退出
set -euo pipefail

START_TIME=`date +%s`

#########要更改变的变量#######
MYCNF="/etc/my.cnf"
MYSQL_PASS=''
BACKDIR="/cache1/backup/full_data"
###要同步的IP，要求安装rsync服务端
BACKUPIP=""

###日志
BKLOG="/cache1/backup/backuplog.txt"
RELOG="/cache1/backup/redolog.txt"
RYLOG="/cache1/backup/rsynclog.txt"

###rsync客户端信息
RY_DIR="/opt/scripts"
CLIENT_PASS_FILE="${RY_DIR}/rsync_client.pwd"
RY_USER=""
RY_PASS=""
MODULE_NAME=""
##############################
if [ ! -f "/usr/bin/innobackupex" ]; then
    echo "#########安装innobackupex########"
    MYSQL_VERSION=`mysql -V|awk '{print $5}'|awk -F "." '{print $1$2}'`
    echo "Mysql Version:" ${MYSQL_VERSION}
    yum install perl-DBD-MySQL perl-DBI perl-Time-HiRes -y
    yum -y install libev-devel numactl-devel
    cd /var/tmp
    wget http://dl.fedoraproject.org/pub/epel/6/x86_64/Packages/l/libev-4.03-3.el6.x86_64.rpm
    rpm -ivh libev-4.03-3.el6.x86_64.rpm

    if [ "${MYSQL_VERSION}" -le 51 ]; then
        wget https://www.percona.com/downloads/XtraBackup/XtraBackup-1.6.7/RPM/rhel6/x86_64/xtrabackup-1.6.7-356.rhel6.x86_64.rpm
        rpm -ivh xtrabackup-1.6.7-356.rhel6.x86_64.rpm
    fi
    if [ "${MYSQL_VERSION}" -gt 51 -a "${MYSQL_VERSION}" -lt 56  ]; then
        wget https://www.percona.com/downloads/XtraBackup/XtraBackup-2.2.9/binary/redhat/6/x86_64/percona-xtrabackup-2.2.9-5067.el6.x86_64.rpm
        rpm -ivh percona-xtrabackup-2.2.9-5067.el6.x86_64.rpm
    fi
    if [ "${MYSQL_VERSION}" -ge 56 ]; then
        wget https://www.percona.com/downloads/XtraBackup/Percona-XtraBackup-2.4.12/binary/redhat/6/x86_64/percona-xtrabackup-24-2.4.12-1.el6.x86_64.rpm
        rpm -ivh percona-xtrabackup-24-2.4.12-1.el6.x86_64.rpm
    fi
fi

echo "#########清空备份目录########"
if [ ! -d $BACKDIR ]
then
    mkdir -p $BACKDIR
fi
rm -rf $BACKDIR/*
rm -f $BKLOG $RELOG $RYLOG

echo "#########开始备份########"
innobackupex --defaults-file=$MYCNF  --no-timestamp --user=root --password="${MYSQL_PASS}"  --rsync  $BACKDIR 2>$BKLOG

if [ $? -ne 0 ]; then   
    echo "backup failed" >> $BKLOG
    exit;
fi
echo "innobackupex --defaults-file=$MYCNF  --no-timestamp --user=root --password=\"${MYSQL_PASS}\"  --rsync  $BACKDIR " >> $BKLOG

echo "#########REDO LOG########"
innobackupex --defaults-file=$MYCNF --user=root --password="${MYSQL_PASS}"  --apply-log $BACKDIR 2>$RELOG

if [ $? -ne 0 ]; then   
    echo "REDO LOG FAILED" >> $RELOG
    exit;
fi

echo "innobackupex --defaults-file=$MYCNF --user=root --password=\"${MYSQL_PASS}\"  --apply-log $BACKDIR" >> $RELOG

echo "########RSYNC $BACKUPIP########"
if [ ! -f "/etc/xinetd.d/rsync" ]; then
    yum install -y rsync
fi

rm -f /etc/rsync*
if [ ! -d "${RY_DIR}" ]; then
    mkdir -p  ${RY_DIR}
fi

echo "${RY_PASS}" > /opt/scripts/rsync_client.pwd
chmod 600 /opt/scripts/rsync_client.pwd


rm -f $BACKDIR/xtrabackup_logfile
/usr/bin/rsync -auvrtzopgP  --progress  --password-file=${CLIENT_PASS_FILE} $BACKDIR  ${RY_USER}@$BACKUPIP::${MODULE_NAME} 1>$RYLOG 2>>$RYLOG

if [ $? -ne 0 ]; then   
    echo "SSYNC  FAILED" >> $RYLOG
    exit;
fi

echo "/usr/bin/rsync -auvrtzopgP  --progress  --password-file=${CLIENT_PASS_FILE} $BACKDIR  ${RY_USER}@$BACKUPIP::${MODULE_NAME}" >> $RYLOG

END_TIME=`date +%s`
echo "=====RUN TIME====="
dif=$[ END_TIME - START_TIME ] 
echo $dif

#at 01:30 tomorrow
#screen -d -m -S mysql /var/tmp/t.sh
#rm -f $0
