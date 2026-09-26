FROM php:8.4-apache

COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/
RUN install-php-extensions mysqli @composer \
	&& cp "$PHP_INI_DIR/php.ini-production" "$PHP_INI_DIR/php.ini"

WORKDIR /var/www/portal
RUN composer require --no-interaction jumbojett/openid-connect-php:^1.0
COPY docker/portal/src/ ./

# Every request goes to index.php; no other file is reachable directly
RUN a2enmod rewrite \
	&& printf '%s\n' \
		'<VirtualHost *:80>' \
		'	DocumentRoot /var/www/portal' \
		'	<Directory /var/www/portal>' \
		'		Require all granted' \
		'	</Directory>' \
		'	RewriteEngine On' \
		'	RewriteRule ^ /index.php [L]' \
		'</VirtualHost>' > /etc/apache2/sites-available/000-default.conf

EXPOSE 80
