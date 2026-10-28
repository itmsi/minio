# Migrasi MinIO ke Server Baru

Panduan memindahkan MinIO (image docker, volume, data, user/policy, konfigurasi bucket)
ke server lain lewat satu file zip.

## Isi file zip

| File | Isi |
|------|-----|
| `minio-image.tar.gz` | Image docker MinIO persis seperti di server lama (`docker save`) |
| `minio-data.tar.gz` | Seluruh isi volume `docker_minio_data` (`/data`), termasuk `.minio.sys` (user, access key, policy, setting bucket) |
| `minio/` | `docker/docker-compose.yml`, `cors.json`, `scripts/`, README |
| `MANIFEST.txt` | Versi MinIO, nama volume, jumlah file, daftar bucket |
| `SHA256SUMS` | Checksum untuk cek file tidak rusak |

## Di server lama: export

```bash
cd /opt/minio
./scripts/export-minio.sh            # hasil di $HOME, TANPA downtime
# atau: ./scripts/export-minio.sh /path/output
# cut-over final (stop MinIO sebentar, 100% konsisten):
#       ./scripts/export-minio.sh --stop /path/output
```

Default-nya MinIO **tetap berjalan** (tidak ada downtime); copy berjalan read-only dengan
prioritas CPU/IO rendah. File yang sedang di-upload tepat saat copy bisa tidak ikut.
Hasilnya `minio-migration-<tanggal>.zip` + `.zip.sha256`.

Upload **kedua file** via FTP dalam mode **binary**.

## Di server baru: import

Prasyarat: Docker + Docker Compose v2, `unzip`, `curl`, user ada di grup `docker`,
port `127.0.0.1:9000` dan `9001` kosong.

```bash
unzip -j minio-migration-XXXX.zip '*/minio/scripts/import-minio.sh' -d .
chmod +x import-minio.sh
./import-minio.sh minio-migration-XXXX.zip /opt/minio
```

Script akan:
1. Cek checksum zip & isi bundle
2. Batal jika container `cloudstorage-minio` atau volume `docker_minio_data` sudah ada (tidak menimpa data)
3. `docker load` image
4. Salin konfigurasi ke `/opt/minio`, buat network `infra_net` jika belum ada
5. Buat container + volume, restore data, **cocokkan jumlah file** dengan export
6. Jalankan MinIO dan cek health

## Instruksi untuk Claude di server baru

Jika Claude diminta melakukan import:
- Baca `MANIFEST.txt` di dalam zip untuk mengetahui versi/volume/jumlah file.
- Jalankan `import-minio.sh` seperti di atas. Jangan pakai `docker pull` untuk MinIO —
  gunakan image dari zip agar versinya sama (lihat `minio_version` di manifest).
- Jangan hapus volume/container yang sudah ada tanpa konfirmasi user.
- Setelah selesai, verifikasi: `docker exec cloudstorage-minio ls /data` harus menampilkan
  bucket yang sama dengan `buckets` di manifest, dan login console dengan user lama berhasil.
- Reverse proxy / Cloudflare tunnel untuk `minio-api.motorsights.com` dan
  `minio-console.motorsights.com` **tidak** termasuk di zip; perlu diarahkan ulang ke server baru.

## Catatan

- Data yang di-upload ke server lama **setelah** export tidak ikut. Untuk cut-over final,
  hentikan aplikasi yang menulis ke MinIO dulu, baru export.
- Hapus file zip setelah migrasi berhasil — isinya memuat semua data dan kredensial.
