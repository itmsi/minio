#!/bin/bash

# Script untuk export MinIO (image + volume data + konfigurasi) menjadi satu file zip
# untuk dipindahkan ke server lain. Pasangannya: import-minio.sh
# Usage: ./export-minio.sh [--stop] [output_directory]
#
# Default: TANPA downtime. Data disalin dari container yang sedang berjalan
# (read-only, prioritas CPU/IO rendah). File yang sedang di-upload tepat saat
# proses copy berjalan bisa tidak ikut / tidak lengkap.
# --stop : stop container sebentar selama copy supaya 100% konsisten
#          (pakai hanya saat cut-over final / maintenance window).

set -euo pipefail

STOP_CONTAINER=false
if [ "${1:-}" = "--stop" ]; then
    STOP_CONTAINER=true
    shift
fi

CONTAINER="cloudstorage-minio"
VOLUME="docker_minio_data"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
OUTPUT_DIR="${1:-$HOME}"
# Jalankan proses berat dengan prioritas rendah supaya tidak mengganggu service lain
LOWPRIO="nice -n 19 ionice -c3"
BUNDLE_NAME="minio-migration-$STAMP"
WORK_DIR="$OUTPUT_DIR/$BUNDLE_NAME"

if ! docker inspect "$CONTAINER" >/dev/null 2>&1; then
    echo "❌ Container $CONTAINER tidak ditemukan"
    exit 1
fi

IMAGE="$(docker inspect "$CONTAINER" --format '{{.Config.Image}}')"
IMAGE_ID="$(docker inspect "$CONTAINER" --format '{{.Image}}')"
MINIO_VERSION="$(docker exec "$CONTAINER" minio --version 2>/dev/null | head -1 || echo unknown)"

echo "📦 Export MinIO"
echo "  Container : $CONTAINER"
echo "  Image     : $IMAGE ($MINIO_VERSION)"
echo "  Volume    : $VOLUME"
echo "  Output    : $WORK_DIR.zip"
echo ""

mkdir -p "$WORK_DIR"

# 1. Image docker
echo "🔄 [1/5] Menyimpan image docker..."
docker save "$IMAGE" | $LOWPRIO gzip > "$WORK_DIR/minio-image.tar.gz"

# 2. Data volume
if [ "$STOP_CONTAINER" = "true" ]; then
    # Apapun yang terjadi, container akan di-start lagi
    WAS_RUNNING="$(docker inspect "$CONTAINER" --format '{{.State.Running}}')"
    restart_container() {
        if [ "$WAS_RUNNING" = "true" ]; then
            echo "▶️  Menjalankan kembali $CONTAINER..."
            docker start "$CONTAINER" >/dev/null
        fi
    }
    trap restart_container EXIT
    echo "⏸️  [2/5] Stop $CONTAINER supaya data konsisten..."
    docker stop "$CONTAINER" >/dev/null
else
    echo "▶️  [2/5] Mode tanpa downtime: $CONTAINER tetap berjalan"
fi

echo "🔄 [3/5] Menyalin data volume..."
docker cp "$CONTAINER:/data" - | $LOWPRIO gzip > "$WORK_DIR/minio-data.tar.gz"

if [ "$STOP_CONTAINER" = "true" ]; then
    restart_container
    trap - EXIT
fi

# 3. Konfigurasi & dokumentasi
echo "🔄 [4/5] Menyalin konfigurasi..."
mkdir -p "$WORK_DIR/minio"
cp -r "$REPO_DIR/docker" "$REPO_DIR/scripts" "$WORK_DIR/minio/"
cp "$REPO_DIR/cors.json" "$REPO_DIR/README.md" "$REPO_DIR/MIGRASI.md" "$WORK_DIR/minio/"
cp "$REPO_DIR/MIGRASI.md" "$WORK_DIR/"

FILE_COUNT="$(gunzip -c "$WORK_DIR/minio-data.tar.gz" | tar -tvf - | grep -c '^-' || true)"
DATA_BYTES="$(gunzip -c "$WORK_DIR/minio-data.tar.gz" | tar -tvf - | awk '$1 ~ /^-/ {s+=$3} END {print s+0}')"
BUCKETS="$(gunzip -c "$WORK_DIR/minio-data.tar.gz" | tar -tf - | awk -F/ 'NF>=3 && $2!=".minio.sys" && $2!="" {print $2}' | sort -u | tr '\n' ' ')"

cat > "$WORK_DIR/MANIFEST.txt" <<EOF
exported_at=$(date -Iseconds)
source_host=$(hostname)
container=$CONTAINER
image=$IMAGE
image_id=$IMAGE_ID
minio_version=$MINIO_VERSION
volume=$VOLUME
compose_project=docker
network=infra_net
file_count=$FILE_COUNT
data_bytes=$DATA_BYTES
buckets=$BUCKETS
EOF

(cd "$WORK_DIR" && sha256sum minio-image.tar.gz minio-data.tar.gz MANIFEST.txt > SHA256SUMS)

# 4. Zip (tanpa kompresi ulang, isinya sudah gzip)
echo "🔄 [5/5] Membuat file zip..."
(cd "$OUTPUT_DIR" && zip -r -0 -q "$BUNDLE_NAME.zip" "$BUNDLE_NAME")
rm -rf "$WORK_DIR"
(cd "$OUTPUT_DIR" && sha256sum "$BUNDLE_NAME.zip" > "$BUNDLE_NAME.zip.sha256")

echo ""
echo "✅ Export selesai!"
cat <<EOF
  File zip : $OUTPUT_DIR/$BUNDLE_NAME.zip ($(du -h "$OUTPUT_DIR/$BUNDLE_NAME.zip" | cut -f1))
  Checksum : $OUTPUT_DIR/$BUNDLE_NAME.zip.sha256
  Jumlah file data : $FILE_COUNT
  Bucket : $BUCKETS

Upload KEDUA file (.zip dan .zip.sha256) via FTP dalam mode BINARY.
Lalu di server baru ikuti MIGRASI.md (ada di dalam zip).
EOF
