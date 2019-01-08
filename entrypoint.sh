#!/bin/bash

# Prevent owner issues on mounted folders
chown -R oracle:dba /u01/app/oracle
rm -f /u01/app/oracle/product
ln -s /u01/app/oracle-product /u01/app/oracle/product
# Update hostname
sed -i -E "s/HOST = [^)]+/HOST = $HOSTNAME/g" /u01/app/oracle/product/11.2.0/xe/network/admin/listener.ora
sed -i -E "s/PORT = [^)]+/PORT = 1521/g" /u01/app/oracle/product/11.2.0/xe/network/admin/listener.ora
echo "export ORACLE_HOME=/u01/app/oracle/product/11.2.0/xe" > /etc/profile.d/oracle-xe.sh
echo "export PATH=\$ORACLE_HOME/bin:\$PATH" >> /etc/profile.d/oracle-xe.sh
echo "export ORACLE_SID=XE" >> /etc/profile.d/oracle-xe.sh
. /etc/profile

impdp () {
	DUMP_FILE=$(basename "$1")
	DUMP_NAME=${DUMP_FILE%.dmp} 
	cat > /tmp/impdp.sql << EOL
-- Impdp User
-- 1. 创建用户，设置用户表空间及其余信息

-- New Scheme User
--创建用户并且设置用户密码
create user ${DUMP_NAME} identified by ${DUMP_NAME};
--授予DBA角色：connect连接角色，resource可以操作其它表空间权限，dba系统权限，谨慎授权
grant dba,connect,resource to ${DUMP_NAME};
--授予导入导出数据库权限
grant imp_full_database,exp_full_database to ${DUMP_NAME};
--创建表空间，1g左右，上线之前可以测试设置多少合适
CREATE TABLESPACE ${DUMP_NAME} DATAFILE '/u01/app/oracle/oradata/XE/${DUMP_NAME}.dbf' SIZE 1000M EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO;
--创建临时表,建议大点，几百M，上线之前可以测试设置多少合适
CREATE TEMPORARY TABLESPACE ${DUMP_NAME}_temp TEMPFILE '/u01/app/oracle/oradata/XE/${DUMP_NAME}_temp.dbf' SIZE 500M;
--为用户分配表空间和临时表空间
alter user ${DUMP_NAME} default tablespace ${DUMP_NAME}_ts temporary tablespace ${DUMP_NAME}_temp;
--设置表空间自动增长，表空间大小就是文件大小，一个文件大约30G，可以增加文件
ALTER DATABASE DATAFILE '/u01/app/oracle/oradata/XE/${DUMP_NAME}_ts.dbf' AUTOEXTEND ON NEXT 200M MAXSIZE UNLIMITED;

exit;
EOL

	su oracle -c "NLS_LANG=.$CHARACTER_SET $ORACLE_HOME/bin/sqlplus -S / as sysdba @/tmp/impdp.sql"
	su oracle -c "NLS_LANG=.$CHARACTER_SET $ORACLE_HOME/bin/imp $DUMP_NAME/$DUMP_NAME file=/docker-entrypoint-initdb.d/ full=y ignore=y log=/docker-entrypoint-initdb.d/init_log.log"
	#Disable IMPDP user
	echo -e 'ALTER USER IMPDP ACCOUNT LOCK;\nexit;' | su oracle -c "NLS_LANG=.$CHARACTER_SET $ORACLE_HOME/bin/sqlplus -S / as sysdba"
}

impFile() {
	echo "found file $1"
	case "$1" in
		*.sh)     echo "[IMPORT] $0: running $1"; . "$1" ;;
		*.sql)    echo "[IMPORT] $0: running $1"; echo "exit" | su oracle -c "NLS_LANG=.$CHARACTER_SET $ORACLE_HOME/bin/sqlplus -S / as sysdba @$1"; echo ;;
		*.dmp)    echo "[IMPORT] $0: running $1"; impdp $1 ;;
		*)        echo "[IMPORT] $0: ignoring $1" ;;
	esac
}

case "$1" in
	'')
		#Check for mounted database files
		if [ "$(ls -A /u01/app/oracle/oradata 2> /dev/null)" ]; then
			echo "found files in /u01/app/oracle/oradata Using them instead of initial database"
			echo "XE:$ORACLE_HOME:N" >> /etc/oratab
			chown oracle:dba /etc/oratab
			chown 664 /etc/oratab
			printf "ORACLE_DBENABLED=false\nLISTENER_PORT=1521\nHTTP_PORT=8080\nCONFIGURE_RUN=true\n" > /etc/default/oracle-xe
			rm -rf /u01/app/oracle-product/11.2.0/xe/dbs
			ln -s /u01/app/oracle/dbs /u01/app/oracle-product/11.2.0/xe/dbs
		else
			echo "Database not initialized. Initializing database."

			if [ -z "$CHARACTER_SET" ]; then
				export CHARACTER_SET="AL32UTF8"
			fi

			printf "Setting up:\nprocesses=$processes\nsessions=$sessions\ntransactions=$transactions\n"
			echo "If you want to use different parameters set processes, sessions, transactions env variables and consider this formula:"
			printf "processes=x\nsessions=x*1.1+5\ntransactions=sessions*1.1\n"

			mv /u01/app/oracle-product/11.2.0/xe/dbs /u01/app/oracle/dbs
			ln -s /u01/app/oracle/dbs /u01/app/oracle-product/11.2.0/xe/dbs

			#Setting up processes, sessions, transactions.
			sed -i -E "s/processes=[^)]+/processes=$processes/g" /u01/app/oracle/product/11.2.0/xe/config/scripts/init.ora
			sed -i -E "s/processes=[^)]+/processes=$processes/g" /u01/app/oracle/product/11.2.0/xe/config/scripts/initXETemp.ora
			
			sed -i -E "s/sessions=[^)]+/sessions=$sessions/g" /u01/app/oracle/product/11.2.0/xe/config/scripts/init.ora
			sed -i -E "s/sessions=[^)]+/sessions=$sessions/g" /u01/app/oracle/product/11.2.0/xe/config/scripts/initXETemp.ora

			sed -i -E "s/transactions=[^)]+/transactions=$transactions/g" /u01/app/oracle/product/11.2.0/xe/config/scripts/init.ora
			sed -i -E "s/transactions=[^)]+/transactions=$transactions/g" /u01/app/oracle/product/11.2.0/xe/config/scripts/initXETemp.ora

			printf 8080\\n1521\\n${DEFAULT_SYS_PASS}\\n${DEFAULT_SYS_PASS}\\ny\\n | /etc/init.d/oracle-xe configure
			echo "Setting sys/system passwords"
			echo  alter user sys identified by \"$DEFAULT_SYS_PASS\"\; | su oracle -s /bin/bash -c "$ORACLE_HOME/bin/sqlplus -s / as sysdba" > /dev/null 2>&1
   			echo  alter user system identified by \"$DEFAULT_SYS_PASS\"\; | su oracle -s /bin/bash -c "$ORACLE_HOME/bin/sqlplus -s / as sysdba" > /dev/null 2>&1

			echo "Database initialized. Please visit http://#containeer:8080/apex to proceed with configuration"
		fi

		/etc/init.d/oracle-xe start

		echo "Starting import scripts from '/docker-entrypoint-initdb.d':"

		for fn in $(ls -1 /docker-entrypoint-initdb.d/* 2> /dev/null)
		do
			# execute script if it didn't execute yet or if it was changed
			cat /docker-entrypoint-initdb.d/.cache 2> /dev/null | grep "$(md5sum $fn)" || impFile $fn
		done

		# clear cache
		if [ -e /docker-entrypoint-initdb.d/.cache ]; then
			rm /docker-entrypoint-initdb.d/.cache
		fi

		# regenerate cache
		ls -1 /docker-entrypoint-initdb.d/*.sh 2> /dev/null | xargs md5sum >> /docker-entrypoint-initdb.d/.cache
		ls -1 /docker-entrypoint-initdb.d/*.sql 2> /dev/null | xargs md5sum >> /docker-entrypoint-initdb.d/.cache
		ls -1 /docker-entrypoint-initdb.d/*.dmp 2> /dev/null | xargs md5sum >> /docker-entrypoint-initdb.d/.cache

		echo "Import finished"
		echo

		echo "Database ready to use. Enjoy! ;)"

		##
		## Workaround for graceful shutdown. ....ing oracle... ‿( ́ ̵ _-`)‿
		##
		while [ "$END" == '' ]; do
			sleep 1
			trap "/etc/init.d/oracle-xe stop && END=1" INT TERM
		done
		;;

	*)
		echo "Database is not configured. Please run /etc/init.d/oracle-xe configure if needed."
		exec "$@"
		;;
esac
