FROM debian:bookworm

RUN apt-get update && apt-get install -y \
    php8.2-fpm \
    php8.2-mysql \
    php8.2-curl \
    php8.2-gd \
    php8.2-mbstring \
    php8.2-xml \
    php8.2-zip \
    curl \
    mariadb-client \
    && rm -rf /var/lib/apt/lists/*

# Install WP-CLI
RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar \
    && chmod +x wp-cli.phar \
    && mv wp-cli.phar /usr/local/bin/wp

RUN mkdir -p /var/www/html
WORKDIR /var/www/html

COPY conf/www.conf /etc/php/8.2/fpm/pool.d/www.conf

COPY tools/wordpress_setup.sh /usr/local/bin/wordpress_setup.sh
RUN chmod +x /usr/local/bin/wordpress_setup.sh

EXPOSE 9000

ENTRYPOINT ["/usr/local/bin/wordpress_setup.sh"]
