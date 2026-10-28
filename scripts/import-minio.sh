#!/bin/bash

# Script untuk import MinIO dari file zip hasil export-minio.sh di server baru.
# Usage: ./import-minio.sh <minio-migration-XXXX.zip> [install_dir]
#
# install_dir default: /opt/minio (konfigurasi docker-compose akan diletakkan di sini)

set -euo pipefail

ZIP_FILE="${1:-}"
INSTALL_DIR="${2:-/opt/minio}"
CONTAINER="cloudstorage-minio"

if [ -z "$ZIP_FILE" ] || [ ! -f "$ZIP_FILE" ]; then
    echo "Usage: $0 <minio-migration-XXXX.zip> [install_dir]"
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

# shellcheck disable=SC1091
source "$BUNDLE_DIR/MANIFEST.txt"
echo ""
echo "  Image   : $image ($minio_version)"
echo "  Volume  : $volume"
echo "  Files   : $file_count"
echo "  Buckets : $buckets"
echo ""

# 2. Pastikan tidak menimpa data yang sudah ada
if docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "❌ Container $CONTAINER sudah ada di server ini. Hapus/rename dulu, script dibatalkan."
    exit 1
fi
if docker volume inspect "$volume" >/dev/null 2>&1; then
    echo "❌ Volume $volume sudah ada di server ini. Script dibatalkan supaya data tidak tertimpa."
    echo "   Jika yakin volume itu boleh dihapus: docker volume rm $volume"
    exit 1
fi

# 3. Load image
echo "🔄 [1/5] Load image docker..."
gunzip -c "$BUNDLE_DIR/minio-image.tar.gz" | docker load

# 4. Konfigurasi
echo "🔄 [2/5] Menyalin konfigurasi ke $INSTALL_DIR..."
mkdir -p "$INSTALL_DIR"
cp -rn "$BUNDLE_DIR/minio/." "$INSTALL_DIR/"
COMPOSE_FILE="$INSTALL_DIR/docker/docker-compose.yml"

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
