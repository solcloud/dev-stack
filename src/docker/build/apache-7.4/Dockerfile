FROM php:7.4-apache

RUN apt-get update
RUN apt-get install -y git
RUN apt-get install -y unzip

RUN apt-get update && apt-get install -y \
        libfreetype6-dev \
        libjpeg62-turbo-dev \
        libmcrypt-dev \
        libpng-dev \
        libwebp-dev \
        zlib1g-dev \
        libicu-dev \
        libzip-dev \
        libc-client-dev \
        libkrb5-dev \
        libonig-dev \
        g++ \
    && docker-php-ext-install -j$(nproc) iconv intl pdo pdo_mysql mysqli mbstring bcmath \
    && docker-php-ext-configure gd --with-freetype --with-webp --with-jpeg \
    && docker-php-ext-install -j$(nproc) gd \
    && apt-get install imagemagick libmagickwand-dev libmagickcore-dev -y \
    && pecl install imagick \
    && pecl install xdebug-2.9.8 \
    && pecl install zip


RUN pecl install redis && docker-php-ext-enable redis
RUN a2enmod rewrite
RUN docker-php-ext-install sockets

RUN apt-get install -y vim
RUN echo "umask 007" >> /etc/apache2/envvars
RUN echo 'export HOME=/tmp' >> /etc/apache2/envvars
