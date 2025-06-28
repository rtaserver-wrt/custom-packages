#!/bin/bash

# OpenWrt target architecture discovery script
# This script fetches all available targets and their architecture packages
# while eliminating duplicates and providing better error handling

OPENWRT_URL="https://downloads.openwrt.org"

# Function to get the latest stable OpenWrt version
get_latest_version() {
    echo "Fetching latest OpenWrt version..." >&2
    VERSION="$( \
        curl -sL "$OPENWRT_URL/" | sed -En '/Stable Release/,/(Old|Upcoming) Stable Release/p' \
        | sed -n '/<ul>/,/<\/ul>/p' | grep 'OpenWrt' \
        | sed -E "s|.+\breleases/([\.0-9]+)/.+|\1|g" \
    )"
    
    if [ -z "$VERSION" ]; then
        echo "Error: Could not determine OpenWrt version" >&2
        exit 1
    fi
    
    echo "Found OpenWrt version: $VERSION" >&2
    echo "$VERSION"
}

# Function to get all available targets
get_targets() {
    local version="$1"
    echo "Fetching available targets..." >&2
    
    TARGETS="$(curl -sL "$OPENWRT_URL/releases/$version/targets/" \
        | sed -n '/<table>/,/<\/table>/p' | grep '<a href=' \
        | sed -E "s|.+\bhref=\"([^/]+)/.+|\1|g" \
    )"
    
    if [ -z "$TARGETS" ]; then
        echo "Error: Could not fetch targets list" >&2
        exit 1
    fi
    
    echo "$TARGETS"
}

# Function to process targets and extract unique architectures
# This is where we solve the duplicate problem
print_unique_architectures() {
    local version="$1"
    local targets="$2"
    local temp_file=$(mktemp)
    local arch_file=$(mktemp)
    
    echo "Processing targets and extracting architectures..." >&2
    
    # First pass: collect all target/subtarget -> arch_packages mappings
    for target in $targets; do
        echo "Processing target: $target" >&2
        
        # Get subtargets for this target
        SUBTARGETS="$(curl -sL "$OPENWRT_URL/releases/$version/targets/$target/" \
            | sed -n '/<table>/,/<\/table>/p' | grep '<a href=' \
            | sed -E "s|.+\bhref=\"([^/]+)/.+|\1|g" \
        )"
        
        # Process each subtarget
        for subtarget in $SUBTARGETS; do
            echo "  Processing subtarget: $subtarget" >&2
            
            # Fetch the profiles.json with error handling
            profiles="$(curl -sL "$OPENWRT_URL/releases/$version/targets/$target/$subtarget/profiles.json" 2>/dev/null)"
            
            if [ -n "$profiles" ]; then
                # Extract architecture package name
                arch_packages="$(echo "$profiles" | jq -rc '.arch_packages' 2>/dev/null)"
                
                # Only process if we got a valid architecture name
                if [ -n "$arch_packages" ] && [ "$arch_packages" != "null" ]; then
                    # Store the mapping in temporary file
                    printf "%-25s %s\n" "'$target/$subtarget'" "$arch_packages" >> "$temp_file"
                    # Also store just the architecture for uniqueness checking
                    echo "$arch_packages" >> "$arch_file"
                fi
            else
                echo "  Warning: Could not fetch profiles for $target/$subtarget" >&2
            fi
        done
    done
    
    echo "Generating results..." >&2
    
    # Create the complete mapping file (all targets with their architectures)
    echo "# Complete OpenWrt Target -> Architecture Mapping" > targets_complete.txt
    echo "# Format: 'target/subtarget' architecture_package" >> targets_complete.txt
    echo "" >> targets_complete.txt
    sort "$temp_file" >> targets_complete.txt
    
    # Create the unique architectures file (deduplicated)
    echo "# Unique OpenWrt Architecture Packages" > targets_unique.txt
    echo "# Each architecture appears only once" >> targets_unique.txt
    echo "" >> targets_unique.txt
    sort "$arch_file" | uniq >> targets_unique.txt
    
    # Create a summary file showing which targets use each architecture
    echo "# OpenWrt Architecture Usage Summary" > targets_summary.txt
    echo "# Shows which targets use each architecture package" >> targets_summary.txt
    echo "" >> targets_summary.txt

    # Group targets by architecture (for TXT)
    for arch in $(sort "$arch_file" | uniq); do
        echo "Architecture: $arch" >> targets_summary.txt
        grep " $arch$" "$temp_file" | sed 's/^/  /' >> targets_summary.txt
        echo "" >> targets_summary.txt
    done

    # Create JSON summary file
    echo "{" > targets_summary.json
    first=1
    for arch in $(sort "$arch_file" | uniq); do
        if [ $first -eq 0 ]; then
            echo "," >> targets_summary.json
        fi
        first=0
        # Get all targets for this arch as a JSON array
        targets=$(grep " $arch$" "$temp_file" | awk '{print $1}' | sed "s/'//g" | jq -R . | jq -s .)
        echo "  \"$arch\": $targets" >> targets_summary.json
    done
    echo "}" >> targets_summary.json

    # Create arch_openwrt.json: list of {arch, target} (unique arch only)
    echo "[" > arch_openwrt.json
    first=1
    # Gunakan associative array untuk filter arch unik
    declare -A arch_seen
    while read -r line; do
        target=$(echo "$line" | awk '{print $1}' | sed "s/'//g")
        arch=$(echo "$line" | awk '{print $2}')
        if [ -z "${arch_seen[$arch]}" ]; then
            arch_seen[$arch]=1
            if [ $first -eq 0 ]; then
                echo "," >> arch_openwrt.json
            fi
            first=0
            echo "  {\"arch\": \"$arch\", \"target\": \"$target\"}" >> arch_openwrt.json
        fi
    done < "$temp_file"
    echo "]" >> arch_openwrt.json

    # Clean up temporary files
    rm "$temp_file" "$arch_file"
    
    echo "Results saved to:" >&2
    echo "  - targets_complete.txt (all target/architecture mappings)" >&2
    echo "  - targets_unique.txt (unique architectures only)" >&2
    echo "  - targets_summary.txt (architectures grouped by usage)" >&2
}

# Main execution flow
main() {
    # Check if required tools are available
    if ! command -v curl >/dev/null 2>&1; then
        echo "Error: curl is required but not installed" >&2
        exit 1
    fi
    
    if ! command -v jq >/dev/null 2>&1; then
        echo "Error: jq is required but not installed" >&2
        exit 1
    fi
    
    # Get version and targets
    VERSION=$(get_latest_version)
    TARGETS=$(get_targets "$VERSION")
    
    # Process and generate results
    print_unique_architectures "$VERSION" "$TARGETS"
    
    echo "Script completed successfully!" >&2
}

# Run the main function
main