FROM php:8.4-apache

COPY --from=mlocati/php-extension-installer /usr/bin/install-php-extensions /usr/local/bin/
# igbinary first, so memcached is built with igbinary serializer support
RUN install-php-extensions igbinary \
	&& install-php-extensions mysqli intl zip redis memcached @composer \
	&& php -r 'exit(Memcached::HAVE_IGBINARY ? 0 : 1);'

RUN apt-get update \
	&& apt-get install -y --no-install-recommends default-mysql-client patch \
	&& rm -rf /var/lib/apt/lists/* \
	# MySQL uses a self-signed certificate; traffic stays on the internal Docker network
	&& printf '[client]\nskip-ssl-verify-server-cert\n' > /etc/mysql/conf.d/zotero-client.cnf

RUN a2enmod rewrite headers deflate
COPY config/php.ini $PHP_INI_DIR/conf.d/zotero.ini
COPY config/zotero.conf /etc/apache2/sites-available/000-default.conf
COPY config/gzip.conf /etc/apache2/conf-enabled/gzip.conf

WORKDIR /var/www/zotero
COPY src/server/dataserver/ ./
COPY src/patches/dataserver/ /tmp/patches/
RUN for p in /tmp/patches/*.patch; do patch -p1 --forward --no-backup-if-mismatch < "$p" || exit 1; done \
	&& rm -rf /tmp/patches
# Zend Framework 1 is no longer bundled; zf1-future is a maintained, PHP 8 compatible fork
RUN composer install --no-dev --no-interaction \
	&& composer require --no-interaction --update-no-dev shardj/zf1-future:^1.24 \
	&& composer dump-autoload --no-dev --optimize

RUN gzip -kf htdocs/zotero-schema/schema.json

COPY config/config.inc.php config/dbconnect.inc.php include/config/
COPY --chmod=755 config/dataserver-scripts/*.sh misc/
COPY config/dataserver-scripts/www.sql misc/

RUN mkdir -p tmp errors && chown www-data:www-data tmp errors

EXPOSE 80
