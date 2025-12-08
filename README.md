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
sudo mkdir -p /home/msiserver/cloudstorage/data
sudo chown -R $USER:$USER /home/msiserver/cloudstorage/data
```

**Catatan:** Sesuaikan path `/home/msiserver/cloudstorage/data` sesuai dengan struktur direktori di server Anda.

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
mkdir -p /home/msiserver/cloudstorage/data
chmod -R 755 /home/msiserver/cloudstorage/data
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

## Akses MinIO

### MinIO Console (Web UI)
```
http://server-ip:9507
```
- Username: `admin`
- Password: `supersecurepass123` (atau sesuai konfigurasi Anda)

### MinIO S3 API
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
   ls -la /home/msiserver/cloudstorage/data
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

## Keamanan

1. **Ganti Password Default:** Pastikan mengubah `MINIO_ROOT_PASSWORD` sebelum production
2. **Firewall:** Konfigurasi firewall untuk membatasi akses ke port 9507 dan 9508
3. **SSL/TLS:** Untuk production, gunakan reverse proxy (seperti Traefik) dengan SSL certificate
4. **Backup:** Lakukan backup rutin pada direktori `/home/msiserver/cloudstorage/data`

## Backup dan Restore

### Backup Data
```bash
tar -czf minio-backup-$(date +%Y%m%d).tar.gz /home/msiserver/cloudstorage/data
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

