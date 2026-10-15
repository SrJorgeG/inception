# Secrets

Password files are not committed. Create them locally before running `make`:

```sh
echo 'change_me' > secrets/db_root_password.txt
echo 'change_me' > secrets/db_password.txt
echo 'change_me' > secrets/wp_admin_password.txt
echo 'change_me' > secrets/wp_user_password.txt
```

The NGINX TLS private key is also not committed. Generate a self-signed pair:

```sh
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout srcs/requirements/nginx/tools/nginx.key \
  -out srcs/requirements/nginx/tools/nginx.crt \
  -subj "/CN=your_login.42.fr"
```
