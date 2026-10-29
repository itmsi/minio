#!/bin/bash

# Script untuk import MinIO dari file zip hasil export-minio.sh di server baru.
# Usage: ./import-minio.sh [--replace] <minio-migration-XXXX.zip> [install_dir]
#
# install_dir default: /opt/minio (konfigurasi docker-compose akan diletakkan di sini)
# --replace : server baru SUDAH punya MinIO (container/volume yang sama). Data lama di
#             volume di-backup dulu ke $INSTALL_DIR/backup-before-import-*.tar.gz, docker-compose.yml
#             lama di-backup ke *.bak-*, lalu container & volume lama diganti dengan isi zip.

set -euo pipefail

REPLACE=false
if [ "${1:-}" = "--replace" ]; then
    REPLACE=true
    shift
fi

ZIP_FILE="${1:-}"
INSTALL_DIR="${2:-/opt/minio}"
CONTAINER="cloudstorage-minio"

if [ -z "$ZIP_FILE" ] || [ ! -f "$ZIP_FILE" ]; then
    echo "Usage: $0 [--replace] <minio-migration-XXXX.zip> [install_dir]"
    exit 1
fi

ZIP_FILE="$(cd "$(dirname "$ZIP_FILE")" && pwd)/$(basename "$ZIP_FILE")"

# 0. Cek checksum zip (jika file .sha256 ikut di-upload)
if [ -f "$ZIP_FILE.sha256" ]; then
    echo "🔍 Cek checksum zip..."
    (cd "$(dirname "$ZIP_FILE")" && sha256sum -c "$(basename "$ZIP_FILE").sha256")
else
    echo "⚠️  $ZIP_FILE.sha256 tidak ada, lewati cek checksum zip"
fi

# 1. Extract
EXTRACT_DIR="$(mktemp -d)"
trap 'rm -rf "$EXTRACT_DIR"' EXIT
echo "📂 Extract zip..."
unzip -q "$ZIP_FILE" -d "$EXTRACT_DIR"
BUNDLE_DIR="$(find "$EXTRACT_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)"

echo "🔍 Cek checksum isi bundle..."
(cd "$BUNDLE_DIR" && sha256sum -c SHA256SUMS)

# Baca MANIFEST.txt sebagai key=value (jangan di-source: nilainya bisa berisi spasi/kurung)
manifest() { grep -m1 "^$1=" "$BUNDLE_DIR/MANIFEST.txt" | cut -d= -f2-; }
image="$(manifest image)"
minio_version="$(manifest minio_version)"
volume="$(manifest volume)"
compose_project="$(manifest compose_project)"
network="$(manifest network)"
file_count="$(manifest file_count)"
buckets="$(manifest buckets)"
echo ""
echo "  Image   : $image ($minio_version)"
echo "  Volume  : $volume"
echo "  Files   : $file_count"
echo "  Buckets : $buckets"
echo ""

# 2. Pastikan tidak menimpa data yang sudah ada (kecuali --replace, dengan backup dulu)
STAMP="$(date +%Y%m%d-%H%M%S)"
if [ "$REPLACE" = "true" ]; then
    mkdir -p "$INSTALL_DIR"
    if docker volume inspect "$volume" >/dev/null 2>&1; then
        BACKUP_FILE="$INSTALL_DIR/backup-before-import-$STAMP.tar.gz"
        echo "💾 Backup data volume lama $volume ke $BACKUP_FILE..."
        docker stop "$CONTAINER" >/dev/null 2>&1 || true
        # Container sementara (tidak dijalankan) hanya untuk membaca isi volume
        docker create --name minio-import-backup -v "$volume:/data" "$image" >/dev/null
        docker cp minio-import-backup:/data - | gzip > "$BACKUP_FILE"
        docker rm minio-import-backup >/dev/null
        echo "   ✔ Backup selesai ($(du -h "$BACKUP_FILE" | cut -f1))"
    fi
    if docker inspect "$CONTAINER" >/dev/null 2>&1; then
        echo "🗑️  Hapus container lama $CONTAINER..."
        docker rm -f "$CONTAINER" >/dev/null
    fi
    if docker volume inspect "$volume" >/dev/null 2>&1; then
        echo "🗑️  Hapus volume lama $volume (sudah di-backup)..."
        docker volume rm "$volume" >/dev/null
    fi
else
    if docker inspect "$CONTAINER" >/dev/null 2>&1; then
        echo "❌ Container $CONTAINER sudah ada di server ini. Script dibatalkan."
        echo "   Untuk mengganti MinIO yang sudah ada (data lama di-backup dulu): $0 --replace $ZIP_FILE $INSTALL_DIR"
        exit 1
    fi
    if docker volume inspect "$volume" >/dev/null 2>&1; then
        echo "❌ Volume $volume sudah ada di server ini. Script dibatalkan supaya data tidak tertimpa."
        echo "   Untuk mengganti MinIO yang sudah ada (data lama di-backup dulu): $0 --replace $ZIP_FILE $INSTALL_DIR"
        exit 1
    fi
fi

# 3. Load image
echo "🔄 [1/5] Load image docker..."
gunzip -c "$BUNDLE_DIR/minio-image.tar.gz" | docker load

# 4. Konfigurasi
echo "🔄 [2/5] Menyalin konfigurasi ke $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
COMPOSE_FILE="$INSTALL_DIR/docker/docker-compose.yml"
if [ "$REPLACE" = "true" ]; then
    # Wajib pakai compose dari server lama: data IAM di .minio.sys terenkripsi dengan
    # MINIO_ROOT_USER/PASSWORD, kalau beda user & policy tidak bisa dibaca
    if [ -f "$COMPOSE_FILE" ] && ! cmp -s "$COMPOSE_FILE" "$BUNDLE_DIR/minio/docker/docker-compose.yml"; then
        cp "$COMPOSE_FILE" "$COMPOSE_FILE.bak-$STAMP"
        echo "   docker-compose.yml lama di-backup ke $COMPOSE_FILE.bak-$STAMP"
    fi
    cp -r "$BUNDLE_DIR/minio/." "$INSTALL_DIR/"
else
    cp -rn "$BUNDLE_DIR/minio/." "$INSTALL_DIR/"
fi

if ! docker network inspect "$network" >/dev/null 2>&1; then
    echo "🌐 Membuat network $network..."
    docker network create "$network" >/dev/null
fi

# 5. Buat container + volume (belum dijalankan), lalu isi volume
echo "🔄 [3/5] Membuat container & volume..."
docker compose -p "$compose_project" -f "$COMPOSE_FILE" create

echo "🔄 [4/5] Restore data ke volume..."
gunzip -c "$BUNDLE_DIR/minio-data.tar.gz" | docker cp - "$CONTAINER:/"

RESTORED_COUNT="$(docker cp "$CONTAINER:/data" - | tar -tvf - | grep -c '^-' || true)"
if [ "$RESTORED_COUNT" != "$file_count" ]; then
    echo "❌ Jumlah file tidak sama! Export: $file_count, Restore: $RESTORED_COUNT"
    echo "   Container TIDAK dijalankan. Cek manual sebelum lanjut."
    exit 1
fi
echo "   ✔ $RESTORED_COUNT file ter-restore (sama dengan export)"

# 6. Jalankan
for port in 9000 9001; do
    if (exec 3<>"/dev/tcp/127.0.0.1/$port") 2>/dev/null; then
        echo "❌ Port 127.0.0.1:$port sudah dipakai (MinIO/aplikasi lain dengan nama container berbeda?)."
        echo "   Data sudah ter-restore di volume $volume. Hentikan pemakai port itu, lalu:"
        echo "   docker compose -p $compose_project -f $COMPOSE_FILE up -d"
        exit 1
    fi
done
echo "🔄 [5/5] Menjalankan MinIO..."
docker compose -p "$compose_project" -f "$COMPOSE_FILE" up -d

echo "⏳ Menunggu MinIO siap..."
for _ in $(seq 1 30); do
    if curl -fsS http://127.0.0.1:9000/minio/health/live >/dev/null 2>&1; then
        echo ""
        echo "✅ Import selesai! MinIO berjalan."
        echo "  Konfigurasi : $INSTALL_DIR"
        echo "  S3 API      : http://127.0.0.1:9000"
        echo "  Console     : http://127.0.0.1:9001"
        echo ""
        echo "Langkah berikutnya: arahkan reverse proxy / tunnel untuk domain"
        echo "minio-api.motorsights.com & minio-console.motorsights.com ke server ini."
        exit 0
    fi
    sleep 2
done

echo "⚠️  MinIO belum merespon health check. Cek log: docker logs $CONTAINER"
exit 1
