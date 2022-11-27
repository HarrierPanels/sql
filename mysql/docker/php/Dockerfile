# Create Apache/PHP image
FROM php:7.4-apache
MAINTAINER HarrierPanels

# Install git and MySQL extensions for PHP
RUN apt-get update && apt-get install -y git
RUN docker-php-ext-install pdo pdo_mysql mysqli
RUN a2enmod rewrite

COPY /bkp/*.php /var/www/html/
ADD /bkp/*.tar.gz /var/www/

EXPOSE 80/tcp
EXPOSE 443/tcp
