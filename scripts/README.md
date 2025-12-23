# Script Download Data MinIO

Script untuk download data dari MinIO ke laptop Anda.

## Metode yang Tersedia

### 1. Download dari Named Volume (minio_data:/data)

**File:** `download-minio-data.sh`

Menggunakan temporary container untuk mengakses Docker volume.

```bash
# Download semua data
./scripts/download-minio-data.sh

# Atau spesifik direktori output
./scripts/download-minio-data.sh ~/Downloads/minio-backup
```

**Cara Manual:**
```bash
# Buat temporary container untuk akses volume
docker run --rm \
  -v minio_minio_data:/source:ro \
  -v "$(pwd)/backup:/backup" \
  alpine sh -c "cp -r /source/* /backup/"

# Atau langsung dari container yang berjalan
docker cp cloudstorage-minio:/data ./minio-backup
```

### 2. Download dari Bind Mount

**File:** `download-via-bind-mount.sh`

Jika menggunakan bind mount (`/home/msiserver/minio/data`), gunakan script ini.

```bash
# Download dari bind mount (harus dijalankan di server)
./scripts/download-via-bind-mount.sh

# Atau spesifik direktori output
./scripts/download-via-bind-mount.sh ~/Downloads/minio-backup
```

**Cara Manual:**
```bash
# Jika di server, langsung copy
cp -r /home/msiserver/minio/data ~/Downloads/minio-backup

# Jika dari laptop, gunakan SCP/RSYNC
scp -r user@server:/home/msiserver/minio/data ~/Downloads/minio-backup
# atau
rsync -avz user@server:/home/msiserver/minio/data/ ~/Downloads/minio-backup/
```

### 3. Download via MinIO Client (RECOMMENDED) ⭐

**File:** `download-via-minio-client.sh`

**Cara terbaik** karena langsung download dari bucket MinIO, bukan dari volume.

**Install MinIO Client dulu:**
```bash
# macOS
brew install minio/stable/mc

# Linux
wget https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/

# Windows
choco install minio-client
```

**Gunakan script:**
```bash
# Download semua file dari bucket default (msi-quotation)
./scripts/download-via-minio-client.sh

# Atau spesifik bucket dan output directory
./scripts/download-via-minio-client.sh ~/Downloads/minio-files msi-sso-private
```

**Cara Manual dengan MinIO Client:**
```bash
# 1. Setup alias
mc alias set myminio https://minio-api.motorsights.com admin Rubysa179596!

# 2. List bucket
mc ls myminio

# 3. Download semua file dari bucket
mc mirror myminio/msi-quotation ~/Downloads/minio-files

# 4. Download file spesifik
mc cp myminio/msi-quotation/path/to/file.txt ~/Downloads/

# 5. Download folder spesifik
mc cp --recursive myminio/msi-quotation/folder/ ~/Downloads/folder/
```

## Perbandingan Metode

| Metode | Keuntungan | Kekurangan |
|--------|-----------|------------|
| **Named Volume** | Data mentah, semua file | Perlu akses Docker, format internal MinIO |
| **Bind Mount** | Data mentah, semua file | Harus di server atau pakai SCP/RSYNC |
| **MinIO Client** ⭐ | Paling praktis, format normal, bisa pilih bucket | Perlu install mc |

## Rekomendasi

**Gunakan MinIO Client (Metode 3)** karena:
- ✅ Paling mudah dan praktis
- ✅ Download langsung dari bucket (format normal)
- ✅ Bisa pilih bucket spesifik
- ✅ Bisa download file/folder tertentu saja
- ✅ Bisa dijalankan dari laptop (tidak perlu akses server)

## Troubleshooting

### Error: Volume tidak ditemukan
```bash
# Cek volume yang ada
docker volume ls | grep minio

# Jika volume namanya berbeda, sesuaikan di script
```

### Error: Permission denied
```bash
# Untuk bind mount, pastikan permission benar
sudo chown -R 1000:1000 /home/msiserver/minio/data
```

### Error: MinIO Client connection failed
```bash
# Test koneksi
mc alias set test https://minio-api.motorsights.com admin Rubysa179596!
mc ls test

# Jika SSL error, coba dengan --insecure
mc alias set test https://minio-api.motorsights.com admin Rubysa179596! --api s3v4
```

