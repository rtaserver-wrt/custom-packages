#!/bin/bash
set -euo pipefail

# Konfigurasi
PWSIZE=16
KEYSIZE=4096
EXPIRE=0
NAME="fantastic packages"
MAIL="fantastic-packages@users.noreply.github.com"
KEY_DIR="keys/gpg"

# Siapkan direktori output
mkdir -p "$KEY_DIR"

# Buat password acak
PW=$(head -c 512 /dev/urandom | md5sum | cut -c1-${PWSIZE})

# Generate GPG key
gpg_output=$(gpg --batch --full-gen-key <(cat <<EOF
Key-Type: RSA
Key-Length: $KEYSIZE
Subkey-Type: RSA
Subkey-Length: $KEYSIZE
Expire-Date: $EXPIRE
Name-Real: $NAME
Name-Email: $MAIL
Passphrase: $PW
EOF
) 2>&1)

# Ambil revocation certificate path
rev_cert=$(echo "$gpg_output" | sed -En "s/.*revocation certificate stored as '([^']+)'.*/\1/p")

# Ambil fingerprint terakhir (key ID = full fingerprint)
key_id=$(gpg --list-secret-keys --with-colons --fingerprint \
    | awk -F: '/^fpr:/ { print $10 }' | tail -n1)

if [[ -z "$key_id" ]]; then
    echo "❌ GPG key generation failed: no key ID found." >&2
    exit 1
fi

# Gunakan 16 karakter terakhir dari key ID sebagai short ID (OpenWrt style)
short_id="${key_id: -16}"
upper_id="${short_id^^}"

# Ambil fingerprint dalam bentuk human-readable
fingerprint=$(gpg --fingerprint "$key_id" | sed -n '2{s/^[[:space:]]*//;p}')

if [[ -z "$rev_cert" || -z "$fingerprint" ]]; then
    echo "❌ GPG key generation failed: missing revocation or fingerprint." >&2
    exit 1
fi

# Simpan file-file terkait
printf '%s\n' "$PW" > "${KEY_DIR}/${upper_id}.pw"
printf '%s\n' "$fingerprint" > "${KEY_DIR}/${upper_id}.finger"
cp "$rev_cert" "${KEY_DIR}/${upper_id}.rev" && rm -f "$rev_cert"

# Ekspor secret key
gpg --batch --yes --pinentry-mode loopback --passphrase "$PW" \
    -a -o "${KEY_DIR}/${upper_id}.sec" --export-secret-keys "$key_id"
gpg --batch --yes --delete-secret-keys "$key_id"

# Ekspor public key
gpg -a -o "${KEY_DIR}/${upper_id}.pub" --export "$key_id"
gpg --batch --yes --delete-keys "$key_id"

# Output hasil
echo "✅ GPG key created and exported:"
echo "  🔓 Public     : ${KEY_DIR}/${upper_id}.pub"
echo "  🔐 Secret     : ${KEY_DIR}/${upper_id}.sec"
echo "  🧾 Revocation : ${KEY_DIR}/${upper_id}.rev"
echo "  🔑 Password   : ${KEY_DIR}/${upper_id}.pw"
echo "  📌 Fingerprint: ${KEY_DIR}/${upper_id}.finger"
