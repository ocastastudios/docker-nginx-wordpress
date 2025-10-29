FROM php:8.3-fpm-alpine3.22
LABEL Maintainer="Ocasta" \
  Description="Nginx PHP8.3 Wordpress Bedrock"

# Install runtime dependencies
RUN apk --no-cache add \
  bash \
  sed \
  ghostscript \
  php83-xml \
  imagemagick \
  ssmtp \
  nginx \
  supervisor \
  composer \
  redis

# Install PHP extensions and PECL packages in a single layer
# https://make.wordpress.org/hosting/handbook/handbook/server-environment/#php-extensions
RUN set -ex; \
  \
  # Add build dependencies
  apk add --no-cache --virtual .build-deps \
  $PHPIZE_DEPS \
  freetype-dev \
  libjpeg-turbo-dev \
  libpng-dev \
  libzip-dev \
  imagemagick-dev \
  ; \
  \
  # Configure and install PHP extensions
  docker-php-ext-configure gd --with-freetype --with-jpeg; \
  docker-php-ext-install -j "$(nproc)" \
  bcmath \
  exif \
  gd \
  mysqli \
  opcache \
  zip \
  ; \
  \
  # Install PECL extensions
  pecl install -o -f imagick; \
  pecl install ds-1.6.0; \
  pecl install apfd-1.0.3; \
  pecl install redis; \
  \
  # Enable all extensions
  docker-php-ext-enable imagick apfd ds redis; \
  \
  # Identify and install runtime dependencies
  runDeps="$( \
  scanelf --needed --nobanner --format '%n#p' --recursive /usr/local/lib/php/extensions \
  | tr ',' '\n' \
  | sort -u \
  | awk 'system("[ -e /usr/local/lib/" $1 " ]") == 0 { next } { print "so:" $1 }' \
  )"; \
  apk add --virtual .wordpress-phpexts-rundeps $runDeps; \
  \
  # Clean up build dependencies
  apk del .build-deps; \
  rm -rf /tmp/pear ~/.pearrc

# Configure PHP settings in a single layer
RUN { \
  # Opcache settings - https://secure.php.net/manual/en/opcache.installation.php
  echo 'opcache.memory_consumption=128'; \
  echo 'opcache.interned_strings_buffer=8'; \
  echo 'opcache.max_accelerated_files=4000'; \
  echo 'opcache.revalidate_freq=2'; \
  echo 'opcache.fast_shutdown=1'; \
  } > /usr/local/etc/php/conf.d/opcache-recommended.ini \
  && { \
  # Error logging - https://wordpress.org/support/article/editing-wp-config-php/#configure-error-logging
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

# Copy configuration files (cached layer - these change infrequently)
COPY config/nginx.conf /etc/nginx/http.d/default.conf
COPY config/nginx_headers.conf /etc/nginx/headers.conf
COPY config/fpm-pool.conf /usr/local/etc/php-fpm.d/zzz_custom.conf
COPY config/php.ini /usr/local/etc/php/conf.d/zzz_custom.ini
COPY config/supervisord.conf /etc/supervisor/conf.d/supervisord.conf

# Install Bedrock with optimized Composer settings
# Sometime Bedrock don't have a release with the latest WP version and you have to use the dependabot commit
# RUN curl -L -o wordpress.tar.gz https://github.com/roots/bedrock/archive/84133b258efabbcbbd258137fd199fd1f742f3d6.tar.gz  && tar --strip=1 -xzvf wordpress.tar.gz && rm wordpress.tar.gz && composer install --no-dev
RUN curl -L https://github.com/roots/bedrock/archive/refs/tags/1.28.3.tar.gz | tar -xz --strip=1 && \
  composer install --no-dev --optimize-autoloader && \
  composer clear-cache

# Install WordPress language packs
COPY scripts/install-language.sh /usr/local/bin/install-language.sh
RUN /usr/local/bin/install-language.sh es_ES fr_FR && \
  rm -f /usr/local/bin/install-language.sh

# Install Arabic language pack (temporary hack until newer version available)
# Check https://make.wordpress.org/polyglots/teams/?locale=ar for updates
RUN cd /var/www/html/web/app/languages && \
  curl -sSL https://downloads.wordpress.org/translation/core/6.1.1/ar.zip -O && \
  unzip -q ar.zip && \
  rm ar.zip

# Create uploads directory and set permissions
RUN mkdir -p /var/www/html/web/app/uploads && \
  chown -R www-data:www-data /var/www/html/web/app/uploads

# Copy scripts (most frequently changing files last for better cache)
COPY ./scripts/. /usr/local/bin/

# Expose nginx port
EXPOSE 80

ENTRYPOINT ["docker-entrypoint"]
CMD ["/usr/bin/supervisord", "-c", "/etc/supervisor/conf.d/supervisord.conf"]
