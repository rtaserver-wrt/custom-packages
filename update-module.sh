#!/bin/bash

# OpenWrt Custom Packages Update Script
# This script initializes and updates packages for OpenWrt custom builds
# Author: rizkikotet
# Version: 2.0

set -euo pipefail

# Colors for terminal output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly BLUE='\033[1;34m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

# Environment variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PACKAGES_DIR="${SCRIPT_DIR}/feeds"
readonly LOG_FILE="${SCRIPT_DIR}/update.log"
readonly TEMP_DIR="$(mktemp -d)"

# Cleanup function
cleanup() {
    local exit_code=$?
    if [[ -d "$TEMP_DIR" ]]; then
        rm -rf "$TEMP_DIR"
    fi
    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed with exit code $exit_code"
    fi
    exit $exit_code
}

trap cleanup EXIT INT TERM

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO] $(date '+%Y-%m-%d %H:%M:%S'): $1${NC}" | tee -a "$LOG_FILE"
}

log_success() {
    echo -e "${GREEN}[SUCCESS] $(date '+%Y-%m-%d %H:%M:%S'): $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $(date '+%Y-%m-%d %H:%M:%S'): $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR] $(date '+%Y-%m-%d %H:%M:%S'): $1${NC}" | tee -a "$LOG_FILE" >&2
}

# Check if required commands exist
check_dependencies() {
    local missing_deps=()
    
    for cmd in git find mv rm; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

# Initialize environment
init_environment() {
    log_info "Initializing environment..."

    
    # Create packages directory if it doesn't exist
    if [[ ! -d "$PACKAGES_DIR" ]]; then
        mkdir -p "$PACKAGES_DIR"
        log_info "Created packages directory: $PACKAGES_DIR"
    fi
    
    # Initialize log file
    echo "=== OpenWrt Packages Update Log - $(date) ===" > "$LOG_FILE"
}

git_clone() {
    local url="$1"
    local destination="${2:-}"
    local max_attempts=3
    local attempt=1

    # Remove destination directory if it exists to avoid clone errors
    if [[ -n "$destination" && -d "$destination" ]]; then
        log_warning "Destination directory $destination already exists, removing before clone."
        rm -rf "$destination"
    fi

    while [[ $attempt -le $max_attempts ]]; do
        log_info "Cloning $url (attempt $attempt/$max_attempts)..."

        local git_args=("clone" "--depth" "1" "--single-branch" "$url")
        if [[ -n "$destination" ]]; then
            git_args+=("$destination")
        fi

        if git "${git_args[@]}" 2>>"$LOG_FILE"; then
            log_success "Successfully cloned $url"

            # Hapus folder .git agar folder bisa ditambahkan ke repo
            local target_dir="${destination:-$(basename "$url" .git)}"
            if [[ -d "$target_dir/.git" ]]; then
                rm -rf "$target_dir/.git"
                log_info "Removed .git folder from $target_dir"
            fi

            return 0
        else
            log_warning "Clone attempt $attempt failed for $url"
            if [[ $attempt -lt $max_attempts ]]; then
                sleep 2
                ((attempt++))
            else
                log_error "Failed to clone $url after $max_attempts attempts"
                return 1
            fi
        fi
    done
}

git_sparse_clone() {
    local branch="$1"
    local url="$2"
    shift 2
    local paths=("$@")

    local repo_name
    repo_name="$(basename "$url" .git)"
    local clone_dir="$TEMP_DIR/sparse_${repo_name}"

    log_info "Performing sparse clone of $url..."

    if [[ ${#branch} -lt 10 ]]; then
        git clone -b "$branch" --depth 1 --filter=blob:none --sparse "$url" "$clone_dir" 2>>"$LOG_FILE"
    else
        git clone --filter=blob:none --sparse "$url" "$clone_dir" 2>>"$LOG_FILE"
        (cd "$clone_dir" && git checkout "$branch" 2>>"$LOG_FILE")
    fi

    (
        cd "$clone_dir"
        git sparse-checkout init --cone
        git sparse-checkout set "${paths[@]}"
    ) 2>>"$LOG_FILE"

    for path in "${paths[@]}"; do
        local src="$clone_dir/$path"
        local dest="$PACKAGES_DIR"

        if [[ -e "$src" ]]; then
            log_info "Moving $src to $dest"
            mkdir -p "$(dirname "$dest")"
            mv -f "$src" "$dest" 2>>"$LOG_FILE" || true
        fi
    done

    rm -rf "$clone_dir/.git"
    log_info "Removed .git directory from sparse clone"
    rm -rf "$clone_dir"
}


mvdir() {
    local source_dir="$1"
    
    if [[ ! -d "$source_dir" ]]; then
        log_error "Source directory does not exist: $source_dir"
        return 1
    fi
    
    log_info "Moving packages from $source_dir..."
    
    # Find directories and move them (excluding .github and .git)
    while IFS= read -r -d '' dir; do
        local dir_name="$(basename "$dir")"
        
        # Skip .github and .git directories
        if [[ "$dir_name" == ".github" || "$dir_name" == ".git" ]]; then
            log_info "Skipping $dir_name directory"
            continue
        fi
        
        local dest_dir="$PACKAGES_DIR/$dir_name"
        
        if [[ -d "$dest_dir" ]]; then
            log_warning "Destination directory already exists, removing: $dest_dir"
            rm -rf "$dest_dir"
        fi
        
        if mv "$dir" "$PACKAGES_DIR/"; then
            log_success "Moved $dir_name to feeds directory"
        else
            log_error "Failed to move $dir_name"
            return 1
        fi
    done < <(find "$source_dir" -maxdepth 1 -type d -not -path "$source_dir" -print0)
    
    # Clean up source directory
    rm -rf "$source_dir"
    log_info "Cleaned up temporary directory: $source_dir"
}

# ================================================================================================================
# 
#
# ================================================================================================================

# Main execution
main() {
    check_dependencies
    init_environment
    log_info "Starting OpenWrt Custom Packages Update..."

    # Clone and move packages
    (
        git_clone https://github.com/xiaorouji/openwrt-passwall && mvdir openwrt-passwall
        git_clone https://github.com/xiaorouji/openwrt-passwall-packages && mvdir openwrt-passwall-packages
        git_sparse_clone "main" "https://github.com/nikkinikki-org/OpenWrt-nikki" \
            "luci-app-nikki" "nikki"
        git_clone https://github.com/derisamedia/luci-theme-alpha "$PACKAGES_DIR/luci-theme-alpha"
    ) &&
    (
        git_sparse_clone "master" "https://github.com/vernesong/OpenClash" "luci-app-openclash"
        git_sparse_clone openwrt-24.10 "https://github.com/immortalwrt/luci" \
            applications/luci-app-3ginfo-lite \
            applications/luci-app-argon-config \
            themes/luci-theme-argon
        
        git_sparse_clone master "https://github.com/obsy/packages" luci-proto-wwan 3ginfo modemband
    ) &&

    log_success "OpenWrt Custom Packages Update completed successfully."
}

# Run main function
main "$@"