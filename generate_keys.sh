#!/bin/bash

# 🔐 Modern Key Generation Script for Package Signing
# ====================================================
# Generates APK signing keys, GPG keys, and USIGN keys for package management
# Created: $(date '+%Y-%m-%d %H:%M:%S')

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# 📋 SUMMARY
# ==========
# This script generates three types of cryptographic keys:
# 1. 🔑 APK Signing Keys (ECDSA P-256) - For Android package signing
# 2. 🔐 GPG Keys (RSA 4096-bit) - For package authentication
# 3. 🛡️ USIGN Keys - For OpenWrt package signing

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly KEY_BASE_DIR="keys"
readonly APK_KEY_DIR="${KEY_BASE_DIR}/apksign"
readonly GPG_KEY_DIR="${KEY_BASE_DIR}/gpg"
readonly USIGN_KEY_DIR="${KEY_BASE_DIR}/usign"
readonly USIGN_BIN="./keys-bin/x86_64/bin/usign"

# Lock file to prevent concurrent execution
readonly LOCK_FILE="${KEY_BASE_DIR}/.keygen.lock"

# GPG Configuration
readonly GPG_KEYSIZE=4096
readonly GPG_EXPIRE=0
readonly GPG_NAME="rtaserver wrt"
readonly GPG_EMAIL="rtaserver-wrt@users.noreply.github.com"
readonly PASSWORD_LENGTH=16

# 🎨 Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

# 📝 Logging functions
log_info() {
    echo -e "${BLUE}ℹ️  INFO:${NC} $1"
}

log_success() {
    echo -e "${GREEN}✅ SUCCESS:${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠️  WARNING:${NC} $1"
}

log_error() {
    echo -e "${RED}❌ ERROR:${NC} $1" >&2
}

log_step() {
    echo -e "${PURPLE}🔧 STEP:${NC} $1"
}

# 📁 Create directory structure
create_directories() {
    log_step "Creating directory structure"
    mkdir -p "${APK_KEY_DIR}" "${GPG_KEY_DIR}" "${USIGN_KEY_DIR}"
    log_success "Directories created successfully"
}

# 📊 Display existing keys summary
display_existing_summary() {
    echo
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                     📋 EXISTING KEYS SUMMARY                   ║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
    
    # APK Keys
    if [[ -d "$APK_KEY_DIR" ]] && find "$APK_KEY_DIR" -name "*.pub" -quit 2>/dev/null | grep -q .; then
        echo -e "${CYAN}║${NC} 🔑 APK Keys:                                                   ${CYAN}║${NC}"
        find "$APK_KEY_DIR" -name "*.pub" | while read -r pub_file; do
            local key_name=$(basename "$pub_file" .pub)
            echo -e "${CYAN}║${NC}   - $key_name                            ${CYAN}║${NC}"
        done
    fi
    
    # GPG Keys  
    if [[ -d "$GPG_KEY_DIR" ]] && find "$GPG_KEY_DIR" -name "*.pub" -quit 2>/dev/null | grep -q .; then
        echo -e "${CYAN}║${NC} 🔐 GPG Keys:                                                   ${CYAN}║${NC}"
        find "$GPG_KEY_DIR" -name "*.pub" | while read -r pub_file; do
            local key_name=$(basename "$pub_file" .pub)
            echo -e "${CYAN}║${NC}   - $key_name        ${CYAN}║${NC}"
        done
    fi
    
    # USIGN Keys
    if [[ -d "$USIGN_KEY_DIR" ]] && find "$USIGN_KEY_DIR" -name "*.pub" -quit 2>/dev/null | grep -q .; then
        echo -e "${CYAN}║${NC} 🛡️  USIGN Keys:                                                ${CYAN}║${NC}"
        find "$USIGN_KEY_DIR" -name "*.pub" | while read -r pub_file; do
            local key_name=$(basename "$pub_file" .pub)
            echo -e "${CYAN}║${NC}   - $key_name                  ${CYAN}║${NC}"
        done
    fi
    
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# 🔒 Lock management
acquire_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE" 2>/dev/null)
        if [[ -n "$lock_pid" ]] && kill -0 "$lock_pid" 2>/dev/null; then
            log_error "Another key generation process is running (PID: $lock_pid)"
            exit 1
        else
            log_warning "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $ > "$LOCK_FILE"
    log_info "Acquired lock for key generation"
}

release_lock() {
    if [[ -f "$LOCK_FILE" ]]; then
        rm -f "$LOCK_FILE"
        log_info "Released lock"
    fi
}

# 🔍 Check for existing keys
check_existing_keys() {
    log_step "Checking for existing keys"
    
    local has_apk=false has_gpg=false has_usign=false
    
    if [[ -d "$APK_KEY_DIR" ]] && find "$APK_KEY_DIR" -name "*.pub" -quit 2>/dev/null | grep -q .; then
        has_apk=true
        local apk_count=$(find "$APK_KEY_DIR" -name "*.pub" | wc -l)
        log_info "Found $apk_count existing APK key pair(s)"
    fi
    
    if [[ -d "$GPG_KEY_DIR" ]] && find "$GPG_KEY_DIR" -name "*.pub" -quit 2>/dev/null | grep -q .; then
        has_gpg=true
        local gpg_count=$(find "$GPG_KEY_DIR" -name "*.pub" | wc -l)
        log_info "Found $gpg_count existing GPG key pair(s)"
    fi
    
    if [[ -d "$USIGN_KEY_DIR" ]] && find "$USIGN_KEY_DIR" -name "*.pub" -quit 2>/dev/null | grep -q .; then
        has_usign=true
        local usign_count=$(find "$USIGN_KEY_DIR" -name "*.pub" | wc -l)
        log_info "Found $usign_count existing USIGN key pair(s)"
    fi
    
    if [[ "$has_apk" == true || "$has_gpg" == true || "$has_usign" == true ]]; then
        echo
        log_warning "⚠️  Existing keys detected!"
        echo -e "${YELLOW}Do you want to:${NC}"
        echo -e "${YELLOW}  1) Keep existing keys and exit${NC}"
        echo -e "${YELLOW}  2) Clean up old duplicates and generate new ones${NC}"
        echo -e "${YELLOW}  3) Force regenerate all keys (will delete existing)${NC}"
        echo
        read -p "Please choose (1/2/3): " choice
        
        case $choice in
            1)
                log_info "Keeping existing keys, exiting..."
                display_existing_summary
                exit 0
                ;;
            2)
                log_info "Will clean up duplicates and generate new keys"
                cleanup_old_keys
                return 0
                ;;
            3)
                log_warning "Will delete all existing keys and regenerate"
                rm -rf "${APK_KEY_DIR:?}"/* "${GPG_KEY_DIR:?}"/* "${USIGN_KEY_DIR:?}"/* 2>/dev/null || true
                return 0
                ;;
            *)
                log_error "Invalid choice. Exiting..."
                exit 1
                ;;
        esac
    fi
}

# 🔑 Generate APK signing keys (ECDSA P-256)
generate_apk_keys() {
    log_step "Generating APK signing keys (ECDSA P-256)"
    
    local temp_private="${APK_KEY_DIR}/private-key.pem"
    local temp_public="${APK_KEY_DIR}/public-key.pem"
    
    # Generate private key
    if ! openssl ecparam -name prime256v1 -genkey -noout -out "${temp_private}"; then
        log_error "Failed to generate APK private key"
        return 1
    fi
    
    # Generate public key
    if ! openssl ec -in "${temp_private}" -pubout > "${temp_public}"; then
        log_error "Failed to generate APK public key"
        return 1
    fi
    
    # Create unique key ID based on timestamp
    local key_id
    key_id=$(date +%Y%m%d%H%M%S | tr 'a-z' 'A-Z')
    
    # Rename keys with unique ID
    mv "${temp_private}" "${APK_KEY_DIR}/${key_id}.sec"
    mv "${temp_public}" "${APK_KEY_DIR}/${key_id}.pub"
    
    # Remove Windows line endings
    sed -i 's/\r//g' "${APK_KEY_DIR}/${key_id}."*
    
    log_success "APK keys generated with ID: ${key_id}"
    return 0
}

# 🔐 Generate random password
generate_password() {
    if command -v openssl >/dev/null 2>&1; then
        openssl rand -base64 32 | tr -d "=+/" | cut -c1-${PASSWORD_LENGTH}
    else
        # Fallback method
        head -c 1000 /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w ${PASSWORD_LENGTH} | head -n 1
    fi
}

# 🔐 Generate GPG keys
generate_gpg_keys() {
    log_step "Generating GPG keys (RSA ${GPG_KEYSIZE}-bit)"
    
    local password
    password=$(generate_password)
    
    if [[ -z "$password" ]]; then
        log_error "Failed to generate password"
        return 1
    fi
    
    # Create GPG key generation parameters
    local gpg_params
    gpg_params=$(cat <<EOF
Key-Type: 1
Key-Length: ${GPG_KEYSIZE}
Subkey-Type: 1
Subkey-Length: ${GPG_KEYSIZE}
Expire-Date: ${GPG_EXPIRE}
Name-Real: ${GPG_NAME}
Name-Email: ${GPG_EMAIL}
Passphrase: ${password}
EOF
)
    
    log_info "Generating GPG key pair (this may take a while)..."
    
    # Generate GPG key
    local gpg_output
    if ! gpg_output=$(gpg --full-gen-key --batch <(echo "$gpg_params") 2>&1); then
        log_error "GPG key generation failed"
        echo "$gpg_output" >&2
        return 1
    fi
    
    # Extract key information with multiple patterns
    local key_id rev_cert
    
    # Try different patterns for key ID extraction
    key_id=$(echo "$gpg_output" | grep -oE '[A-F0-9]{40}' | head -n1)
    if [[ -z "$key_id" ]]; then
        key_id=$(echo "$gpg_output" | sed -En 's|.+key ([[:xdigit:]]+) marked.+|\1|p')
    fi
    if [[ -z "$key_id" ]]; then
        key_id=$(echo "$gpg_output" | sed -En 's|.*([A-F0-9]{40}).*|\1|p')
    fi
    
    # Extract revocation certificate path
    rev_cert=$(echo "$gpg_output" | sed -En "s|.+revocation certificate stored as '([^']+)'.*|\1|p")
    
    log_info "Debug - GPG Output:"
    echo "$gpg_output" | while IFS= read -r line; do
        log_info "  $line"
    done
    
    log_info "Extracted Key ID: ${key_id:-'NOT_FOUND'}"
    log_info "Extracted Rev Cert: ${rev_cert:-'NOT_FOUND'}"
    
    if [[ -z "$key_id" ]]; then
        log_error "Failed to extract GPG key ID"
        
        # Try to get key ID from GPG keyring as fallback
        log_info "Attempting to get key ID from GPG keyring..."
        local fallback_key_id
        fallback_key_id=$(gpg --list-secret-keys --with-colons | grep '^sec:' | cut -d: -f5 | tail -n1)
        
        if [[ -n "$fallback_key_id" ]]; then
            log_info "Found key ID from keyring: $fallback_key_id"
            key_id="$fallback_key_id"
        else
            log_error "No fallback key ID found"
            return 1
        fi
    fi
    
    if [[ -z "$rev_cert" ]]; then
        log_warning "Revocation certificate path not found, will skip copying"
    fi
    
    # Get fingerprint
    local fingerprint
    fingerprint=$(gpg --fingerprint "${key_id}" | sed -n '2{s|^\s*||p}')
    
    # Convert key_id to uppercase
    local key_id_upper="${key_id^^}"
    
    # Save key information
    echo "$password" > "${GPG_KEY_DIR}/${key_id_upper}.pw"
    echo "$fingerprint" > "${GPG_KEY_DIR}/${key_id_upper}.finger"
    
    # Copy revocation certificate if found
    if [[ -n "$rev_cert" && -f "$rev_cert" ]]; then
        cp "$rev_cert" "${GPG_KEY_DIR}/${key_id_upper}.rev"
        rm "$rev_cert" 2>/dev/null || true
        log_info "Revocation certificate saved"
    else
        log_warning "Revocation certificate not copied (file not found or path empty)"
    fi
    
    # Export and delete keys from keyring
    if ! gpg -a -o "${GPG_KEY_DIR}/${key_id_upper}.sec" \
         --batch --pinentry-mode=loopback --yes \
         --passphrase "$password" --export-secret-key "${key_id}"; then
        log_error "Failed to export GPG secret key"
        return 1
    fi
    
    if ! gpg -a -o "${GPG_KEY_DIR}/${key_id_upper}.pub" --export "${key_id}"; then
        log_error "Failed to export GPG public key"
        return 1
    fi
    
    # Clean up keyring
    gpg --delete-secret-keys "${key_id}" --batch --yes >/dev/null 2>&1 || true
    gpg --delete-keys "${key_id}" --batch --yes >/dev/null 2>&1 || true
    
    log_success "GPG keys generated with ID: ${key_id_upper}"
    return 0
}

# 🛡️ Generate USIGN keys
generate_usign_keys() {
    log_step "Generating USIGN keys for OpenWrt packages"
    
    if [[ ! -f "$USIGN_BIN" ]]; then
        log_error "USIGN binary not found: $USIGN_BIN"
        return 1
    fi
    
    # Check if usign binary has correct permissions
    if [[ ! -x "$USIGN_BIN" ]]; then
        log_info "Setting executable permissions on USIGN binary"
        chmod +x "$USIGN_BIN" 2>/dev/null || {
            log_error "Cannot set executable permissions on USIGN binary"
            return 1
        }
    fi
    
    # Check for library dependencies and fix permissions
    local usign_dir="$(dirname "$USIGN_BIN")"
    local lib_dir="${usign_dir}/../lib"
    
    if [[ -d "$lib_dir" ]]; then
        log_info "Setting permissions on USIGN library files"
        find "$lib_dir" -type f -name "*.so*" -exec chmod +x {} \; 2>/dev/null || true
        find "$lib_dir" -type f -name "ld-linux*" -exec chmod +x {} \; 2>/dev/null || true
    fi
    
    # Test usign binary
    log_info "Testing USIGN binary"
    if ! "$USIGN_BIN" -h >/dev/null 2>&1; then
        log_warning "USIGN binary test failed, attempting alternative methods"
        
        # Try system usign if available
        if command -v usign >/dev/null 2>&1; then
            log_info "Using system usign instead"
            local system_usign="usign"
        else
            log_error "No working USIGN binary found"
            log_info "You can manually install usign or skip this step"
            log_info "On Ubuntu/Debian: apt install usign"
            log_info "On OpenWrt: opkg install usign"
            return 1
        fi
    else
        local system_usign="$USIGN_BIN"
    fi
    
    local temp_pub="${USIGN_KEY_DIR}/usign.pub"
    local temp_sec="${USIGN_KEY_DIR}/usign.sec"
    
    # Generate USIGN key pair
    if ! "$system_usign" -G -p "$temp_pub" -s "$temp_sec" \
         -c "Public usign key for fantastic-packages builds" 2>/dev/null; then
        log_error "Failed to generate USIGN keys"
        return 1
    fi
    
    # Get fingerprints and rename files
    local pub_fingerprint sec_fingerprint
    
    if ! pub_fingerprint=$("$system_usign" -F -p "$temp_pub" 2>/dev/null | tr 'a-z' 'A-Z'); then
        log_error "Failed to get public key fingerprint"
        return 1
    fi
    
    if ! sec_fingerprint=$("$system_usign" -F -s "$temp_sec" 2>/dev/null | tr 'a-z' 'A-Z'); then
        log_error "Failed to get secret key fingerprint"
        return 1
    fi
    
    if [[ -z "$pub_fingerprint" || -z "$sec_fingerprint" ]]; then
        log_error "Empty fingerprints received"
        return 1
    fi
    
    # Rename keys with fingerprint
    mv "$temp_pub" "${USIGN_KEY_DIR}/${pub_fingerprint}.pub"
    mv "$temp_sec" "${USIGN_KEY_DIR}/${sec_fingerprint}.sec"
    
    log_success "USIGN keys generated with fingerprints: ${pub_fingerprint}"
    return 0
}

# 📊 Display summary
display_summary() {
    echo
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                        🎉 KEY GENERATION COMPLETE               ║${NC}"
    echo -e "${CYAN}╠════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} Generated keys are stored in the following directories:        ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 🔑 APK Keys:   ${APK_KEY_DIR}/                          ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 🔐 GPG Keys:   ${GPG_KEY_DIR}/                            ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 🛡️  USIGN Keys: ${USIGN_KEY_DIR}/                         ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC}                                                                ${CYAN}║${NC}"
    echo -e "${CYAN}║${NC} 🔒 Keep your private keys and passwords secure!               ${CYAN}║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo
}

# 🧹 Cleanup function
cleanup_old_keys() {
    log_step "Cleaning up old/duplicate keys"
    
    # Clean up APK keys - keep only the most recent
    if [[ -d "$APK_KEY_DIR" ]]; then
        local apk_count=$(find "$APK_KEY_DIR" -name "*.pub" | wc -l)
        if [[ $apk_count -gt 1 ]]; then
            log_info "Found $apk_count APK key pairs, cleaning up old ones"
            find "$APK_KEY_DIR" -name "*.pub" -o -name "*.sec" | head -n -2 | xargs rm -f 2>/dev/null || true
        fi
    fi
    
    # Clean up GPG keys - keep only the most recent pair
    if [[ -d "$GPG_KEY_DIR" ]]; then
        local gpg_count=$(find "$GPG_KEY_DIR" -name "*.pub" | wc -l)
        if [[ $gpg_count -gt 1 ]]; then
            log_info "Found $gpg_count GPG key pairs, cleaning up old ones"
            # Get all GPG key files sorted by modification time (oldest first)
            find "$GPG_KEY_DIR" -name "*.pub" -printf '%T@ %p\n' | sort -n | head -n -1 | cut -d' ' -f2- | while read -r pub_file; do
                local base_name="${pub_file%.pub}"
                rm -f "${base_name}".* 2>/dev/null || true
                log_info "Removed old GPG key: $(basename "$base_name")"
            done
        fi
    fi
    
    # Clean up USIGN keys - keep only the most recent pair
    if [[ -d "$USIGN_KEY_DIR" ]]; then
        local usign_count=$(find "$USIGN_KEY_DIR" -name "*.pub" | wc -l)
        if [[ $usign_count -gt 1 ]]; then
            log_info "Found $usign_count USIGN key pairs, cleaning up old ones"
            find "$USIGN_KEY_DIR" -name "*.pub" -o -name "*.sec" | head -n -2 | xargs rm -f 2>/dev/null || true
        fi
    fi
    
    log_success "Cleanup completed"
}

# 🚀 Main execution
main() {
    # Set up trap for cleanup
    trap 'release_lock; exit 1' INT TERM EXIT
    
    echo -e "${PURPLE}🔐 Starting Modern Key Generation Script${NC}"
    echo -e "${PURPLE}=======================================${NC}"
    echo
    
    # Check requirements
    if ! command -v openssl >/dev/null 2>&1; then
        log_error "OpenSSL is required but not installed"
        exit 1
    fi
    
    if ! command -v gpg >/dev/null 2>&1; then
        log_error "GPG is required but not installed"
        exit 1
    fi
    
    # Acquire lock to prevent concurrent execution
    acquire_lock
    
    # Check for existing keys and handle accordingly
    check_existing_keys
    
    # Execute key generation steps
    create_directories || exit 1
    generate_apk_keys || exit 1
    generate_gpg_keys || exit 1
    
    # Try to generate USIGN keys, but don't fail if it doesn't work
    if ! generate_usign_keys; then
        log_warning "USIGN key generation failed, but continuing with other keys"
        log_info "USIGN keys can be generated manually later if needed"
    fi
    
    display_summary
    
    # Clean up and release lock
    trap - INT TERM EXIT
    release_lock
    
    log_success "Key generation completed! 🎉"
}

# Execute main function
main "$@"