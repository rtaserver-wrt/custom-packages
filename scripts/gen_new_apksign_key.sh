#!/bin/bash

# APK Signing Key Generator
# Generates ECDSA P-256 key pairs for APK signing

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Configuration
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly KEY_DIR="$SCRIPT_DIR/../keys/apksign"
readonly KEY_CURVE="prime256v1"
readonly TEMP_PRIVATE_KEY="private-key.pem"
readonly TEMP_PUBLIC_KEY="public-key.pem"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Generate timestamp-based key ID
generate_key_id() {
    date +%Y%m%d%H%M%S
}

# Validate dependencies
check_dependencies() {
    local deps=("openssl" "date" "tr" "sed")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        log_error "Missing required dependencies: ${missing[*]}"
        log_error "Please install the missing tools and try again."
        exit 1
    fi
}

# Create directory structure
setup_directories() {
    if [ ! -d "$KEY_DIR" ]; then
        log_info "Creating key directory: $KEY_DIR"
        mkdir -p "$KEY_DIR" || {
            log_error "Failed to create directory: $KEY_DIR"
            exit 1
        }
    fi
}

# Generate key pair
generate_keys() {
    local temp_private="$KEY_DIR/$TEMP_PRIVATE_KEY"
    local temp_public="$KEY_DIR/$TEMP_PUBLIC_KEY"
    
    log_info "Generating ECDSA P-256 key pair..."
    
    # Generate private key
    if ! openssl ecparam -name "$KEY_CURVE" -genkey -noout -out "$temp_private"; then
        log_error "Failed to generate private key"
        exit 1
    fi
    
    # Generate public key from private key
    if ! openssl ec -in "$temp_private" -pubout -out "$temp_public" 2>/dev/null; then
        log_error "Failed to generate public key"
        rm -f "$temp_private"  # Clean up on failure
        exit 1
    fi
    
    # Set restrictive permissions on private key
    chmod 600 "$temp_private"
    chmod 644 "$temp_public"
}

# Rename keys with timestamp ID
rename_keys() {
    local temp_private="$1"
    local temp_public="$2"
    local key_id="$3"
    
    local final_private="$KEY_DIR/${key_id}.sec"
    local final_public="$KEY_DIR/${key_id}.pub"
    
    log_info "Renaming keys with ID: $key_id"
    
    if ! mv "$temp_private" "$final_private"; then
        log_error "Failed to rename private key"
        exit 1
    fi
    
    if ! mv "$temp_public" "$final_public"; then
        log_error "Failed to rename public key"
        # Try to restore private key
        mv "$final_private" "$temp_private" 2>/dev/null || true
        exit 1
    fi
}

# Clean line endings (remove Windows line endings if present)
clean_line_endings() {
    local private_key="$1"
    local public_key="$2"
    
    log_info "Cleaning line endings..."
    
    # Use sed to remove carriage returns (cross-platform compatible)
    sed -i.bak 's/\r$//' "$private_key" "$public_key" 2>/dev/null || {
        # Fallback for systems where sed -i behaves differently
        sed 's/\r$//' "$private_key" > "$private_key.tmp" && mv "$private_key.tmp" "$private_key"
        sed 's/\r$//' "$public_key" > "$public_key.tmp" && mv "$public_key.tmp" "$public_key"
    }
    
    # Clean up backup files if they exist
    rm -f "$private_key.bak" "$public_key.bak" 2>/dev/null || true
}

# Verify generated keys
verify_keys() {
    local private_key="$1"
    local public_key="$2"
    
    log_info "Verifying generated keys..."
    
    # Check if private key is valid
    if ! openssl ec -in "$private_key" -check -noout 2>/dev/null; then
        log_error "Generated private key is invalid"
        return 1
    fi
    
    # Check if public key is valid
    if ! openssl ec -in "$public_key" -pubin -check -noout 2>/dev/null; then
        log_error "Generated public key is invalid"
        return 1
    fi
    
    log_info "Key verification successful"
}

# Display key information
show_key_info() {
    local key_id="$1"
    local private_key="$2"
    local public_key="$3"
    
    echo
    echo "============================="
    echo "APK Signing Keys Generated"
    echo "============================="
    echo "Key ID: $key_id"
    echo "Private Key: $private_key"
    echo "Public Key: $public_key"
    echo "Curve: $KEY_CURVE"
    echo
    
    # Show key fingerprints
    echo "Private Key Info:"
    openssl ec -in "$private_key" -text -noout 2>/dev/null | head -5
    echo
    
    echo "Public Key Fingerprint:"
    openssl ec -in "$public_key" -pubin -text -noout 2>/dev/null | grep -A 2 "pub:"
    echo "============================="
}

# Cleanup function for error handling
cleanup() {
    local temp_private="$KEY_DIR/$TEMP_PRIVATE_KEY"
    local temp_public="$KEY_DIR/$TEMP_PUBLIC_KEY"
    
    rm -f "$temp_private" "$temp_public" 2>/dev/null || true
}

# Main execution
main() {
    log_info "Starting APK signing key generation..."
    
    # Set up cleanup trap
    trap cleanup EXIT
    
    # Validate environment
    check_dependencies
    setup_directories
    
    # Generate unique key ID
    local key_id
    key_id=$(generate_key_id)
    
    # Check if key already exists
    if [ -f "$KEY_DIR/${key_id}.sec" ] || [ -f "$KEY_DIR/${key_id}.pub" ]; then
        log_warn "Keys with ID $key_id already exist, waiting 1 second..."
        sleep 1
        key_id=$(generate_key_id)
    fi
    
    # Generate keys
    local temp_private="$KEY_DIR/$TEMP_PRIVATE_KEY"
    local temp_public="$KEY_DIR/$TEMP_PUBLIC_KEY"
    generate_keys
    
    # Rename keys
    local final_private="$KEY_DIR/${key_id}.sec"
    local final_public="$KEY_DIR/${key_id}.pub"
    rename_keys "$temp_private" "$temp_public" "$key_id"
    
    # Clean line endings
    clean_line_endings "$final_private" "$final_public"
    
    # Verify keys
    verify_keys "$final_private" "$final_public"
    
    # Show results
    show_key_info "$key_id" "$final_private" "$final_public"
    
    log_info "APK signing key generation completed successfully!"
}

# Run main function
main "$@"