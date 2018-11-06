#!/bin/bash
#xtrabackup 增量备份
#备份用户:grant SELECT,RELOAD,SHOW DATABASES,SUPER,LOCK TABLES,REPLICATION CLIENT,SHOW VIEW,EVENT,FILE,PROCESS on *.* to backup@'localhost' identified by 'backup';
#date "+%Y-%m-%d %H:%M:%S"

#环境设置:u 不存在的变量报错;e 发生错误退出;pipefail 管道有错退出
set -euo pipefail

START_TIME=`date +%s`

#########要更改变的变量#######
MYCNF="/etc/my.cnf"
SOCKET=`sed '/^socket.*=/!d;s/.*=//' $MYCNF | sed 's/^[ \t]*//g'| head -1` 
BACKUP_USER="backup"
BACKUP_PASS='backup'
SUF=`date "+%Y-%m-%d_%H-%M-%S"`
BACK_PATH="/cache1/backup"
FULL_BACKUP_DIR="${BACK_PATH}/full_backup"
INCREMENTAL_DIR="${BACK_PATH}/incremental"

###日志
BACKUK_LOG_PATH="/cache1/logs"
BKLOG="${BACKUK_LOG_PATH}/backuplog-$SUF.txt"

###innobackupex命令
INNOD_BACKUP_CMD="innobackupex --defaults-file=$MYCNF --user=${BACKUP_USER} --password=${BACKUP_PASS} --socket=$SOCKET --no-timestamp --rsync"

###是否传输
IS_RSYNC="false"
###要同步的IP，要求安装rsync服务端
BACKUPIP=""
###rsync客户端信息
RY_DIR="/opt/scripts"
CLIENT_PASS_FILE="${RY_DIR}/rsync_client.pwd"
RY_USER="chenzl"
MODULE_NAME="mysql"
RYLOG="${BACKUK_LOG_PATH}/rsynclog-$SUF.txt"
##############################
if [ ! -d "${BACK_PATH}" ]
then
    echo "#########创建备份目录########"
    mkdir -p "${BACK_PATH}"
fi

if [ ! -d "${BACKUK_LOG_PATH}" ]
then
    echo "#########创建日志目录########"
    mkdir -p "${BACKUK_LOG_PATH}"
fi

if [ ! -f "$BKLOG" ]; then
    touch "$BKLOG"
fi

###文件夹数
set +e
FULL_BACKUP_NUM=`ls -l ${FULL_BACKUP_DIR}| grep "^d" | wc -l`
set -e
if [  "${FULL_BACKUP_NUM}" -eq 0 ]; then
    echo "#########${FULL_BACKUP_DIR}为空,删除########"
    rm -rf ${FULL_BACKUP_DIR}
fi


if [ ! -d  "${FULL_BACKUP_DIR}" ]; then
    echo "#########开始全量备份########"
    echo "${INNOD_BACKUP_CMD}  ${FULL_BACKUP_DIR} 2>$BKLOG "
    echo "${INNOD_BACKUP_CMD}  ${FULL_BACKUP_DIR} 2>$BKLOG " >> $BKLOG
    ${INNOD_BACKUP_CMD}  ${FULL_BACKUP_DIR} 2>>$BKLOG
    echo "#########全量备份完成########"
    exit
else
    echo "#########全量备份已存在,开始增量备份########"
fi


echo "#########已有增量目录########"
echo "#########开始增量备份########"
###文件夹数
set +e
###当前最大num
INCREMENTAL_NUM=`ls ${BACK_PATH} | grep "incremental"|awk -F '-' '{print $2}'|awk 'BEGIN {max = 0} {if ($1+0 > max+0) max=$1 fi} END {print max}'`

if [  "${INCREMENTAL_NUM}" -eq 0 ]; then
    echo "#########开始第1次增量备份########"
    NUM=1
    echo "${INNOD_BACKUP_CMD} --incremental ${INCREMENTAL_DIR}-$NUM-$SUF  --incremental-basedir=${FULL_BACKUP_DIR}"
    echo "${INNOD_BACKUP_CMD} --incremental ${INCREMENTAL_DIR}-$NUM-$SUF  --incremental-basedir=${FULL_BACKUP_DIR}" >>$BKLOG
    ${INNOD_BACKUP_CMD} --incremental ${INCREMENTAL_DIR}-$NUM-$SUF  --incremental-basedir=${FULL_BACKUP_DIR} 2>>$BKLOG
else
    echo "#########最新的增量目录########"
    LAST=`ls /cache1/backup | grep  "incremental"-"${INCREMENTAL_NUM}"`
    echo "最新增量目录:" $LAST >>$BKLOG
    NUM=$[INCREMENTAL_NUM + 1]
    if [ ! -f "${BACK_PATH}/$LAST/xtrabackup_checkpoints" ]; then
        echo "$LAST 备份不完整,等待备份完成或重做备份" >>$BKLOG 
        exit
    fi
    echo "#########基于$LAST开始第$NUM次增量备份########"
    echo "${INNOD_BACKUP_CMD} --incremental ${INCREMENTAL_DIR}-$NUM-$SUF  --incremental-basedir=${BACK_PATH}/$LAST "
    echo "${INNOD_BACKUP_CMD} --incremental ${INCREMENTAL_DIR}-$NUM-$SUF  --incremental-basedir=${BACK_PATH}/$LAST " >>$BKLOG 
    ${INNOD_BACKUP_CMD} --incremental ${INCREMENTAL_DIR}-$NUM-$SUF --incremental-basedir=${BACK_PATH}/$LAST 2>>$BKLOG
fi


INCREMENTAL_DIR_NUM=`ls -l ${INCREMENTAL_DIR}-$NUM-$SUF | grep "^d" | wc -l`

if [ "${INCREMENTAL_DIR_NUM}" -ne 0 ]; then
    echo "#########增量备份完成########"
else
   echo "#########增量备份失败,删除########" 
   echo "rm -rf ${INCREMENTAL_DIR}-$NUM-$SUF"
   rm -rf ${INCREMENTAL_DIR}-$NUM-$SUF
fi
set -e

END_TIME=`date +%s`
echo "=====RUN TIME====="
dif=$[ END_TIME - START_TIME ] 
echo $dif
echo "total time:"$dif >> $BKLOG

if [ "${IS_RSYNC}" == "false" ]; then
    exit
fi

echo "=====传输到${BACKUPIP}====="
echo "/usr/bin/rsync -auvrtzopgP  --progress  --password-file=${CLIENT_PASS_FILE} $BACKDIR  ${RY_USER}@$BACKUPIP::${MODULE_NAME}" > $RYLOG
/usr/bin/rsync -auvrtzopgP  --progress  --password-file=${CLIENT_PASS_FILE} $BACKDIR  ${RY_USER}@$BACKUPIP::${MODULE_NAME} 1>>$RYLOG 2>>$RYLOG

END_TIME=`date +%s`
echo "=====RUN TIME====="
dif=$[ END_TIME - START_TIME ] 
echo $dif
echo "total time:"$dif >> $RYLOG

#rm -f /var/tmp/t.sh
#
