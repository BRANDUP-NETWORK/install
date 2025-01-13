#!/bin/bash
VINSTALL="$(tr -dc A-Z1-9 < /dev/urandom | head -c 15 | xargs)"
apt update 
apt -y upgrade
clear
#Si Mysql ya esta instalado
if [ ! -f /etc/init.d/mariadb ];
then
apt -y install software-properties-common ca-certificates lsb-release apt-transport-https sudo net-tools unzip zip wget expect curl
#REPOSITORIO PHP
wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
sh -c 'echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
#REPOSITORIO PHP
apt update && apt -s upgrade

wget --no-check-certificate https://brandup.network/wp-content/uploads/2025/01/BRANDWISP.zip?v=$VINSTALL -O install.zip -q --show-progress
unzip -o install.zip
clear
chown root php_root
chmod u=rwx,go=xr,+s php_root
apt -y install mariadb-server

ROOTBD="$(tr -dc A-Z1-9 < /dev/urandom | head -c 15 | xargs)"
USERBD="$(tr -dc A-Z1-9 < /dev/urandom | head -c 6 | xargs)"
PASSBD="$(tr -dc A-Z1-9 < /dev/urandom | head -c 15 | xargs)"

cat <<EOT > accessmysql.log
    User: $USERBD
    Pass: $PASSBD
    Passroot: $ROOTBD
EOT

SECURE_MYSQL=$(expect -c "
set timeout 10
spawn mysql_secure_installation
expect \"Enter current password for root (enter for none):\"
send \"\r\"
expect \"Set root password?\"
send \"y\r\"
expect \"New password:\"
send \"$ROOTBD\r\"
expect \"Re-enter new password:\"
send \"$ROOTBD\r\"
expect \"Remove anonymous users?\"
send \"y\r\"
expect \"Disallow root login remotely?\"
send \"y\r\"
expect \"Remove test database and access to it?\"
send \"y\r\"
expect \"Reload privilege tables now?\"
send \"y\r\"
expect eof
")
echo "$SECURE_MYSQL"
apt -y purge expect
mysql -u root  mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOTBD'"
mysql -u root mysql -e "FLUSH PRIVILEGES;"

mysql -u root -p$ROOTBD -e "DROP DATABASE IF EXISTS BrandwispDB;"
mysql -u root -p$ROOTBD -e "CREATE DATABASE BrandwispDB /*\!40100 DEFAULT CHARACTER SET utf8 */;"
mysql -u root -p$ROOTBD -e "CREATE USER $USERBD@localhost IDENTIFIED BY '$PASSBD';"
mysql -u root -p$ROOTBD -e "GRANT ALL PRIVILEGES ON BrandwispDB.* TO '$USERBD'@'localhost';"
mysql -u root -p$ROOTBD mysql -e "FLUSH PRIVILEGES;"
mysql -u root -p$ROOTBD  mysql -e "SET GLOBAL group_concat_max_len = 1000000;"

echo "<?php
define(\"root\",\"/var/www/html\");
define(\"INSTALADO\", \"\");
define(\"NAME_BD\", \"BrandwispDB\");
define(\"USER_BD\", \"$USERBD\");
define(\"PASSWORD_BD\", \"$PASSBD\");
define(\"HOST_BD\", \"localhost\");
define(\"PORT_BD\", \"3306\");
define(\"BACKUP_LIMIT\",7);
define(\"SSL_KEY\",\"/etc/apache2/ssl/privkey1.pem\");
define(\"SSL_CRT\",\"/etc/apache2/ssl/fullchain1.pem\");
define(\"ROOT_BD_PASSWORD\",\"$ROOTBD\");
?>" > html/admin/ajax/db/config.php

apt -y install wget apache2 curl default-mysql-client unzip zip sudo perl libnet-ssleay-perl libxml2 openssl libauthen-pam-perl libpam-runtime libio-pty-perl apt-show-versions python3 dos2unix
apt -y install php7.2 php7.2-common php7.2-cli php7.2-fpm php7.2-mysql php7.2-xml php7.2-curl php7.2-mbstring php7.2-zip php7.2-gd libapache2-mod-php7.2
a2enconf php7.2
a2enmod php7.2
chmod -R 755 /var/www/html
rm -f -r /var/www/html/*
apt -y install php7.2-dev rrdtool imagemagick php7.2-rrd libnet-snmp-perl snmp php7.2-snmp fping php7.2-imagick ghostscript openssl freeradius freeradius-mysql freeradius-utils freeradius-common php7.2-soap openssl mcrypt gcc make autoconf libc-dev pkg-config libmcrypt-dev php7.2-dev libmcrypt-dev
printf "\n" | pecl install mcrypt-1.0.1
sudo bash -c "echo extension=/usr/lib/php/20170718/mcrypt.so > /etc/php/7.2/cli/conf.d/mcrypt.ini"
sudo bash -c "echo extension=/usr/lib/php/20170718/mcrypt.so > /etc/php/7.2/apache2/conf.d/mcrypt.ini"

### CONFIG RADIUS 
yes | cp -rf radius/brandwisp /etc/freeradius/3.0/sites-available/
rm /etc/freeradius/3.0/sites-enabled/inner-tunnel
rm /etc/freeradius/3.0/sites-enabled/default

cat <<EOT >  /etc/freeradius/3.0/mods-available/sql
sql {                  
driver = "rlm_sql_mysql"
dialect = "mysql"
server = "localhost"
port = 3306
login = "$USERBD"
password = "$PASSBD"
radius_db = "BrandwispDB"
acct_table1 = "radacct"
acct_table2 = "radacct"
postauth_table = "radpostauth"
authcheck_table = "radcheck"
groupcheck_table = "radgroupcheck"
authreply_table = "radreply"
groupreply_table = "radgroupreply"
usergroup_table = "radusergroup"
delete_stale_sessions = yes
pool {                               
start = \${thread[pool].start_servers}
min = \${thread[pool].min_spare_servers}
max = \${thread[pool].max_servers}
spare = \${thread[pool].max_spare_servers}
uses = 0
retry_delay = 30
lifetime = 0
idle_timeout = 60
}                 
read_clients = yes
client_table = "nas"
group_attribute = "SQL-Group"
\$INCLUDE \${modconfdir}/\${.:name}/main/\${dialect}/queries.conf
}
EOT

cat <<EOT >  /etc/freeradius/3.0/mods-available/exec
exec{
wait = yes
input_pairs = request
shell_escape = yes
output = none
}

exec cerrar{
wait = yes
input_pairs = request
program ="/usr/bin/php  /var/www/html/admin/ajax/radius.php '%{User-Name}'  'cerrar' &"
output = none
timeout = 10
}

exec suspender{
wait = yes
input_pairs = request
program ="/usr/bin/php  /var/www/html/admin/ajax/radius.php '%{User-Name}'  'add' &"
output = none
timeout = 10
}

exec activar{
wait = yes
input_pairs = request
program = "/usr/bin/php  /var/www/html/admin/ajax/radius.php '%{User-Name}'  'remove' &"
output = none
timeout = 10
}
EOT

ln -s /etc/freeradius/3.0/sites-available/brandwisp /etc/freeradius/3.0/sites-enabled/brandwisp
ln -s /etc/freeradius/3.0/mods-available/sql /etc/freeradius/3.0/mods-enabled/sql


### FIN RADIUS

### INSTALAR IONCUBE
yes | cp -rf 00-ioncube.ini /etc/php/7.2/apache2/conf.d/
yes | cp -rf 00-ioncube.ini /etc/php/7.2/cli/conf.d/

#Config Mysql
cat <<EOT > mkws.cnf
[mariadb]
unix_socket=OFF

[mysqld]
sql-mode="NO_ENGINE_SUBSTITUTION"
max_connections=1000
innodb_flush_log_at_trx_commit=2
skip-innodb_doublewrite
innodb_lock_wait_timeout=120
innodb_file_per_table=1

query_cache_type = 1
query_cache_limit = 5M
query_cache_size = 50M
EOT

yes | cp -rf mkws.cnf /etc/mysql/mariadb.conf.d/

if uname -a | grep x86_64
then
yes | cp -rf loader_64.so /usr/lib/php/20170718/ioncube_loader_lin_7.2.so
fi

if uname -a | grep i686
then
yes | cp -rf loader.so /usr/lib/php/20170718/ioncube_loader_lin_7.2.so
fi

if uname -a | grep armv7l
then
yes | cp -rf loaderpi.so /usr/lib/php/20170718/ioncube_loader_lin_7.2.so
fi

### INSTALL NFDUNMP
apt autoremove -y
apt-get install flex -y
apt-get install libbz2-dev -y
apt-get install bison -y
apt-get install byacc -y
apt install cmake -y
apt-get install doxygen -y
apt-get install libpcap-dev -y
apt-get install libghc-bzlib-dev -y
apt-get install libtool	-y
apt-get install dh-autoreconf -y
apt-get install binutils make csh g++ sed gawk autoconf automake autotools-dev -y
apt-get install graphviz -y
apt-get install autogen -y
apt-get install autogen pkg-config libgtk-3-dev -y

wget https://github.com/phaag/nfdump/archive/refs/tags/v1.7.3.tar.gz
tar -xvf v1.7.3.tar.gz
rm v1.7.3.tar.gz
cd nfdump-1.7.3
./autogen.sh
./autogen.sh
./configure
make
make install
ldconfig
cd ..
rm -r nfdump-1.7.3
clear
##FIN NFDUMP


yes | cp -rf 000-default.conf /etc/apache2/sites-available
yes | cp -rf default-ssl.conf /etc/apache2/sites-available
yes | cp -rf sudoers /etc/
yes | cp -rf sshd_config /etc/ssh/
chmod u+s `which ping`
cp -r html /var/www/
a2enmod rewrite
a2enmod ssl
a2ensite default-ssl
systemctl restart apache2
service mysql restart
service mariadb restart
a2dismod php5.6
a2dismod php7.1
a2dismod php7.3
a2enmod php7.2
update-alternatives --set php /usr/bin/php7.2
systemctl enable freeradius
rm install.zip


### INSTALL NPM SOCKET
curl -sL https://deb.nodesource.com/setup_21.x | bash -
apt install nodejs -y
sudo apt install -y gconf-service libgbm-dev libasound2 libatk1.0-0 libc6 libcairo2 libcups2 libdbus-1-3 libexpat1 libfontconfig1 libgcc1 libgconf-2-4 libgdk-pixbuf2.0-0 libglib2.0-0 libgtk-3-0 libnspr4 libpango-1.0-0 libpangocairo-1.0-0 libstdc++6 libx11-6 libx11-xcb1 libxcb1 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6 libxrandr2 libxrender1 libxss1 libxtst6 ca-certificates fonts-liberation libappindicator1 libnss3 lsb-release xdg-utils wget
mkdir -p /var/www/html/socket
cd /var/www/html/socket/

cat <<EOT > package.json
{
  "private": true,
  "devDependencies": {
    "axios": "^0.25.0"
  },
  "dependencies": {
    "apexcharts": "^3.33.1",
    "axios": "^0.25.0",
    "express": "^4.17.1",
    "merge-stream": "^2.0.0",
    "method-override": "^3.0.0",
    "qrcode": "^1.4.4",
    "socket.io": "^4.1.3",
    "whatsapp-web.js": "^1.24.0"
  }
}
EOT

npm install


apt install ffmpeg -y
apt-get install -y libgbm-dev
wget https://www.johnvansickle.com/ffmpeg/old-releases/ffmpeg-4.4.1-amd64-static.tar.xz
tar xvf ffmpeg-4.4.1-amd64-static.tar.xz
rm ffmpeg-4.4.1-amd64-static.tar.xz
a2enmod proxy
a2enmod proxy_http
a2enmod proxy_balancer
a2enmod lbmethod_byrequests
a2enmod proxy_wstunnel
a2enmod proxy_connect

for file in /etc/apache2/sites-available/*
do
   if grep -q 'localhost:3005' $file
then
echo "Instalado"
else
proxy="RewriteEngine On\n\
RewriteCond %{REQUEST_URI} ^\/socket.io          [NC]\n\
RewriteCond %{QUERY_STRING} transport=websocket [NC]\n\
RewriteRule \/(.*) ws:\/\/localhost:3005\/\$1        [P,L]\n\
ProxyPass \/socket.io http:\/\/localhost:3005\/socket.io\n\
ProxyPassReverse \/socket.io http:\/\/localhost:3005\/socket.io\n\
<\/VirtualHost>\n"

sed -i "s/<\/VirtualHost>/$proxy/" $file
fi

done
systemctl restart apache2
### INSTALL NPM

##COMPOSER
php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
php composer-setup.php
php -r "unlink('composer-setup.php');"
mv composer.phar /usr/local/bin/composer
##FIN COMPOSER


rm -f -r /var/www/html/__MACOSX
chown -R www-data:www-data /var/www/html/
IP=$(ifconfig | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | grep -v '127.0.0.1')
echo " \n"
echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" 
echo "+                                                                                       +"
echo "+    LUEGO DE REINICIAR PUEDE CONTINUAR VIA WEB  http://$IP/install       "
echo "+                                                                                     +"
echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++" 
read -rp 'Pulsa Enter para terminar y reiniciar servidor...'  key
reboot
else
clear
echo "El servidor ya tiene instalado Brandwisp o Mysql y no se puede volver ejecutar.";
exit 1
fi
#FIN MYSQL INSTALADOR
