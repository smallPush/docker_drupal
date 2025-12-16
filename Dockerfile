FROM php:8.3-apache

# 1. Download PHP extension installer (Fixes libc-client-dev and IMAP issues)
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

# 2. Install SYSTEM packages (General tools)
# NOTE: Removed -dev libraries (libpng, libxml, etc) because the installer above handles them.
# Keeping 'nodejs' and 'npm' from stable repositories.
RUN chmod +x /usr/local/bin/install-php-extensions && \
  apt-get update && apt-get install -y --no-install-recommends \
  apt-transport-https \
  bash-completion \
  default-mysql-client \
  git \
  iproute2 \
  msmtp-mta \
  nano \
  nodejs \
  npm \
  rsync \
  sudo \
  unzip \
  vim \
  zip \
  vpnc \
  wget \
  memcached \
  telnet \
  openssh-client \
  jq \
  && rm -rf /var/lib/apt/lists/*

# 3. Install PHP and PECL extensions (Using the magic script)
# This replaces all 'docker-php-ext-install' and 'pecl install' blocks
# The script handles missing dependencies (like libc-client)
RUN install-php-extensions \
  bcmath \
  gd \
  gettext \
  imap \
  intl \
  mysqli \
  opcache \
  pdo_mysql \
  soap \
  zip \
  filter \
  imagick \
  xdebug

# 4. Enable Apache modules
RUN a2enmod rewrite headers

# 5. Create necessary directories
RUN mkdir -p .amp/apache.d .cache/bower .composer .drush .npm

# 6. Copy configurations
COPY php.ini /usr/local/etc/php/conf.d/php.ini
COPY 000-default.conf /etc/apache2/conf-enabled/

# 7. Install Composer (From official image)
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer
RUN composer global require drush/drush:8.* phpunit/phpunit

ENV PATH="/root/.composer/vendor/bin:${PATH}"
RUN ln -s /root/.composer/vendor/bin/phpunit /usr/bin/phpunit

# 8. Bash aliases
RUN echo 'export PATH="$HOME/.composer/vendor/drush/drush:$PATH"' >> /root/.bashrc \
  && echo "alias ll='ls -alF --color=auto'" >> /root/.bashrc \
  && echo "alias la='ls -A'" >> /root/.bashrc \
  && echo "alias l='ls -CF'" >> /root/.bashrc

# 9. Buildkit and CiviCRM tools
WORKDIR /buildkit
ENV PATH="/buildkit/bin:${PATH}"

RUN git clone https://github.com/civicrm/civicrm-buildkit.git . \
  && git clone https://github.com/squizlabs/PHP_CodeSniffer \
  && git clone https://github.com/civicrm/coder.git

# Install PHP CodeSniffer
WORKDIR /tmp
RUN curl -OL https://squizlabs.github.io/PHP_CodeSniffer/phpcs.phar \
  && cp phpcs.phar /usr/local/bin/phpcs \
  && chmod +x /usr/local/bin/phpcs

WORKDIR /buildkit
RUN phpcs --config-set installed_paths /buildkit/coder/coder_sniffer

# CiviCRM Tools
RUN curl -LsS https://download.civicrm.org/cv/cv.phar -o /usr/local/bin/cv \
  && curl -LsS https://download.civicrm.org/civix/civix.phar -o /usr/local/bin/civix \
  && curl https://drupalconsole.com/installer -L -o /usr/local/bin/drupal \
  && chmod +x /usr/local/bin/cv /usr/local/bin/civix /usr/local/bin/drupal

# Remove xdebug for production (Optional)
RUN rm -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini