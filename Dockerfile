FROM php:8.1-fpm-alpine3.19
LABEL Maintainer="Ocasta" \
      Description="Nginx PHP8.1 Wordpress Bedrock"


# install the PHP extensions we need (https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions)
RUN set -ex; \
  \
  apk add --no-cache --virtual .build-deps \
    $PHPIZE_DEPS \
    freetype-dev \
    libjpeg-turbo-dev \
    libpng-dev \
    libzip-dev \
  ; \
  \
  docker-php-ext-configure gd --with-freetype --with-jpeg; \
  docker-php-ext-install -j "$(nproc)" \
    bcmath \
    exif \
    gd \
    mysqli \
    opcache \
    zip; 
# Install imagick
RUN apk add --no-cache ${PHPIZE_DEPS} bash sed ghostscript php81-xml imagemagick imagemagick-dev
RUN pecl install -o -f imagick \
    &&  docker-php-ext-enable imagick
RUN apk del --no-cache ${PHPIZE_DEPS}
# Install ds and apfd
RUN pecl install ds-1.4.0; \
  pecl install apfd-1.0.3; \
  docker-php-ext-enable apfd ds
RUN runDeps="$( \
    scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
      | tr ',' '\n' \
      | sort -u \
      | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
  )"; \
  apk add --virtual .wordpress-phpexts-rundeps $runDeps; \
  apk del .build-deps

# set recommended PHP.ini settings
# see https://secure.php.net/manual/en/opcache.installation.php
RUN { \
    echo 'opcache.memory_consumption=128'; \
    echo 'opcache.interned_strings_buffer=8'; \
    echo 'opcache.max_accelerated_files=4000'; \
    echo 'opcache.revalidate_freq=2'; \
    echo 'opcache.fast_shutdown=1'; \
  } > /usr/local/etc/php/conf.d/opcache-recommended.ini
# https://wordpress.org/support/article/editing-wp-config-php/#configure-error-logging
RUN { \
# https://www.php.net/manual/en/errorfunc.constants.php
# https://github.com/docker-library/wordpress/issues/420#issuecomment-517839670
    echo 'error_reporting = E_ERROR | E_WARNING | E_PARSE | E_CORE_ERROR | E_CORE_WARNING | E_COMPILE_ERROR | E_COMPILE_WARNING | E_RECOVERABLE_ERROR'; \
    echo 'error_reporting = 0'; \
    echo 'display_errors = Off'; \
    echo 'display_startup_errors = Off'; \
    echo 'log_errors = On'; \
    echo 'error_log = /dev/stderr'; \
    echo 'log_errors_max_len = 1024'; \
    echo 'ignore_repeated_errors = On'; \
    echo 'ignore_repeated_source = Off'; \
    echo 'html_errors = Off'; \
  } > /usr/local/etc/php/conf.d/error-logging.ini


# Add nginx, Wordpress, and our own configuration

# Install our additional packages
RUN apk --no-cache add ssmtp nginx supervisor composer

# Configure nginx
COPY config/nginx.conf /etc/nginx/http.d/default.conf

# Configure PHP-FPM
# https://github.com/TrafeX/docker-php-nginx/blob/6a3b2f4abcd35da533ec191d8cb09eaa31159a85/config/fpm-pool.conf
COPY config/fpm-pool.conf /usr/local/etc/php-fpm.d/zzz_custom.conf
COPY config/php.ini /usr/local/etc/php/conf.d/zzz_custom.ini

# Configure supervisord
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Add Bedrock
# Sometime Bedrock don't have a release with the latest WP version and you have to use the dependabot commit
# RUN curl -L -o wordpress.tar.gz https://github.com/roots/bedrock/archive/84133b258efabbcbbd258137fd199fd1f742f3d6.tar.gz  && tar --strip=1 -xzvf wordpress.tar.gz && rm wordpress.tar.gz && \
# Use the next one when there's a Bedrock release
RUN curl -L https://github.com/roots/bedrock/archive/refs/tags/1.24.3.tar.gz | tar -xzv --strip=1 && \
    composer install --no-dev

COPY scripts/install-language.sh /usr/local/bin/install-language.sh
RUN /usr/local/bin/install-language.sh es_ES fr_FR

# Annoying hack for arabic as there is only a 6.1.1 version
# Check https://make.wordpress.org/polyglots/teams/?locale=ar for updates
RUN cd /var/www/html/web/app/languages && \
    curl https://downloads.wordpress.org/translation/core/6.1.1/ar.zip -O && \
    unzip ar.zip && \
    rm ar.zip

RUN chown -R www-data.www-data /var/www/html/web/app/uploads/

# Expose the nginx port
EXPOSE 80

COPY ./scripts/. /usr/local/bin/
ENTRYPOINT ["docker-entrypoint"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
