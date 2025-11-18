FROM php:8.2-apache

# Install apt packages
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
  apt-transport-https \
  && curl -sL https://deb.nodesource.com/setup_14.x | bash - \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
  bash-completion \
  default-mysql-client \
  git \
  iproute2 \
  libc-client-dev \
  libicu-dev \
  libfreetype6-dev \
  libjpeg62-turbo-dev \
  libkrb5-dev \
  libmagickwand-dev \
  libpng-dev \
  libxml2-dev \
  libwebp-dev \
  libzip-dev \
  msmtp-mta \
  nano \
  nodejs \
  rsync \
  sudo \
  unzip \
  vim \
  zip \
  vpnc \
  wget \
  memcached \
  telnet \
  ssh-client \
  jq \
  && rm -rf /var/lib/apt/lists/*

# Install php extensions
RUN docker-php-ext-install bcmath \
  && docker-php-ext-configure gd --with-freetype --with-jpeg --with-webp \
  && docker-php-ext-install gd \
  && docker-php-ext-install gettext \
  && docker-php-ext-configure imap --with-kerberos --with-imap-ssl \
  && docker-php-ext-install imap \
  && docker-php-ext-install intl \
  && docker-php-ext-install mysqli \
  && docker-php-ext-install opcache \
  && docker-php-ext-install pdo_mysql \
  && docker-php-ext-install soap \
  && docker-php-ext-install zip \
  && docker-php-ext-install filter

# Install PECL extensions
RUN pecl install imagick xdebug \
  && docker-php-ext-enable imagick

# Enable Apache modules
RUN a2enmod rewrite headers

# Create directories
RUN mkdir -p .amp/apache.d .cache/bower .composer .drush .npm

# Copy configuration files
COPY php.ini /usr/local/etc/php/conf.d/php.ini
COPY 000-default.conf /etc/apache2/conf-enabled/

# Install Composer and tools
RUN curl -sS https://getcomposer.org/installer | php \
  && mv composer.phar /usr/local/bin/composer \
  && composer global require drush/drush:8.* phpunit/phpunit

ENV PATH="/root/.composer/vendor/bin:${PATH}"
RUN ln -s /root/.composer/vendor/bin/phpunit /usr/bin/phpunit

# Add bash aliases
RUN echo 'export PATH="$HOME/.composer/vendor/drush/drush:$PATH"' >> /root/.bashrc \
  && echo "alias ll='ls -alF --color=auto'" >> /root/.bashrc \
  && echo "alias la='ls -A'" >> /root/.bashrc \
  && echo "alias l='ls -CF'" >> /root/.bashrc

# Install buildkit
WORKDIR /buildkit
ENV PATH="/buildkit/bin:${PATH}"

RUN git clone https://github.com/rubofvil/civicrm-buildkit.git . \
  && git clone https://github.com/squizlabs/PHP_CodeSniffer \
  && git clone https://github.com/civicrm/coder.git

# Install PHP CodeSniffer
WORKDIR /tmp
RUN curl -OL https://squizlabs.github.io/PHP_CodeSniffer/phpcs.phar \
  && cp phpcs.phar /usr/local/bin/phpcs \
  && chmod +x /usr/local/bin/phpcs

WORKDIR /buildkit
RUN phpcs --config-set installed_paths /buildkit/coder/coder_sniffer

# Install CiviCRM tools
RUN curl -LsS https://download.civicrm.org/cv/cv.phar -o /usr/local/bin/cv \
  && curl -LsS https://download.civicrm.org/civix/civix.phar -o /usr/local/bin/civix \
  && curl https://drupalconsole.com/installer -L -o /usr/local/bin/drupal \
  && chmod +x /usr/local/bin/cv /usr/local/bin/civix /usr/local/bin/drupal

# Remove xdebug config (if not needed in production)
RUN rm -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

# Copy and set entrypoint
COPY ./docker-civicrm-entrypoint /usr/local/bin/
RUN chmod +x /usr/local/bin/docker-civicrm-entrypoint

WORKDIR /var/www/html

ENTRYPOINT ["docker-civicrm-entrypoint"]
CMD ["apache2-foreground"]
