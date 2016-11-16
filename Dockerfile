FROM atsjj/php:5.3.29
MAINTAINER Steve Jabour <steve@jabour.me>

ENV GPG_KEYS 3D9A1B1AC72E5318
ENV SSP_VERSION 1.5.4.10265
ENV SSP_SALT dQMhPkOTJ4hGy8NPVzIKr1ugI7h957w757m5cROxiwSBBS0EpJoEsrIE3rIgU5th02N64rb4edCeVC7z8ji6heyaRTYrtV3uKWa6ejwXsERKm8OP6g4MzK1IQ1CgKOzzdgoGHvVrDaP0jZBoLHaGbQQswtG8rDCOzhoSXohgdVle7pvAbOvOIswOTsNUnUwHY98YsvGYNsfZZClrv98DM33xlRwuLzZ1Ys5i89bDSkRlYeAyU45O6QovdcsL5Des
ENV SSP_CACHE_ENGINE File
ENV SSP_CACHE_MEMCACHE localhost:11211
ENV SSP_URL https://summit.com/assets/slideshow-pro-director.tar.xz
ENV SSP_ASC_URL https://summit.com/assets/slideshow-pro-director.tar.xz.asc
ENV SSP_SHA256 1914a5b9986f909ee4d37d408580c585e9ae12d34b9d9eb6f588f94d97b66b04
ENV SSP_MD5 ffef04080ce91e501b23781db8c108a8
ENV MYSQL_HOST localhost
ENV MYSQL_USER user
ENV MYSQL_PASSWORD password
ENV MYSQL_DATABASE slideshow-pro-director
ENV MYSQL_TABLE_PREFIX ssp_
ENV MYSQL_ENCODING utf8

# add jessie backports repository
RUN set -ex \
    && { \
      echo 'deb http://ftp.de.debian.org/debian jessie-backports main'; \
    } | tee -a /etc/apt/sources.list

# install dependencies
RUN apt-get update && \
    apt-get install -y \
      ffmpeg \
      gettext-base \
      imagemagick \
      libfreetype6-dev \
      libgd-dev \
      libjpeg-dev \
      libmysqlclient-dev \
      libpng-dev \
      zlib1g-dev \
    --no-install-recommends && rm -r /var/lib/apt/lists/*

# work around php5-gd freetype2 bug (http://stackoverflow.com/a/26342869)
RUN mkdir /usr/include/freetype2/freetype && \
    ln -s /usr/include/freetype2/freetype.h /usr/include/freetype2/freetype/freetype.h

# install php extensions
RUN docker-php-ext-configure gd \
      --with-gd \
      --with-jpeg-dir \
      --with-png-dir \
      --with-zlib-dir \
      --with-freetype-dir

RUN docker-php-ext-configure exif \
      --enable-exif

RUN docker-php-ext-install -j$(nproc) \
      exif \
      gd \
      mysqli

# install slideshow-pro-director and environment inside the container
COPY docker-ssp-source /usr/local/bin/

RUN set -xe; \
  \
  fetchDeps=' \
    wget \
    xz-utils \
  '; \
  apt-get update; \
  apt-get install -y --no-install-recommends $fetchDeps; \
  rm -rf /var/lib/apt/lists/*; \
  \
  cd /tmp; \
  \
  wget -O slideshow-pro-director.tar.xz "$SSP_URL"; \
  \
  if [ -n "$SSP_SHA256" ]; then \
    echo "$SSP_SHA256 *slideshow-pro-director.tar.xz" | sha256sum -c -; \
  fi; \
  if [ -n "$SSP_MD5" ]; then \
    echo "$SSP_MD5 *slideshow-pro-director.tar.xz" | md5sum -c -; \
  fi; \
  \
  export GNUPGHOME="$(mktemp -d)"; \
  \
  for key in $GPG_KEYS; do \
    gpg --keyserver ha.pool.sks-keyservers.net --recv-keys "$key"; \
  done; \
  \
  if [ -n "$SSP_ASC_URL" ]; then \
    wget -O slideshow-pro-director.tar.xz.asc "$SSP_ASC_URL"; \
    gpg --batch --verify slideshow-pro-director.tar.xz.asc slideshow-pro-director.tar.xz; \
  fi; \
  \
  rm -r "$GNUPGHOME"; \
  \
  docker-ssp-source extract; \
  cd /var/www; \
  chown -R www-data:www-data slideshow-pro-director; \
  \
  apt-get purge -y --auto-remove $fetchDeps

COPY docker-php-fpm /usr/local/bin/

WORKDIR /var/www/slideshow-pro-director

RUN set -ex \
  && cd /usr/local/etc \
  && { \
    echo '[global]'; \
    echo 'error_log = /proc/self/fd/2'; \
    echo 'daemonize = no'; \
    echo; \
    echo '[www]'; \
    echo 'user = www-data'; \
    echo 'group = www-data'; \
    echo 'listen = 9000'; \
    echo 'pm = dynamic'; \
    echo 'pm.max_children = 5'; \
    echo 'pm.start_servers = 2'; \
    echo 'pm.min_spare_servers = 1'; \
    echo 'pm.max_spare_servers = 3'; \
    echo 'access.log = /proc/self/fd/2'; \
    echo 'catch_workers_output = yes'; \
    echo 'php_value[post_max_size] = 1024M'; \
    echo 'php_value[upload_max_filesize] = 1024M'; \
  } | tee php-fpm.conf \
  && cd /var/www/slideshow-pro-director \
  && { \
    echo '<?php'; \
    echo '  $interface = "mysqli";'; \
    echo '  $host = "${MYSQL_HOST}";'; \
    echo '  $db = "${MYSQL_DATABASE}";'; \
    echo '  $user = "${MYSQL_USER}";'; \
    echo '  $pass = "${MYSQL_PASSWORD}";'; \
    echo '  $pre = "${MYSQL_TABLE_PREFIX}";'; \
    echo '  $encoding = "${MYSQL_ENCODING}";'; \
    echo '?>'; \
  } | tee config/conf.php.template \
  && { \
    echo '<?php'; \
    echo '  Configure::write("debug", 0);'; \
    echo; \
    echo '  define("PRODUCTION", 1);'; \
    echo; \
    echo '  Configure::write("App.encoding", "UTF-8");'; \
    echo '  Configure::write("App.baseUrl", env("PHP_SELF") . "?");'; \
    echo; \
    echo '  if (defined("DISABLE_CACHE") && DISABLE_CACHE) {'; \
    echo '    Configure::write("Cache.disable", true);'; \
    echo '  } else {'; \
    echo '    Configure::write("Cache.disable", false);'; \
    echo '  }'; \
    echo; \
    echo '  Configure::write("Cache.check", true);'; \
    echo; \
    echo '  define("LOG_ERROR", 2);'; \
    echo; \
    echo '  Configure::write("Session.save", "cake");'; \
    echo '  Configure::write("Session.cookie", "DIRECTOR");'; \
    echo '  Configure::write("Session.timeout", "120");'; \
    echo '  Configure::write("Session.start", true);'; \
    echo '  Configure::write("Session.checkAgent", false);'; \
    echo; \
    echo '  Configure::write("Security.level", "low");'; \
    echo '  Configure::write("Security.salt", "${SSP_SALT}");'; \
    echo; \
    echo '  Configure::write("Acl.classname", "DbAcl");'; \
    echo '  Configure::write("Acl.database", "default");'; \
    echo; \
    echo '  if ("${SSP_CACHE_ENGINE}" == "Memcache") {'; \
    echo '    Cache::config("default", array('; \
    echo '      "engine" => "Memcache",'; \
    echo '      "servers" => array("${SSP_CACHE_MEMCACHE}")'; \
    echo '    ));'; \
    echo '  } else {' \
    echo '    Cache::config("default", array("engine" => "File"));'; \
    echo '  }'; \
    echo '?>'; \
  } | tee app/config/core.php.template \
  && { \
    echo '<?php'; \
    echo '  define("SALT", "${SSP_SALT}");'; \
    echo '  define("AUTO_UPDATE", false);'; \
    echo '  define("BETA_TEST", true);'; \
    echo; \
    echo '  ini_set("default_charset", "UTF-8");'; \
    echo '?>'; \
  } | tee config/user_setup.php.template \
  && chown www-data:www-data config/*.template \
  && cd /var/www \
  && cp -R ./slideshow-pro-director/ ./slideshow-pro-director-mirror \
  && chown -R www-data:www-data ./slideshow-pro-director-mirror \
  && mkdir ./slideshow-pro-director-data \
  && cd ./slideshow-pro-director-data \
  && cp -R ../slideshow-pro-director/albums/ ./albums \
  && cp -R ../slideshow-pro-director/album-audio/ ./album-audio \
  && cp -R ../slideshow-pro-director/app/tmp/ ./tmp \
  && cp -R ../slideshow-pro-director/xml_cache/ ./xml_cache \
  && cd ../slideshow-pro-director \
  && rm -rf ./albums ./album-audio ./app/tmp ./xml_cache \
  && ln -s /var/www/slideshow-pro-director-data/albums ./albums \
  && ln -s /var/www/slideshow-pro-director-data/album-audio ./album-audio \
  && ln -s /var/www/slideshow-pro-director-data/tmp ./app/tmp \
  && ln -s /var/www/slideshow-pro-director-data/xml_cache ./xml_cache \
  && chown -h www-data:www-data ./albums \
  && chown -h www-data:www-data ./album-audio \
  && chown -h www-data:www-data ./app/tmp \
  && chown -h www-data:www-data ./xml_cache \
  && chown -R www-data:www-data /var/www/slideshow-pro-director-data

# clean-up after install
RUN apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# php-fpm on port 9000
EXPOSE 9000

# run php-fpm on container start
CMD ["docker-php-fpm", "start"]
