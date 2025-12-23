# MinIO Setup dengan Docker

Panduan setup MinIO menggunakan Docker Compose dengan network Traefik.

## Prasyarat

Sebelum memulai, pastikan server Anda sudah memiliki:

1. **Docker** (versi 29.1.2 atau lebih baru)
   ```bash
   docker --version
   ```

2. **Docker Compose** (versi 2.0 atau lebih baru)
   ```bash
   docker compose version
   ```

3. **Network Traefik** yang sudah dibuat
   ```bash
   docker network ls | grep traefik-network
   ```
   
   Jika network belum ada, buat dengan perintah:
   ```bash
   docker network create traefik-network
   ```

## Struktur File

```
minio/
├── docker/
│   └── docker-compose.yml    # Konfigurasi Docker Compose
├── cors.json                 # Konfigurasi CORS untuk MinIO
└── README.md                 # File ini
```

## Konfigurasi

### 1. Volume Storage

Pastikan direktori untuk data MinIO sudah ada dan memiliki permission yang tepat:

```bash
sudo mkdir -p /home/msiserver/minio/data
sudo chown -R $USER:$USER /home/msiserver/minio/data
```

**Catatan:** Sesuaikan path `/home/msiserver/minio/data` sesuai dengan struktur direktori di server Anda.

### 2. Credentials

File `docker-compose.yml` menggunakan credentials default:
- **Username:** `admin`
- **Password:** `supersecurepass123`

**⚠️ PENTING:** Ganti password default sebelum deploy ke production!

Untuk mengubah credentials, edit file `docker/docker-compose.yml`:
```yaml
environment:
  MINIO_ROOT_USER: your-username
  MINIO_ROOT_PASSWORD: your-secure-password
```

### 3. Port Configuration

MinIO menggunakan port berikut:
- **Port 9508:** MinIO S3 API (mapping ke port 9000 di container)
- **Port 9507:** MinIO Console (mapping ke port 9001 di container)

Pastikan port-port ini tidak digunakan oleh aplikasi lain di server.

## Setup di Server

### Langkah 1: Clone atau Upload File

Jika menggunakan Git:
```bash
git clone <repository-url>
cd minio
```

Atau upload file-file berikut ke server:
- `docker/docker-compose.yml`
- `cors.json`

### Langkah 2: Verifikasi Network Traefik

Pastikan network `traefik-network` sudah ada:
```bash
docker network inspect traefik-network
```

Jika belum ada, buat network:
```bash
docker network create traefik-network
```

### Langkah 3: Buat Direktori Data

```bash
mkdir -p /home/msiserver/minio/data
chmod -R 755 /home/msiserver/minio/data
```

### Langkah 4: Jalankan MinIO

Masuk ke direktori yang berisi file `docker-compose.yml`:
```bash
cd docker
```

Jalankan dengan Docker Compose:
```bash
docker compose up -d
```

Atau jika menggunakan `docker-compose` (versi lama):
```bash
docker-compose up -d
```

### Langkah 5: Verifikasi Container Berjalan

```bash
docker ps | grep minio
```

Atau cek status container:
```bash
docker compose ps
```

### Langkah 6: Cek Logs (Opsional)

```bash
docker compose logs -f minio
```

## Konfigurasi CORS

File `cors.json` sudah dikonfigurasi untuk mengizinkan akses dari semua origin. Untuk mengatur CORS di MinIO:

1. Login ke MinIO Console (http://server-ip:9507)
2. Masuk ke **Settings** > **CORS**
3. Import file `cors.json` atau konfigurasi manual sesuai kebutuhan

Atau menggunakan MinIO Client (mc):
```bash
# Install MinIO Client jika belum ada
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# Konfigurasi alias
mc alias set myminio http://localhost:9508 admin supersecurepass123

# Set CORS
mc admin config set myminio api cors_config cors.json
```

## Setup Traefik dan Cloudflare Tunnel

MinIO dikonfigurasi untuk diakses melalui Traefik reverse proxy dengan Cloudflare Tunnel. Ini memungkinkan akses via subdomain dengan SSL/TLS otomatis.

### Prasyarat

1. **Traefik** sudah berjalan di server dan terhubung ke network `traefik-network`
2. **Cloudflare Tunnel** sudah dikonfigurasi dan berjalan
3. **Dua subdomain** sudah terdaftar di DNS Cloudflare:
   - `minio-api.yourdomain.com` untuk S3 API
   - `minio-console.yourdomain.com` untuk Console

### Langkah 1: Konfigurasi Subdomain di docker-compose.yml

Edit file `docker/docker-compose.yml` dan sesuaikan dengan konfigurasi Traefik Anda:

1. **Ganti subdomain** sesuai dengan domain Anda:
   ```yaml
   # Ganti 'yourdomain.com' dengan domain Anda
   - "traefik.http.routers.minio-api.rule=Host(`minio-api.yourdomain.com`)"
   - "traefik.http.routers.minio-console.rule=Host(`minio-console.yourdomain.com`)"
   ```

2. **Sesuaikan entrypoint** jika berbeda (cek konfigurasi Traefik Anda):
   ```yaml
   # Default: websecure (untuk HTTPS)
   # Jika berbeda, ganti dengan entrypoint Traefik Anda
   - "traefik.http.routers.minio-api.entrypoints=websecure"
   - "traefik.http.routers.minio-console.entrypoints=websecure"
   ```

3. **Sesuaikan certificate resolver** jika berbeda:
   ```yaml
   # Default: letsencrypt
   # Jika berbeda, ganti dengan certificate resolver Traefik Anda
   - "traefik.http.routers.minio-api.tls.certresolver=letsencrypt"
   - "traefik.http.routers.minio-console.tls.certresolver=letsencrypt"
   ```

**Contoh:**
- Jika domain Anda adalah `example.com`, maka:
  - `minio-api.example.com` untuk S3 API
  - `minio-console.example.com` untuk Console

**⚠️ PENTING:** 
- Pastikan entrypoint dan certificate resolver sesuai dengan konfigurasi Traefik yang sudah ada
- Jika Traefik Anda menggunakan nama berbeda, sesuaikan label-label tersebut

### Langkah 2: Konfigurasi DNS di Cloudflare

1. Login ke **Cloudflare Dashboard**
2. Pilih domain Anda
3. Masuk ke **DNS** > **Records**
4. Tambahkan 2 record CNAME:

   **Record 1 - S3 API:**
   - **Type:** CNAME
   - **Name:** `minio-api` (atau `minio-api.yourdomain.com`)
   - **Target:** `your-cloudflare-tunnel-id.cfargotunnel.com`
   - **Proxy status:** Proxied (orange cloud)

   **Record 2 - Console:**
   - **Type:** CNAME
   - **Name:** `minio-console` (atau `minio-console.yourdomain.com`)
   - **Target:** `your-cloudflare-tunnel-id.cfargotunnel.com`
   - **Proxy status:** Proxied (orange cloud)

### Langkah 3: Konfigurasi Cloudflare Tunnel

Edit file konfigurasi Cloudflare Tunnel (biasanya `config.yml` di folder cloudflared):

```yaml
tunnel: your-tunnel-id
credentials-file: /path/to/credentials.json

ingress:
  # MinIO S3 API
  - hostname: minio-api.yourdomain.com
    service: http://traefik:80
    originRequest:
      noHappyEyeballs: true
  
  # MinIO Console
  - hostname: minio-console.yourdomain.com
    service: http://traefik:80
    originRequest:
      noHappyEyeballs: true
  
  # Catch-all rule (harus di akhir)
  - service: http_status:404
```

**Catatan:** 
- Ganti `yourdomain.com` dengan domain Anda
- Pastikan Traefik container dapat diakses di `http://traefik:80` dari network yang sama
- Jika Traefik menggunakan port lain, sesuaikan URL service

### Langkah 4: Restart Services

Setelah mengubah konfigurasi:

1. **Restart Cloudflare Tunnel:**
   ```bash
   # Jika menggunakan systemd
   sudo systemctl restart cloudflared
   
   # Atau jika menggunakan Docker
   docker restart cloudflared
   docker compose restart cloudflared
   ```

2. **Restart MinIO:**
   ```bash
   cd docker
   docker compose restart
   ```

3. **Verifikasi Traefik mendeteksi MinIO:**
   ```bash
   docker logs traefik | grep minio
   ```

### Langkah 5: Verifikasi Konfigurasi Traefik

Pastikan Traefik Anda memiliki konfigurasi berikut:

1. **Entrypoint `websecure`** untuk HTTPS (port 443)
2. **Certificate Resolver** (misalnya `letsencrypt`) untuk SSL/TLS otomatis
3. **Docker provider** aktif untuk auto-discovery

Contoh konfigurasi Traefik (`traefik.yml`):
```yaml
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

certificatesResolvers:
  letsencrypt:
    acme:
      email: your-email@example.com
      storage: /letsencrypt/acme.json
      httpChallenge:
        entryPoint: web

providers:
  docker:
    endpoint: "unix:///var/run/docker.sock"
    exposedByDefault: false
    network: traefik-network
```

## Akses MinIO

### Via Subdomain (Recommended)

Setelah setup Traefik dan Cloudflare Tunnel selesai:

**MinIO Console (Web UI):**
```
https://minio-console.yourdomain.com
```
- Username: `admin`
- Password: `Rubysa179596!` (atau sesuai konfigurasi Anda)

**MinIO S3 API:**
```
https://minio-api.yourdomain.com
```

### Akses Langsung (Alternatif)

Jika port mapping masih aktif (uncomment di docker-compose.yml):

**MinIO Console (Web UI):**
```
http://server-ip:9507
```

**MinIO S3 API:**
```
http://server-ip:9508
```

### Dari Container Lain di Network Traefik

Jika ada container lain di network `traefik-network`, Anda dapat mengakses MinIO menggunakan:
- **Hostname:** `cloudstorage-minio` (nama container)
- **Port:** `9000` (S3 API) atau `9001` (Console)

Contoh URL dari container lain:
```
http://cloudstorage-minio:9000  # S3 API
http://cloudstorage-minio:9001  # Console
```

## Management Commands

### Stop MinIO
```bash
cd docker
docker compose stop
```

### Start MinIO
```bash
cd docker
docker compose start
```

### Restart MinIO
```bash
cd docker
docker compose restart
```

### Stop dan Hapus Container
```bash
cd docker
docker compose down
```

**⚠️ PERINGATAN:** Perintah `docker compose down` akan menghapus container, tetapi data di volume tetap tersimpan.

### Update MinIO ke Versi Terbaru
```bash
cd docker
docker compose pull
docker compose up -d
```

## Troubleshooting

### Container Tidak Berjalan

1. Cek logs:
   ```bash
   docker compose logs minio
   ```

2. Cek apakah port sudah digunakan:
   ```bash
   sudo netstat -tulpn | grep -E '9507|9508'
   ```

3. Cek permission direktori data:
   ```bash
   ls -la /home/msiserver/minio/data
   ```

### Network Error

Jika ada error terkait network `traefik-network`:

1. Verifikasi network ada:
   ```bash
   docker network ls
   ```

2. Cek detail network:
   ```bash
   docker network inspect traefik-network
   ```

3. Jika network tidak ada, buat:
   ```bash
   docker network create traefik-network
   ```

### Tidak Bisa Akses dari Container Lain

Pastikan container lain juga terhubung ke network `traefik-network`:
```bash
docker network connect traefik-network <nama-container-lain>
```

Atau tambahkan di `docker-compose.yml` container lain:
```yaml
networks:
  - traefik-network
```

### Traefik Tidak Mendeteksi MinIO

1. **Cek label Traefik di container:**
   ```bash
   docker inspect cloudstorage-minio | grep -A 20 Labels
   ```

2. **Verifikasi Traefik membaca Docker provider:**
   ```bash
   docker logs traefik | grep -i "docker\|minio"
   ```

3. **Pastikan Traefik terhubung ke network yang sama:**
   ```bash
   docker network inspect traefik-network | grep -A 5 cloudstorage-minio
   docker network inspect traefik-network | grep -A 5 traefik
   ```

4. **Cek entrypoint dan certificate resolver:**
   - Pastikan entrypoint `websecure` ada di Traefik
   - Pastikan certificate resolver `letsencrypt` dikonfigurasi dengan benar

5. **Restart Traefik:**
   ```bash
   docker restart traefik
   ```

### Subdomain Tidak Bisa Diakses

1. **Cek DNS di Cloudflare:**
   - Pastikan CNAME record sudah dibuat
   - Pastikan proxy status aktif (orange cloud)
   - Tunggu beberapa menit untuk propagasi DNS

2. **Cek Cloudflare Tunnel:**
   ```bash
   # Jika menggunakan systemd
   sudo systemctl status cloudflared
   sudo journalctl -u cloudflared -f
   
   # Atau jika menggunakan Docker
   docker logs cloudflared
   ```

3. **Verifikasi konfigurasi Cloudflare Tunnel:**
   - Pastikan hostname di config.yml sesuai dengan subdomain
   - Pastikan service mengarah ke `http://traefik:80` (atau port Traefik yang sesuai)

4. **Test koneksi dari server:**
   ```bash
   # Test apakah Traefik bisa diakses
   curl -H "Host: minio-api.yourdomain.com" http://localhost
   curl -H "Host: minio-console.yourdomain.com" http://localhost
   ```

5. **Cek SSL Certificate:**
   - Pastikan Let's Encrypt certificate sudah terbit
   - Cek di Traefik dashboard atau logs

### Error 404 atau Bad Gateway

1. **Cek apakah MinIO container berjalan:**
   ```bash
   docker ps | grep minio
   ```

2. **Cek routing Traefik:**
   ```bash
   docker exec traefik wget -O- http://cloudstorage-minio:9000
   docker exec traefik wget -O- http://cloudstorage-minio:9001
   ```

3. **Verifikasi label Traefik:**
   - Pastikan `traefik.enable=true` ada
   - Pastikan hostname di rule sesuai dengan subdomain
   - Pastikan port service sesuai (9000 untuk API, 9001 untuk Console)

4. **Cek Traefik dashboard:**
   - Akses Traefik dashboard (biasanya di `http://traefik:8080`)
   - Lihat apakah router dan service MinIO terdeteksi

### SSL Certificate Tidak Terbit

1. **Cek Let's Encrypt logs di Traefik:**
   ```bash
   docker logs traefik | grep -i acme
   docker logs traefik | grep -i certificate
   ```

2. **Pastikan email di certificate resolver valid:**
   ```yaml
   certificatesResolvers:
     letsencrypt:
       acme:
         email: your-email@example.com  # Pastikan email valid
   ```

3. **Cek rate limit Let's Encrypt:**
   - Let's Encrypt memiliki rate limit
   - Jika terlalu banyak request, tunggu beberapa jam

4. **Gunakan DNS challenge jika HTTP challenge gagal:**
   ```yaml
   certificatesResolvers:
     letsencrypt:
       acme:
         email: your-email@example.com
         storage: /letsencrypt/acme.json
         dnsChallenge:
           provider: cloudflare
           resolvers:
             - "1.1.1.1:53"
             - "1.0.0.1:53"
   ```

## Keamanan

1. **Ganti Password Default:** Pastikan mengubah `MINIO_ROOT_PASSWORD` sebelum production
2. **Firewall:** Konfigurasi firewall untuk membatasi akses ke port 9507 dan 9508
3. **SSL/TLS:** Untuk production, gunakan reverse proxy (seperti Traefik) dengan SSL certificate
4. **Backup:** Lakukan backup rutin pada direktori `/home/msiserver/minio/data`

## Backup dan Restore

### Backup Data
```bash
tar -czf minio-backup-$(date +%Y%m%d).tar.gz /home/msiserver/minio/data
```

### Restore Data
```bash
# Stop MinIO
docker compose stop

# Restore data
tar -xzf minio-backup-YYYYMMDD.tar.gz -C /

# Start MinIO
docker compose start
```

## Informasi Tambahan

- **Dokumentasi MinIO:** https://min.io/docs/
- **Docker Compose Version:** Kompatibel dengan Docker 29.1.2+
- **Network:** Menggunakan external network `traefik-network`

## Support

Jika mengalami masalah, cek:
1. Logs container: `docker compose logs minio`
2. Status container: `docker compose ps`
3. Dokumentasi MinIO: https://min.io/docs/



2. Konfigurasi lengkap yang disarankan
Untuk akses dari dalam Docker network (infra_net):

# MinIO Configuration
MINIO_ENABLED=true
S3_PROVIDER=minio
S3_REGION=us-east-1
S3_BUCKET=msi-quotation

# Credentials
S3_ACCESS_KEY_ID=admin
S3_SECRET_ACCESS_KEY=Rubysa179596!

# Endpoint (internal Docker network)
S3_ENDPOINT=http://cloudstorage-minio:9000
S3_BASE_URL=http://cloudstorage-minio:9000
S3_SSL_ENABLED=false
S3_FORCE_PATH_STYLE=true
S3_SIGNATURE_VERSION=v4

# MinIO Private Bucket Configuration
S3_BUCKET_PRIVATE=msi-sso-private
MINIO_BUCKET_PRIVATE=msi-sso-private
AWS_BUCKET_PRIVATE=msi-sso-private


Untuk akses dari luar Docker network (via domain):
# MinIO Configuration
MINIO_ENABLED=true
S3_PROVIDER=minio
S3_REGION=us-east-1
S3_BUCKET=msi-quotation

# Credentials
S3_ACCESS_KEY_ID=admin
S3_SECRET_ACCESS_KEY=Rubysa179596!

# Endpoint (public domain)
S3_ENDPOINT=https://minio-api.motorsights.com
S3_BASE_URL=https://minio-api.motorsights.com
S3_SSL_ENABLED=true  # ← HARUS true untuk HTTPS
S3_FORCE_PATH_STYLE=true
S3_SIGNATURE_VERSION=v4

# MinIO Private Bucket Configuration
S3_BUCKET_PRIVATE=msi-sso-private
MINIO_BUCKET_PRIVATE=msi-sso-private
AWS_BUCKET_PRIVATE=msi-sso-private
