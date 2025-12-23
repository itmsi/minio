#!/bin/bash

# Script untuk download data dari MinIO Docker volume ke laptop
# Usage: ./download-minio-data.sh [output_directory]

OUTPUT_DIR=${1:-./minio-backup-$(date +%Y%m%d-%H%M%S)}

echo "📦 Downloading MinIO data..."
echo "Output directory: $OUTPUT_DIR"

# Buat direktori output
mkdir -p "$OUTPUT_DIR"

# Method 1: Menggunakan temporary container untuk copy dari volume
echo "🔄 Creating temporary container to access volume..."
docker run --rm \
  -v minio_minio_data:/source:ro \
  -v "$(pwd)/$OUTPUT_DIR:/backup" \
  alpine sh -c "cp -r /source/* /backup/ 2>/dev/null || echo 'No data found or permission issue'"

# Method 2: Alternatif menggunakan docker cp dari container yang berjalan
# docker cp cloudstorage-minio:/data "$OUTPUT_DIR"

echo "✅ Download selesai!"
echo "📁 Data tersimpan di: $OUTPUT_DIR"
echo ""
echo "Untuk melihat isi:"
echo "  ls -lh $OUTPUT_DIR"

