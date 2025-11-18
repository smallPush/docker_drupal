FROM php:8.2-apache

# 1. Descargar el instalador de extensiones PHP (Soluciona el problema de libc-client-dev e IMAP)
ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/

# 2. Instalar paquetes del SISTEMA (Herramientas generales)
# NOTA: He quitado las librerías -dev (libpng, libxml, etc) porque el instalador de arriba las maneja solo.
# Se mantiene 'nodejs' y 'npm' de los repositorios estables.
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

# 3. Instalar extensiones PHP y PECL (Usando el script mágico)
# Esto reemplaza todos los bloques 'docker-php-ext-install' y 'pecl install'
# El script se encarga de las dependencias faltantes (como libc-client)
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

# 4. Habilitar módulos de Apache
RUN a2enmod rewrite headers

# 5. Crear directorios necesarios
RUN mkdir -p .amp/apache.d .cache/bower .composer .drush .npm

# 6. Copiar configuraciones
COPY php.ini /usr/local/etc/php/conf.d/php.ini
COPY 000-default.conf /etc/apache2/conf-enabled/

# 7. Instalar Composer (Desde imagen oficial)
COPY --from=composer:latest /usr/bin/composer /usr/local/bin/composer
RUN composer global require drush/drush:8.* phpunit/phpunit

ENV PATH="/root/.composer/vendor/bin:${PATH}"
RUN ln -s /root/.composer/vendor/bin/phpunit /usr/bin/phpunit

# 8. Alias de bash
RUN echo 'export PATH="$HOME/.composer/vendor/drush/drush:$PATH"' >> /root/.bashrc \
  && echo "alias ll='ls -alF --color=auto'" >> /root/.bashrc \
  && echo "alias la='ls -A'" >> /root/.bashrc \
  && echo "alias l='ls -CF'" >> /root/.bashrc

# 9. Buildkit y herramientas CiviCRM
WORKDIR /buildkit
ENV PATH="/buildkit/bin:${PATH}"

RUN git clone https://github.com/rubofvil/civicrm-buildkit.git . \
  && git clone https://github.com/squizlabs/PHP_CodeSniffer \
  && git clone https://github.com/civicrm/coder.git

# Instalar PHP CodeSniffer
WORKDIR /tmp
RUN curl -OL https://squizlabs.github.io/PHP_CodeSniffer/phpcs.phar \
  && cp phpcs.phar /usr/local/bin/phpcs \
  && chmod +x /usr/local/bin/phpcs

WORKDIR /buildkit
RUN phpcs --config-set installed_paths /buildkit/coder/coder_sniffer

# Herramientas CiviCRM
RUN curl -LsS https://download.civicrm.org/cv/cv.phar -o /usr/local/bin/cv \
  && curl -LsS https://download.civicrm.org/civix/civix.phar -o /usr/local/bin/civix \
  && curl https://drupalconsole.com/installer -L -o /usr/local/bin/drupal \
  && chmod +x /usr/local/bin/cv /usr/local/bin/civix /usr/local/bin/drupal

# Eliminar xdebug para producción (Opcional)
RUN rm -f /usr/local/etc/php/conf.d/docker-php-ext-xdebug.ini

#