#!/bin/sh

# OpenWrt Custom Packages Submodule Setup Script
# Author: rizkikotet

set -e

# Warna untuk output terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[1;34m'
NC='\033[0m' # No Color

add_submodule() {
  local repo_url=$1
  local branch=$2
  local path=$3

  echo -e "${BLUE}📦 Adding submodule: ${repo_url} -> ${path}${NC}"
  if [ ! -d "$path" ]; then
    git submodule add -b "$branch" --depth 1 "$repo_url" "$path" > /dev/null
    if [ $? -ne 0 ]; then
      echo -e "${RED}❌ Failed to add submodule: $repo_url${NC}"
      exit 1
    fi
    echo -e "${GREEN}✅ Submodule added: $path${NC}"
  else
    echo -e "${GREEN}✅ Submodule already exists: $path${NC}"
  fi
}

create_symlink() {
  local source=$1
  local target=$2

  if [ ! -e "$target" ]; then
    ln -s "$source" "$target"
    echo -e "${GREEN}🔗 Linked: $target → $source${NC}"
  else
    echo -e "${BLUE}⏭️  Skipped (exists): $target${NC}"
  fi
}

echo -e "${BLUE}🔄 Initializing submodules and symlinks...${NC}"

# OpenClash
add_submodule https://github.com/vernesong/OpenClash master submodule-packages/OpenClash
create_symlink ../../submodule-packages/OpenClash/luci-app-openclash feeds/luci/luci-app-openclash

# Passwall
add_submodule https://github.com/xiaorouji/openwrt-passwall main submodule-packages/openwrt-passwall
create_symlink ../../submodule-packages/openwrt-passwall/luci-app-passwall feeds/luci/luci-app-passwall

# Passwall Packages
add_submodule https://github.com/xiaorouji/openwrt-passwall-packages main submodule-packages/openwrt-passwall-packages

for dir in submodule-packages/openwrt-passwall-packages/*; do
  [ -d "$dir" ] || continue
  pkg_name=$(basename "$dir")
  create_symlink "../../$dir" "feeds/packages/$pkg_name"
done

# Nikki
add_submodule https://github.com/nikkinikki-org/OpenWrt-nikki main submodule-packages/OpenWrt-nikki
create_symlink ../../submodule-packages/OpenWrt-nikki/luci-app-nikki feeds/luci/luci-app-nikki
create_symlink ../../submodule-packages/OpenWrt-nikki/nikki feeds/packages/nikki




# Finalize
echo -e "${BLUE}🔃 Syncing submodules...${NC}"
git submodule sync
git submodule update --init --recursive --remote

echo -e "${GREEN}✅ Done.${NC}"
