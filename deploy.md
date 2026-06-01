# ChronoCalendar 部署说明

本文档使用 UTF-8 编码，面向当前仓库的实际部署方式编写。

当前后端部署结构：

- `backend`：Django API，容器内使用 Gunicorn 提供服务
- `db`：PostgreSQL
- `nginx`：反向代理，转发到 Django
- `docker-compose.yml`：统一编排三个服务
- Cloudflare：DNS 解析和 HTTPS 入口

本文默认你的后端域名是：

```text
https://thuse.skyislimit.uno
```

如果后续域名变化，把文中的域名替换成你的真实域名即可。

## 1. 部署目标和现状

你的目标是：

1. 云服务器上运行 Django、PostgreSQL 和 Nginx
2. Cloudflare 解析域名到服务器公网 IP
3. Cloudflare SSL/TLS 模式使用 `Full`
4. 前端 APK 通过 HTTPS 访问后端

当前仓库里已经具备：

- Dockerfile
- `docker-compose.yml`
- Gunicorn 启动方式
- PostgreSQL 容器
- Nginx 80 端口反向代理
- `.env.example`

当前仓库里还没有真正完成的部分：

- Nginx 的 443 TLS 配置
- `docker-compose.yml` 对 443 端口和证书目录的挂载
- 源站证书文件

这意味着：

- 如果不补 443 配置，Cloudflare `Full` 模式无法正常工作
- 你不能只改 Cloudflare 面板设置，还必须同步改服务器配置

## 2. 需要上传到服务器的文件

推荐做法：直接上传整个仓库，或者在服务器上 `git clone`。

如果你只打算上传后端部署所需文件，至少要包含这些内容：

```text
backend/
deploy/
docker-compose.yml
.env.example
deploy.md
```

其中：

- `backend/`：Django 源码、`requirements.txt`、`Dockerfile`
- `backend/docker/entrypoint.sh`：容器启动时自动迁移数据库和收集静态文件
- `deploy/nginx/chronocalendar.conf`：Nginx 反向代理配置
- `docker-compose.yml`：定义 `db`、`backend`、`nginx`
- `.env.example`：生产环境变量模板

不建议上传这些内容：

```text
frontend/
demo/
temp/
.venv/
backend/db.sqlite3
backend/staticfiles/
```

原因：

- `frontend/` 对服务器部署后端不是必需
- `db.sqlite3` 是本地开发库，不应该作为正式生产库
- `staticfiles/` 会由容器启动时自动收集生成
- `.venv/` 是本地虚拟环境，容器部署不需要

## 3. Cloudflare 配置

Cloudflare 中应至少存在一条 DNS 记录：

```text
类型：A
名称：thuse
内容：你的服务器公网 IP
代理状态：已代理（橙色云朵）
```

如果你的完整域名是 `thuse.skyislimit.uno`，上面这种配置是合理的。

Cloudflare 的 SSL/TLS 模式使用：

```text
Full
```

`Full` 的含义是：

- 浏览器到 Cloudflare 使用 HTTPS
- Cloudflare 到你的源站服务器也使用 HTTPS

所以你的服务器必须：

- 对外开放 `443/tcp`
- Nginx 监听 `443`
- Nginx 挂载证书和私钥

如果服务器没有这些配置，Cloudflare 虽然能解析到你的服务器，但访问时会报错。

## 4. 服务器准备

本文假设你的服务器系统是 Ubuntu 或 Debian。

安装 Docker 和 Docker Compose：

```bash
sudo apt update
sudo apt install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

确认安装成功：

```bash
docker --version
docker compose version
```

如果你希望普通用户也能直接运行 Docker：

```bash
sudo usermod -aG docker $USER
newgrp docker
```

开放端口：

```text
80/tcp
443/tcp
```

如果你有云厂商安全组，也要同步放行 `80` 和 `443`。

## 5. 上传代码到服务器

你现在本地已经打了一个压缩包 `ChronoCalendar-backend.zip`，这可以直接用。

一种简单做法是：

```bash
mkdir -p ~/workspace/thuapp
cd ~/workspace/thuapp
```

把压缩包上传到这个目录后解压：

```bash
unzip ChronoCalendar-backend.zip
```

解压后建议确认这些文件确实存在：

```bash
ls
ls backend
ls deploy/nginx
```

如果你用 Git 部署，流程可以改成：

```bash
mkdir -p ~/workspace/thuapp
cd ~/workspace/thuapp
git clone <你的仓库地址> .
```

## 6. 创建 `.env`

进入项目根目录：

```bash
cd ~/workspace/thuapp
cp .env.example .env
```

编辑文件：

```bash
nano .env
```

建议至少改这些值：

```text
DJANGO_SECRET_KEY=<替换成一段随机长字符串>
DJANGO_DEBUG=false
DJANGO_ALLOWED_HOSTS=thuse.skyislimit.uno
DJANGO_CSRF_TRUSTED_ORIGINS=https://thuse.skyislimit.uno

CORS_ALLOW_ALL_ORIGINS=false
CORS_ALLOWED_ORIGINS=https://thuse.skyislimit.uno

DB_ENGINE=postgres
POSTGRES_DB=chronocalendar
POSTGRES_USER=chronocalendar
POSTGRES_PASSWORD=<替换成强密码>
POSTGRES_HOST=db
POSTGRES_PORT=5432

DJANGO_SECURE_SSL_REDIRECT=false
DJANGO_SECURE_HSTS_SECONDS=0
DJANGO_SECURE_HSTS_INCLUDE_SUBDOMAINS=false
DJANGO_SECURE_HSTS_PRELOAD=false
```

这些变量的作用：

- `DJANGO_SECRET_KEY`
  Django 的核心密钥，用于签名 session、token 相关安全数据，必须替换，不能继续用示例值
- `DJANGO_DEBUG`
  生产环境必须为 `false`
- `DJANGO_ALLOWED_HOSTS`
  告诉 Django 允许哪些域名访问，否则可能报 `DisallowedHost`
- `DJANGO_CSRF_TRUSTED_ORIGINS`
  告诉 Django 哪些 HTTPS 来源可以安全访问
- `CORS_ALLOWED_ORIGINS`
  约束跨域来源，虽然 APK 本身不一定受浏览器 CORS 限制，但保留正确配置更稳妥
- `POSTGRES_*`
  PostgreSQL 的数据库名、用户名、密码和容器内连接地址
- `DJANGO_SECURE_SSL_REDIRECT`
  是否强制把 HTTP 重定向到 HTTPS
- `DJANGO_SECURE_HSTS_SECONDS`
  是否告诉浏览器未来一段时间内只走 HTTPS

生成新的 `DJANGO_SECRET_KEY`：

```bash
docker run --rm python:3.12-slim python -c "import secrets; print(secrets.token_urlsafe(50))"
```

现在先把：

```text
DJANGO_SECURE_SSL_REDIRECT=false
DJANGO_SECURE_HSTS_SECONDS=0
```

保持为当前值。原因是：在你把 443 和证书真正配好之前，过早强制 HTTPS 会把访问直接重定向到一个还没准备好的入口。

## 7. 为 Cloudflare Full 配置源站 TLS

这是当前部署里最关键的一步。

因为你使用的是 Cloudflare `Full`，所以源站必须有 HTTPS。最简单的方式是使用 Cloudflare Origin Certificate。

### 7.1 在 Cloudflare 创建证书

进入 Cloudflare 面板：

1. 打开 `SSL/TLS`
2. 进入 `Origin Server`
3. 点击 `Create Certificate`
4. Hostnames 填：

```text
thuse.skyislimit.uno
```

5. 生成后保存证书和私钥

### 7.2 在服务器保存证书

进入项目目录并创建证书目录：

```bash
cd ~/workspace/thuapp
mkdir -p deploy/certs
```

保存为：

```text
~/workspace/thuapp/deploy/certs/origin.pem
~/workspace/thuapp/deploy/certs/origin.key
```

限制私钥权限：

```bash
chmod 600 deploy/certs/origin.key
```

### 7.3 修改 `docker-compose.yml`

当前仓库里的 `nginx` 只映射了 `80:80`，需要增加 `443:443`，并挂载证书目录。

把 `nginx` 这一段改成下面这样：

```yaml
nginx:
  image: nginx:1.27-alpine
  restart: unless-stopped
  depends_on:
    - backend
  ports:
    - "80:80"
    - "443:443"
  volumes:
    - ./deploy/nginx/chronocalendar.conf:/etc/nginx/conf.d/default.conf:ro
    - ./deploy/certs:/etc/nginx/certs:ro
    - staticfiles:/staticfiles:ro
```

### 7.4 修改 Nginx 配置

当前 `deploy/nginx/chronocalendar.conf` 只有 80 端口配置，需要改成同时支持：

- 80 端口跳转到 HTTPS
- 443 端口处理真实请求

建议改成：

```nginx
upstream chronocalendar_backend {
    server backend:8000;
}

server {
    listen 80;
    server_name thuse.skyislimit.uno;
    return 301 https://$host$request_uri;
}

server {
    listen 443 ssl;
    server_name thuse.skyislimit.uno;

    ssl_certificate /etc/nginx/certs/origin.pem;
    ssl_certificate_key /etc/nginx/certs/origin.key;

    client_max_body_size 10m;

    location /static/ {
        alias /staticfiles/;
        access_log off;
        expires 30d;
    }

    location /healthz/ {
        proxy_pass http://chronocalendar_backend;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }

    location / {
        proxy_pass http://chronocalendar_backend;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto https;
    }
}
```

## 8. 启动服务

确认 `.env`、证书、`docker-compose.yml`、Nginx 配置都已经准备好后，在项目根目录运行：

```bash
cd ~/workspace/thuapp
docker compose up -d --build
```

这个命令会启动：

- `db`
- `backend`
- `nginx`

后端容器启动时会自动执行：

```text
python manage.py migrate --noinput
python manage.py collectstatic --noinput
gunicorn config.wsgi:application
```

查看容器状态：

```bash
docker compose ps
```

查看日志：

```bash
docker compose logs -f db
docker compose logs -f backend
docker compose logs -f nginx
```

## 9. 首次验证

先在服务器本机验证端口监听：

```bash
sudo ss -tulpn | grep ':80'
sudo ss -tulpn | grep ':443'
```

再验证 Nginx：

```bash
curl http://127.0.0.1/healthz/
curl -k https://127.0.0.1/healthz/
```

预期应该能返回：

```json
{"status": "ok"}
```

然后从服务器外部或你本机验证：

```bash
curl https://thuse.skyislimit.uno/healthz/
```

再测 API 路径：

```bash
curl https://thuse.skyislimit.uno/api/v1/
```

这里返回 `404` 或认证失败不一定有问题，关键是请求已经通到 Django，而不是 Cloudflare 报错或 Nginx 502。

## 10. 开启 Django HTTPS 安全项

当你确认下面这条已经稳定可访问：

```text
https://thuse.skyislimit.uno/healthz/
```

再把 `.env` 中这几个值改成：

```text
DJANGO_SECURE_SSL_REDIRECT=true
DJANGO_SECURE_HSTS_SECONDS=31536000
DJANGO_SECURE_HSTS_INCLUDE_SUBDOMAINS=false
DJANGO_SECURE_HSTS_PRELOAD=false
```

然后重启服务：

```bash
docker compose up -d
```

这样 Django 会更严格地按照 HTTPS 方式工作。

## 11. 常见问题

### 11.1 Cloudflare 返回 521

通常表示 Cloudflare 连不上源站。

检查：

```bash
docker compose ps
sudo ss -tulpn | grep ':443'
```

重点确认：

- 服务器 443 端口是否监听
- 云安全组是否放行 443
- Nginx 容器是否正常启动

### 11.2 Cloudflare 返回 525 或 526

通常表示 TLS 握手或证书有问题。

检查：

- `origin.pem` 和 `origin.key` 是否对应
- Nginx 配置中的证书路径是否正确
- Cloudflare 面板中域名是否和证书中的 Hostname 一致

### 11.3 返回 502 Bad Gateway

通常表示 Nginx 正常，但后端服务没有正常提供 8000 端口。

检查：

```bash
docker compose logs -f backend
```

重点看：

- 数据库连接失败
- migrations 执行失败
- `.env` 缺失关键变量

### 11.4 报 `DisallowedHost`

说明 `DJANGO_ALLOWED_HOSTS` 配置不对。

应改成：

```text
DJANGO_ALLOWED_HOSTS=thuse.skyislimit.uno
```

改完后重启：

```bash
docker compose up -d
```

### 11.5 改了数据库密码后数据库起不来

如果 PostgreSQL 卷已经初始化过，单独改 `.env` 中的 `POSTGRES_PASSWORD` 不会自动改旧数据库里的密码。

如果你还没有正式数据，可以删除卷重建：

```bash
docker compose down -v
docker compose up -d --build
```

这会删除数据库内容，已有正式数据时不要这样做。

## 12. 更新部署

以后更新后端时，进入目录执行：

```bash
cd ~/workspace/thuapp
docker compose up -d --build
```

如果你使用 Git 管理代码，则更新步骤是：

```bash
cd ~/workspace/thuapp
git pull
docker compose up -d --build
```

更新后再次检查：

```bash
docker compose ps
curl -k https://127.0.0.1/healthz/
curl https://thuse.skyislimit.uno/healthz/
```

## 13. 前端 APK 打包

当后端 HTTPS 验证通过后，再打包前端 APK。

注意：`API_BASE_URL` 只写根地址，不带 `/api/v1`。

```powershell
cd frontend
flutter clean
flutter pub get
flutter build apk --release --dart-define=API_BASE_URL=https://thuse.skyislimit.uno
```

生成的 APK 通常在：

```text
frontend/build/app/outputs/flutter-apk/app-release.apk
```
