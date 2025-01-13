#!/bin/bash
VINSTALL="$(tr -dc A-Z1-9 < /dev/urandom | head -c 15 | xargs)"
apt update 
apt -y upgrade
clear
# Si MySQL ya está instalado
if [ ! -f /etc/init.d/mariadb ]; then
    apt -y install software-properties-common ca-certificates lsb-release apt-transport-https sudo net-tools unzip zip wget expect curl
    # REPOSITORIO PHP
    wget -O /etc/apt/trusted.gpg.d/php.gpg https://packages.sury.org/php/apt.gpg
    sh -c 'echo "deb https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list'
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
    mysql -u root mysql -e "ALTER USER 'root'@'localhost' IDENTIFIED BY '$ROOTBD'"
    mysql -u root -p"$ROOTBD" mysql -e "FLUSH PRIVILEGES;"

    mysql -u root -p"$ROOTBD" -e "DROP DATABASE IF EXISTS BrandwispDB;"
    mysql -u root -p"$ROOTBD" -e "CREATE DATABASE BrandwispDB /*\!40100 DEFAULT CHARACTER SET utf8 */;"
    mysql -u root -p"$ROOTBD" -e "CREATE USER $USERBD@localhost IDENTIFIED BY '$PASSBD';"
    mysql -u root -p"$ROOTBD" -e "GRANT ALL PRIVILEGES ON BrandwispDB.* TO '$USERBD'@'localhost';"
    mysql -u root -p"$ROOTBD" -e "FLUSH PRIVILEGES;"
    mysql -u root -p"$ROOTBD" mysql -e "SET GLOBAL group_concat_max_len = 1000000;"

    echo "<?php
\$server = \"localhost\";
\$usernamebase = \"root\";
\$passwordbase = \"$ROOTBD\";
\$database = \"BrandwispDB\";

// Intentar conectar con la base de datos
\$mysqli = new MySQLi(\$server, \$usernamebase, \$passwordbase, \$database);

// Configurar el juego de caracteres
\$mysqli->set_charset(\"utf8\");

// Incluir el archivo de errores si es necesario
include_once \"errores.php\";
?>" > /var/www/html/required/connect_db.php

    chmod 644 /var/www/html/required/connect_db.php
    chown www-data:www-data /var/www/html/required/connect_db.php

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

    # Continuar con el resto de las configuraciones...
    
    apt -y install wget apache2 curl default-mysql-client unzip zip sudo perl libnet-ssleay-perl libxml2 openssl libauthen-pam-perl libpam-runtime libio-pty-perl apt-show-versions python3 dos2unix
    apt -y install php7.2 php7.2-common php7.2-cli php7.2-fpm php7.2-mysql php7.2-xml php7.2-curl php7.2-mbstring php7.2-zip php7.2-gd libapache2-mod-php7.2
    a2enconf php7.2
    a2enmod php7.2
    chmod -R 755 /var/www/html
    rm -f -r /var/www/html/*
    # Rest of the script...
fi
