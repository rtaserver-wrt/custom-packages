#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
USIGN="$SCRIPT_DIR/x86_64/bin/usign"
KEY_DIR="$SCRIPT_DIR/../keys/usign"

# Pastikan direktori ada
mkdir -p "$KEY_DIR"

# Generate usign key pair
"$USIGN" -G -p "$KEY_DIR/usign.pub" -s "$KEY_DIR/usign.sec"

# Ambil fingerprint dan simpan dengan nama berdasarkan fingerprint (uppercase)
pub_fingerprint=$("$USIGN" -F -p "$KEY_DIR/usign.pub" | tr 'a-z' 'A-Z')
sec_fingerprint=$("$USIGN" -F -s "$KEY_DIR/usign.sec" | tr 'a-z' 'A-Z')

mv "$KEY_DIR/usign.pub" "$KEY_DIR/${pub_fingerprint}.pub"
mv "$KEY_DIR/usign.sec" "$KEY_DIR/${sec_fingerprint}.sec"

echo "✅ USIGN keypair generated:"
echo "  🔐 Secret: $KEY_DIR/${sec_fingerprint}.sec"
echo "  🔓 Public: $KEY_DIR/${pub_fingerprint}.pub"
