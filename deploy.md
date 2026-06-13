# ChronoCalendar 部署说明

本文按当前仓库的新版本编写，重点适配你的实际限制：服务器不能登录 Git 再 `clone`，只能由你在本地打包后手动 SFTP 上传。

默认后端域名：

```text
https://thuse.skyislimit.uno
```

如果域名变化，把文档里的 `thuse.skyislimit.uno` 替换成真实域名即可。前端 `API_BASE_URL` 只写域名根地址，不要带 `/api/v1`。

## 1. 当前部署形态

仓库根目录已有 Docker 部署文件：

```text
docker-compose.yml
backend/Dockerfile
backend/docker/entrypoint.sh
deploy/nginx/chronocalendar.conf
.env.example
```

`docker compose` 会启动三个服务：

```text
db       PostgreSQL 16
backend  Django + Gunicorn，容器内监听 8000
nginx    容器 Nginx，当前默认只映射服务器 80 端口
```

后端接口全部在：

```text
/api/v1/
```

健康检查：

```text
/healthz/
```

容器启动时 `backend/docker/entrypoint.sh` 会自动执行：

```text
python manage.py migrate --noinput
python manage.py collectstatic --noinput
gunicorn config.wsgi:application
```

## 2. 本地打包命令

在 Windows PowerShell 中进入项目根目录：

```powershell
cd E:\Codes\android\final_hw\ChronoCalendar
```

执行下面这段命令，会生成一个适合 SFTP 上传的 zip 包，只包含后端部署必要文件，不包含 `frontend/`、`demo/`、`.git/`、本地数据库、虚拟环境和证书私钥目录。

```powershell
$ErrorActionPreference = "Stop"
$zip = "ChronoCalendar-deploy-$(Get-Date -Format yyyyMMdd-HHmmss).zip"
$stage = Join-Path $env:TEMP "ChronoCalendar-deploy"
Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $stage | Out-Null

robocopy backend (Join-Path $stage "backend") /E /XD .venv venv env __pycache__ staticfiles media /XF db.sqlite3 *.pyc *.pyo *.pyd *.sqlite3-journal | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy backend failed: $LASTEXITCODE" }

robocopy deploy (Join-Path $stage "deploy") /E /XD certs | Out-Null
if ($LASTEXITCODE -ge 8) { throw "robocopy deploy failed: $LASTEXITCODE" }

Copy-Item -Path @("docker-compose.yml", ".env.example", "README.md", "api.md", "deploy.md") -Destination $stage
Compress-Archive -Path "$stage\*" -DestinationPath $zip -Force
Write-Host "Created $zip"
```

生成的文件名类似：

```text
ChronoCalendar-deploy-20260606-153000.zip
```

用 SFTP 把这个 zip 上传到服务器，例如：

```text
~/workspace/thuapp/ChronoCalendar-deploy-20260606-153000.zip
```

## 3. 服务器首次准备

本文假设服务器是 Ubuntu/Debian，并且你可以通过 SSH 执行命令。

安装 Docker 和 Docker Compose 插件：

```bash
sudo apt update
sudo apt install -y ca-certificates curl unzip
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

如果希望当前普通用户直接运行 Docker：

```bash
sudo usermod -aG docker $USER
newgrp docker
```

服务器防火墙或云安全组至少放行：

```text
80/tcp
```

当前仓库的默认 `docker-compose.yml` 只映射 `80:80`。如果你之后自己给源站配置 443，再额外放行 `443/tcp`。

## 4. 上传并解压

服务器上创建部署目录：

```bash
mkdir -p ~/workspace/thuapp
cd ~/workspace/thuapp
```

用 SFTP 上传 zip 到这个目录后，解压最新上传的包：

```bash
latest_zip=$(ls -t ChronoCalendar-deploy-*.zip | head -n 1)
unzip -o "$latest_zip" -d ~/workspace/thuapp
```

确认关键文件存在：

```bash
ls
ls backend
ls deploy/nginx
```

应该能看到：

```text
backend/
deploy/
docker-compose.yml
.env.example
README.md
api.md
deploy.md
```

## 5. 创建生产 `.env`

首次部署时：

```bash
cd ~/workspace/thuapp
cp .env.example .env
nano .env
```

建议至少配置：

```text
DJANGO_SECRET_KEY=<替换成随机长密钥>
DJANGO_DEBUG=false
DJANGO_ALLOWED_HOSTS=thuse.skyislimit.uno,127.0.0.1,localhost
DJANGO_CSRF_TRUSTED_ORIGINS=https://thuse.skyislimit.uno,http://127.0.0.1,http://localhost
DJANGO_SECURE_SSL_REDIRECT=false
DJANGO_SECURE_HSTS_SECONDS=0
DJANGO_SECURE_HSTS_INCLUDE_SUBDOMAINS=false
DJANGO_SECURE_HSTS_PRELOAD=false
DJANGO_TIME_ZONE=UTC

CORS_ALLOW_ALL_ORIGINS=false
CORS_ALLOWED_ORIGINS=https://thuse.skyislimit.uno

DB_ENGINE=postgres
POSTGRES_DB=chronocalendar
POSTGRES_USER=chronocalendar
POSTGRES_PASSWORD=<替换成强密码>
POSTGRES_HOST=db
POSTGRES_PORT=5432
```

生成 `DJANGO_SECRET_KEY`：

```bash
docker run --rm python:3.12-slim python -c "import secrets; print(secrets.token_urlsafe(50))"
```

AI 助手说明：

- Agent 的 LLM/ASR/TTS 配置遵循同一优先级：用户个人配置 > 服务器 `.env` 全局默认 > 代码中的缺省值。
- `.env` 可用于设置全局默认 Base URL、API Key 和模型名；客户端“AI 配置”页保存的是当前账号的覆盖配置。
- 如果用户没有配置个人 API Key，会回退到 `.env` 中对应的全局 API Key；如果两边都没有 Key，则返回“AI 未配置”，不会让接口 500。
- 如果 `.env` 中 Base URL 或模型名留空，会继续使用代码中的缺省值。
- 不要把真实 API Key 写进 `.env.example`、部署文档或仓库。

## 6. HTTPS 与 Cloudflare

当前仓库默认容器 Nginx 只监听并映射 80 端口：

```yaml
ports:
  - "80:80"
```

因此最省事的方式是：

```text
浏览器/APP -> Cloudflare HTTPS -> 源站服务器 HTTP:80 -> 容器 Nginx -> Django
```

这种情况下 Cloudflare SSL/TLS 模式可先用 `Flexible`。`.env` 中保持：

```text
DJANGO_SECURE_SSL_REDIRECT=false
DJANGO_SECURE_HSTS_SECONDS=0
```

如果你必须使用 Cloudflare `Full` 或 `Full strict`，源站也要提供 HTTPS。那就需要你额外修改：

```text
docker-compose.yml
deploy/nginx/chronocalendar.conf
deploy/certs/origin.pem
deploy/certs/origin.key
```

当前仓库没有默认启用 443，所以不要只在 Cloudflare 面板切到 `Full`，否则很容易出现 525/526。

## 7. 启动服务

在服务器项目目录运行：

```bash
cd ~/workspace/thuapp
docker compose up -d --build
```

注意 `--build` 要跟在 `up` 后面。不要写成 `docker compose --build`，那会报 `unknown flag: --build`。

查看状态：

```bash
docker compose ps
```

查看日志：

```bash
docker compose logs -f backend
docker compose logs -f nginx
docker compose logs -f db
```

本机验证：

```bash
curl http://127.0.0.1/healthz/
```

预期返回：

```json
{"status": "ok"}
```

外部验证：

```bash
curl https://thuse.skyislimit.uno/healthz/
```

如果 Cloudflare 还没配好，也可以先直接测服务器公网 IP 的 80 端口。

## 8. 更新部署

以后每次更新代码：

1. 在本地重新执行第 2 节的 PowerShell 打包命令。
2. 用 SFTP 把新的 zip 上传到 `~/workspace/thuapp/`。
3. 在服务器解压覆盖。
4. 重新构建并启动容器。

服务器命令：

```bash
cd ~/workspace/thuapp
latest_zip=$(ls -t ChronoCalendar-deploy-*.zip | head -n 1)
unzip -o "$latest_zip" -d ~/workspace/thuapp
docker compose up -d --build
docker compose ps
curl http://127.0.0.1/healthz/
```

注意：

- `.env` 不在打包文件里，更新代码不会覆盖服务器上的 `.env`。
- PostgreSQL 数据保存在 Docker volume `postgres_data`，普通更新不会清空数据。
- 不要在已有正式数据时执行 `docker compose down -v`，那会删除数据库卷。

## 9. 前端 APK 打包

后端域名可访问后，在本地构建 APK。

```powershell
cd E:\Codes\android\final_hw\ChronoCalendar\frontend
D:\flutter\flutter\bin\flutter.bat clean
D:\flutter\flutter\bin\flutter.bat pub get
D:\flutter\flutter\bin\flutter.bat build apk --release --dart-define=API_BASE_URL=https://thuse.skyislimit.uno
```

生成位置：

```text
frontend/build/app/outputs/flutter-apk/app-release.apk
```

如果后端还只能用 HTTP 测试，`API_BASE_URL` 可以临时写成：

```text
http://你的服务器IP
```

正式给用户使用时建议走 HTTPS 域名。

## 10. 常见问题

### 10.1 502 Bad Gateway

Nginx 能访问，但后端容器没正常提供 8000。

检查：

```bash
docker compose ps
docker compose logs -f backend
```

重点看数据库连接、migrations、环境变量是否报错。

如果日志里是：

```text
exec /app/docker/entrypoint.sh: no such file or directory
```

通常是 Windows 打包后 shell 脚本带了 CRLF 行尾，Linux 容器执行 shebang 时会失败。当前 Dockerfile 已经在构建时自动清理 `backend/docker/entrypoint.sh` 行尾。重新用第 2 节命令打包、SFTP 上传，然后执行：

```bash
cd ~/workspace/thuapp
latest_zip=$(ls -t ChronoCalendar-deploy-*.zip | head -n 1)
unzip -o "$latest_zip" -d ~/workspace/thuapp
docker compose up -d --build
docker compose logs -f backend
```

等 backend 不再重启后，再测：

```bash
curl http://127.0.0.1/healthz/
```

### 10.2 DisallowedHost

`DJANGO_ALLOWED_HOSTS` 没有包含当前访问域名。

修改 `.env`：

```text
DJANGO_ALLOWED_HOSTS=thuse.skyislimit.uno,127.0.0.1,localhost
```

然后重启：

```bash
docker compose up -d
```

### 10.3 Cloudflare 521

Cloudflare 连不上源站。

检查：

```bash
docker compose ps
sudo ss -tulpn | grep ':80'
```

确认服务器安全组、防火墙和容器端口映射都放行了 80。

### 10.4 Cloudflare 525/526

通常是你把 Cloudflare 切到了 `Full` 或 `Full strict`，但源站没有正确配置 HTTPS 证书。

当前默认 compose 只支持 80。如果暂时不配置源站证书，把 Cloudflare SSL/TLS 模式调回 `Flexible`。

### 10.5 修改 PostgreSQL 密码后数据库起不来

PostgreSQL volume 初始化后，单独改 `.env` 的 `POSTGRES_PASSWORD` 不会自动修改旧数据库里的密码。

如果还没有正式数据，可以删除卷重建：

```bash
docker compose down -v
docker compose up -d --build
```

已有正式数据时不要这样做。
