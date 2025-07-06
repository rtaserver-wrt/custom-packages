#!/bin/bash

# OpenWrt Custom Packages Update Script
# This script initializes and updates packages for OpenWrt custom builds
# Author: rizkikotet
# Version: 2.1

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

    # Determine the actual destination directory
    local target_dir
    if [[ -n "$destination" ]]; then
        target_dir="$destination"
    else
        target_dir="$(basename "$url" .git)"
    fi

    # Remove destination directory if it exists to avoid clone errors
    if [[ -d "$target_dir" ]]; then
        log_warning "Destination directory $target_dir already exists, removing before clone."
        rm -rf "$target_dir"
    fi

    while [[ $attempt -le $max_attempts ]]; do
        log_info "Cloning $url (attempt $attempt/$max_attempts)..."

        local git_args=("clone" "--depth" "1" "--single-branch" "$url")
        if [[ -n "$destination" ]]; then
            git_args+=("$destination")
        fi

        # Print git errors to both log and console
        if git "${git_args[@]}" 2> >(tee -a "$LOG_FILE" >&2); then
            log_success "Successfully cloned $url"

            # Hapus folder .git agar folder bisa ditambahkan ke repo
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

    log_info "Performing sparse clone of $url (branch: $branch)..."

    # Clone the repo with sparse-checkout
    git clone --quiet --filter=blob:none --sparse "$url" "$clone_dir" 2>>"$LOG_FILE"

    (
        cd "$clone_dir"
        # Checkout the specific branch/commit if provided
        if [[ -n "$branch" ]]; then
            git checkout "$branch" 2>>"$LOG_FILE"
        fi

        # Initialize and set sparse-checkout
        git sparse-checkout init --cone 2>>"$LOG_FILE"
        git sparse-checkout set "${paths[@]}" 2>>"$LOG_FILE"
    )

    # Move each specified path to the packages directory
    for path in "${paths[@]}"; do
        local src="$clone_dir/$path"
        local dest="$PACKAGES_DIR/$(basename "$path")"

        if [[ -e "$src" ]]; then
            log_info "Moving $src to $dest"
            # Remove existing destination if it exists
            if [[ -e "$dest" ]]; then
                rm -rf "$dest"
            fi
            mkdir -p "$(dirname "$dest")"
            mv -f "$src" "$dest" 2>>"$LOG_FILE" || true
        else
            log_warning "Path $src does not exist in the repository"
        fi
    done

    # Clean up the temporary clone directory
    rm -rf "$clone_dir"
    log_info "Cleaned up temporary sparse clone directory: $clone_dir"
}

mvdir() {
    local source_dir="$1"
    if [[ ! -d "$source_dir" ]]; then
        log_error "Source directory does not exist: $source_dir"
        return 1
    fi
    log_info "Moving packages from $source_dir..."
    local moved_any=0
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
        log_info "Moving $dir to $PACKAGES_DIR"
        if mv -f "$dir" "$PACKAGES_DIR/"; then
            log_success "Moved $dir_name to feeds directory"
            moved_any=1
        else
            log_error "Failed to move $dir_name"
            return 1
        fi
    done < <(find "$source_dir" -mindepth 1 -maxdepth 1 -type d -print0)
    if [[ $moved_any -eq 0 ]]; then
        log_warning "No packages were moved from $source_dir (nothing to do)"
    fi
    # Clean up source directory
    if [[ -d "$source_dir" ]]; then
        log_info "Cleaning up source directory: $source_dir"
        rm -rf "$source_dir"
    fi
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
    git_clone https://github.com/xiaorouji/openwrt-passwall && mvdir openwrt-passwall || { log_error "Error processing openwrt-passwall"; exit 1; }
    git_clone https://github.com/xiaorouji/openwrt-passwall-packages && mvdir openwrt-passwall-packages || { log_error "Error processing openwrt-passwall-packages"; exit 1; }
    git_sparse_clone "main" "https://github.com/nikkinikki-org/OpenWrt-nikki" \
        "luci-app-nikki" "nikki" || { log_error "Error processing OpenWrt-nikki"; exit 1; }
    git_clone https://github.com/derisamedia/luci-theme-alpha "$PACKAGES_DIR/luci-theme-alpha" || { log_error "Error processing luci-theme-alpha"; exit 1; }
    git_sparse_clone "master" "https://github.com/vernesong/OpenClash" "luci-app-openclash" || { log_error "Error processing OpenClash"; exit 1; }
    git_sparse_clone "openwrt-24.10" "https://github.com/immortalwrt/luci" \
        "applications/luci-app-3ginfo-lite" \
        "applications/luci-app-argon-config" \
        "themes/luci-theme-argon" || { log_error "Error processing immortalwrt/luci"; exit 1; }
    git_sparse_clone "master" "https://github.com/obsy/packages" \
        "luci-proto-wwan" "3ginfo" "modemband" || { log_error "Error processing obsy/packages"; exit 1; }
    log_success "OpenWrt Custom Packages Update completed successfully."
}

# Run main function
main "$@"