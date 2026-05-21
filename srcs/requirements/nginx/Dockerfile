FROM debian:bullseye

RUN apt-get update && apt-get install -y \
    nginx \
    openssl \
    && rm -rf /var/lib/apt/lists/*

COPY tools/nginx.crt /etc/nginx/ssl/nginx.crt
COPY tools/nginx.key /etc/nginx/ssl/nginx.key

COPY conf/nginx.conf /etc/nginx/nginx.conf

EXPOSE 443

CMD ["nginx", "-g", "daemon off;"]