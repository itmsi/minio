#!/bin/bash

# Script untuk download data dari bind mount ke laptop
# Usage: ./download-via-bind-mount.sh [output_directory]

OUTPUT_DIR=${1:-./minio-backup-$(date +%Y%m%d-%H%M%S)}
SOURCE_DIR="/home/msiserver/minio/data"

echo "📦 Downloading MinIO data dari bind mount..."
echo "Source: $SOURCE_DIR"
echo "Output directory: $OUTPUT_DIR"

# Buat direktori output
mkdir -p "$OUTPUT_DIR"

# Copy data dari server ke laptop (jika di server)
if [ -d "$SOURCE_DIR" ]; then
    echo "🔄 Copying data..."
    cp -r "$SOURCE_DIR"/* "$OUTPUT_DIR/" 2>/dev/null
    echo "✅ Download selesai!"
    echo "📁 Data tersimpan di: $OUTPUT_DIR"
else
    echo "❌ Direktori source tidak ditemukan: $SOURCE_DIR"
    echo "💡 Pastikan Anda menjalankan script ini di server yang sama dengan MinIO"
fi

