#!/bin/bash

ORA_DEB="oracle-xe_11.2.0-1.0_amd64.deb"

#
# download the Oracle installer
#
# downloadOracle () {

# 	local url="https://github.com/MaksymBilenko/docker-oracle-xe-11g"

# 	local ora_deb_partial=( 
# 		${ORA_DEB}aa 
# 		${ORA_DEB}ab 
# 		${ORA_DEB}ac
# 	)
	
# 	local i=1
# 	for part in "${ora_deb_partial[@]}"; do     
# 		echo "[Downloading '$part' (part $i/3)]"
# 		curl -s --retry 3 -m 60 -o /$part -L $url/blob/master/$part?raw=true
# 		i=$((i + 1))

# 	done
	
# 	cat /${ORA_DEB}a* > /${ORA_DEB}

# 	rm -f /${ORA_DEB}a*

# }

# downloadOracle

cat /${ORA_DEB}a* > /${ORA_DEB}
dpkg --install /${ORA_DEB}
rm -f /${ORA_DEB}

# 判断文件夹是否存在
if [ ! -d "/u01/app/oracle/product/11.2.0/xe/config/scripts/" ];then
echo "/u01/app/oracle/product/11.2.0/xe/config/scripts not exit."
echo "/u01/app/oracle/product/11.2.0/xe/config/scripts create..."
mkdir /u01/app/oracle/product/11.2.0/xe/config/scripts
else
echo "/u01/app/oracle/product/11.2.0/xe/config/scripts exit."
fi
mv /init.ora       /u01/app/oracle/product/11.2.0/xe/config/scripts
mv /initXETemp.ora /u01/app/oracle/product/11.2.0/xe/config/scripts

mv /u01/app/oracle/product /u01/app/oracle-product

apt-get clean && rm -rf /tmp/* /var/lib/apt/lists/* /var/tmp/*
