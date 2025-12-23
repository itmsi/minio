#!/bin/bash

# Script untuk download file dari MinIO bucket menggunakan MinIO Client (mc)
# Method ini lebih praktis karena langsung download dari bucket, bukan dari volume

OUTPUT_DIR=${1:-./minio-files-$(date +%Y%m%d-%H%M%S)}
BUCKET_NAME=${2:-msi-quotation}

# Konfigurasi MinIO
MINIO_ENDPOINT="https://minio-api.motorsights.com"
MINIO_ACCESS_KEY="admin"
MINIO_SECRET_KEY="Rubysa179596!"

echo "📦 Downloading files dari MinIO bucket: $BUCKET_NAME"
echo "Output directory: $OUTPUT_DIR"

# Cek apakah mc sudah terinstall
if ! command -v mc &> /dev/null; then
    echo "❌ MinIO Client (mc) belum terinstall"
    echo ""
    echo "Install mc:"
    echo "  macOS: brew install minio/stable/mc"
    echo "  Linux: wget https://dl.min.io/client/mc/release/linux-amd64/mc && chmod +x mc && sudo mv mc /usr/local/bin/"
    echo "  Windows: choco install minio-client"
    exit 1
fi

# Buat direktori output
mkdir -p "$OUTPUT_DIR"

# Konfigurasi alias MinIO
ALIAS_NAME="myminio-$(date +%s)"
echo "🔧 Setting up MinIO alias: $ALIAS_NAME"

mc alias set "$ALIAS_NAME" "$MINIO_ENDPOINT" "$MINIO_ACCESS_KEY" "$MINIO_SECRET_KEY"

# Download semua file dari bucket
echo "⬇️  Downloading files..."
mc mirror "$ALIAS_NAME/$BUCKET_NAME" "$OUTPUT_DIR"

# Hapus alias (opsional)
mc alias remove "$ALIAS_NAME"

echo "✅ Download selesai!"
echo "📁 Data tersimpan di: $OUTPUT_DIR"
echo ""
echo "Untuk melihat isi:"
echo "  ls -lh $OUTPUT_DIR"

