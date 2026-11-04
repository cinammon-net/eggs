# Cinammon WebHost · Nginx + PHP 8.3 sobre Alpine
# Construir:  docker build -t ghcr.io/cinammon-net/webhost:latest images/webhost
FROM alpine:3.20

LABEL org.opencontainers.image.title="Cinammon WebHost" \
      org.opencontainers.image.description="Nginx + PHP 8.3 (FPM) para el hosting web de Cinammon" \
      org.opencontainers.image.vendor="Cinammon Network" \
      org.opencontainers.image.source="https://github.com/cinammon-net/eggs"

RUN apk add --no-cache \
        bash ca-certificates curl git tzdata tini \
        nginx \
        php83 php83-fpm php83-opcache php83-common \
        php83-bcmath php83-ctype php83-curl php83-dom php83-exif php83-fileinfo php83-gd php83-gettext \
        php83-iconv php83-intl php83-mbstring php83-mysqli php83-openssl php83-pdo php83-pdo_mysql \
        php83-pdo_pgsql php83-pdo_sqlite php83-phar php83-session php83-simplexml php83-sodium \
        php83-sqlite3 php83-tokenizer php83-xml php83-xmlreader php83-xmlwriter php83-zip php83-pecl-imagick \
    && ln -sf /usr/bin/php83 /usr/bin/php \
    && ln -sf /usr/sbin/php-fpm83 /usr/sbin/php-fpm \
    && curl -fsSL https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer \
    && adduser -D -h /home/container -u 1000 container

USER container
ENV USER=container HOME=/home/container
WORKDIR /home/container

COPY --chmod=755 entrypoint.sh /entrypoint.sh
ENTRYPOINT ["/sbin/tini", "--", "/entrypoint.sh"]
