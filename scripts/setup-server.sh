#!/bin/bash

# Script de configuración automática para servidor Laravel en EC2
# Red Hat Enterprise Linux / Amazon Linux 2

set -e  # Salir si hay errores

echo "🚀 Iniciando configuración del servidor Laravel en Red Hat..."

# Detectar versión del sistema
if [ -f /etc/redhat-release ]; then
    echo "📋 Sistema detectado: $(cat /etc/redhat-release)"
fi

# Limpiar repositorios problemáticos
echo "🧹 Limpiando repositorios conflictivos..."
sudo dnf config-manager --disable docker-ce-stable 2>/dev/null || true

# Actualizar sistema
echo "📦 Actualizando paquetes del sistema..."
sudo dnf update -y

# Instalar dependencias básicas
echo "🔧 Instalando dependencias básicas..."
sudo dnf install -y curl wget unzip git

# Habilitar repositorio EPEL para RHEL 10
echo "📦 Habilitando repositorio EPEL..."
sudo dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-10.noarch.rpm || echo "EPEL ya instalado o no disponible"

# Habilitar repositorio CodeReady/PowerTools para más paquetes
sudo dnf config-manager --set-enabled crb 2>/dev/null || sudo dnf config-manager --set-enabled powertools 2>/dev/null || true

# Instalar repositorio Remi para PHP 8.2
echo "🐘 Instalando repositorio Remi para PHP 8.2..."
sudo dnf install -y https://rpms.remirepo.net/enterprise/remi-release-10.rpm || \
sudo dnf install -y https://rpms.remirepo.net/enterprise/remi-release-9.rpm || \
sudo dnf install -y https://rpms.remirepo.net/enterprise/remi-release-8.rpm

# Habilitar módulo PHP 8.2
sudo dnf module reset php -y
sudo dnf module enable php:remi-8.2 -y

# Instalar PHP 8.2 y extensiones
echo "📦 Instalando PHP 8.2 y extensiones..."
sudo dnf install -y php php-fpm php-mysqlnd php-xml php-curl \
    php-zip php-mbstring php-gd php-intl php-bcmath \
    php-dom php-fileinfo php-tokenizer php-opcache

# Instalar Composer
echo "🎼 Instalando Composer..."
curl -sS https://getcomposer.org/installer | php
sudo mv composer.phar /usr/local/bin/composer
sudo chmod +x /usr/local/bin/composer

# Instalar Nginx
echo "🌐 Instalando Nginx..."
sudo dnf install -y nginx

# Instalar MySQL/MariaDB
echo "🗃️ Instalando MariaDB..."
sudo dnf install -y mariadb-server mariadb

# Configurar MySQL/MariaDB
echo "🔐 Configurando MariaDB..."
sudo systemctl start mariadb
sudo systemctl enable mariadb
sudo mysql_secure_installation

# Crear usuario y base de datos para Laravel
echo "👤 Configurando base de datos..."
sudo mysql -e "CREATE DATABASE laravel_production;"
sudo mysql -e "CREATE USER 'laravel_user'@'localhost' IDENTIFIED BY 'Laravel123!';"
sudo mysql -e "GRANT ALL PRIVILEGES ON laravel_production.* TO 'laravel_user'@'localhost';"
sudo mysql -e "FLUSH PRIVILEGES;"

# Instalar Node.js y npm
echo "📦 Instalando Node.js..."
curl -fsSL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo dnf install -y nodejs

# Configurar directorios
echo "📁 Configurando directorios..."
sudo mkdir -p /var/www/laravel
sudo chown -R nginx:nginx /var/www/laravel
sudo chmod -R 755 /var/www

# Configurar Nginx para Laravel
echo "⚙️ Configurando Nginx..."
sudo mkdir -p /etc/nginx/conf.d
sudo tee /etc/nginx/conf.d/laravel.conf > /dev/null << 'EOF'
server {
    listen 80;
    server_name _;
    root /var/www/laravel/public;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php;

    charset utf-8;

    location / {
        try_files $uri $uri/ /index.php?$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php-fpm/www.sock;
        fastcgi_param SCRIPT_FILENAME $realpath_root$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

# Deshabilitar configuración por defecto
sudo rm -f /etc/nginx/conf.d/default.conf

# Configurar PHP-FPM
echo "🔧 Configurando PHP-FPM..."
sudo sed -i 's/user = apache/user = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/group = apache/group = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/;listen.owner = nobody/listen.owner = nginx/' /etc/php-fpm.d/www.conf
sudo sed -i 's/;listen.group = nobody/listen.group = nginx/' /etc/php-fpm.d/www.conf

# Reiniciar servicios
echo "🔄 Reiniciando servicios..."
sudo systemctl enable nginx php-fpm mariadb
sudo systemctl restart nginx php-fpm mariadb

# Configurar firewall
echo "🔥 Configurando firewall..."
sudo firewall-cmd --permanent --add-service=http
sudo firewall-cmd --permanent --add-service=https
sudo firewall-cmd --permanent --add-service=ssh
sudo firewall-cmd --reload

# Crear archivo de entorno de producción
echo "📝 Creando archivo de entorno..."
sudo tee /var/www/laravel/.env > /dev/null << EOF
APP_NAME=Laravel
APP_ENV=production
APP_KEY=
APP_DEBUG=false
APP_URL=http://$(curl -s http://checkip.amazonaws.com)

DB_CONNECTION=mysql
DB_HOST=localhost
DB_PORT=3306
DB_DATABASE=laravel_production
DB_USERNAME=laravel_user
DB_PASSWORD=Laravel123!

CACHE_DRIVER=file
QUEUE_CONNECTION=sync
SESSION_DRIVER=file
EOF

echo "✅ ¡Configuración del servidor completada!"
echo ""
echo "📋 Información importante:"
echo "  - IP del servidor: $(curl -s http://checkip.amazonaws.com)"
echo "  - Directorio web: /var/www/laravel"
echo "  - Usuario MySQL: laravel_user"
echo "  - Password MySQL: Laravel123!"
echo "  - Base de datos: laravel_production"
echo ""
echo "🚀 El servidor está listo para recibir deployments!"
echo "💡 Recuerda configurar los secrets en GitHub con esta información."