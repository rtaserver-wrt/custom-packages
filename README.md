# RTASERVER-WRT OPKG Repository 🚀

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Contributors](https://img.shields.io/github/contributors/rtaserver-wrt/custom-packages)](https://github.com/rtaserver-wrt/custom-packages/graphs/contributors)
[![OpenWRT](https://img.shields.io/badge/OpenWRT-23.05%20%7C%2024.10%20%7C%20snapshot-blue)](https://openwrt.org/)

Custom OPKG Repository for OpenWRT, menyediakan berbagai aplikasi dan paket tambahan untuk memperkaya fitur router Anda.

---

## ✨ Fitur Utama
- Koleksi aplikasi LUCI & paket populer
- Dukungan banyak arsitektur (x86_64, mips, arm, aarch64, dll)
- Mudah diintegrasikan ke OpenWRT



---

## 🚀 Cara Menggunakan
### 1. Nonaktifkan Signature Check
Edit `/etc/opkg.conf`, tambahkan `#` di depan `option check_signature`:
```diff
- option check_signature
+ #option check_signature
```

### 2. Tambahkan Custom Feed
Edit `/etc/opkg/customfeeds.conf` dan tambahkan:
```bash
src/gz rtaserver-wrt https://rtaserver-wrt.github.io/custom-packages/releases/{VERSION}/packages/{ARCH}
```
- Ganti `{VERSION}` dengan versi OpenWRT Anda (misal: 23.05)
- Ganti `{ARCH}` dengan arsitektur perangkat Anda (misal: x86_64)

**Contoh:**
```bash
src/gz rtaserver-wrt https://rtaserver-wrt.github.io/custom-packages/releases/23.05/packages/x86_64
```

### 3. Update Daftar Paket
```bash
opkg update
```
Atau melalui LUCI: `System > Software > Update List`

### 4. Instal Paket
```bash
opkg install <nama-paket>
```

---

## 📦 Lihat Daftar Packages
Untuk melihat daftar lengkap paket yang tersedia, kunjungi:

➡️ [https://rtaserver-wrt.github.io/custom-packages/releases/](https://rtaserver-wrt.github.io/custom-packages/releases/)

---

## 🛠️ Versi OpenWRT yang Didukung
- SNAPSHOT
- 24.10.2
- 23.05.5

## 🖥️ Arsitektur yang Didukung
- x86_64
- mips_24kc
- mipsel_24kc
- arm_cortex-a7_neon-vfpv4
- aarch64_cortex-a53
- aarch64_cortex-a72
- aarch64_generic

---

## 🤝 Kontribusi
Kontribusi sangat terbuka! Anda bisa:
- Mengajukan pull request (PR) untuk menambah/upgrade paket
- Melaporkan bug atau request fitur di [Issues](https://github.com/rtaserver-wrt/custom-packages/issues)
- Ikuti format PR yang jelas & sertakan deskripsi perubahan

**Langkah kontribusi:**
1. Fork repo ini
2. Buat branch baru untuk perubahan Anda
3. Commit perubahan & push ke branch
4. Ajukan Pull Request

---

## 📜 Lisensi
Proyek ini berlisensi [MIT](LICENSE). Silakan gunakan, modifikasi, dan distribusikan sesuai kebutuhan.

---

## 📬 Kontak & Dukungan
- Telegram: [@RizkiKotet](https://t.me/RizkiKotet)
- Diskusi & bantuan: [Telegram Discussions](https://t.me/backup_rtawrt)

Selamat menggunakan & berkontribusi! 🚦
