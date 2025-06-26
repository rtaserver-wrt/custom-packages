# NOSIGNAL OPKG Repository
Custom Repository for OpenWRT

## How To Use
### On Running OpenWRT Firmware
1. Edit ` /etc/opkg.conf ` files, add ` # ` on front from ` option check_signature `
   - Before ` option check_signature `
   - After ` #option check_signature `
2. Edit ` /etc/opkg/customfeeds.conf ` and Add sign OPKG Repo. ex:
   ```bash
     src/gz sign-act https://repo.signdev.my.id/releases/22.03/packages/aarch64_generic/action
     src/gz sign-base https://repo.signdev.my.id/releases/22.03/packages/aarch64_generic/base
     src/gz sign-pkg https://repo.signdev.my.id/releases/22.03/packages/aarch64_generic/packages
     src/gz sign-luci https://repo.signdev.my.id/releases/22.03/packages/aarch64_generic/luci
     ```
   - Format : ` src/gz sign-pkg https://repo.signdev.my.id/releases/{OPENWRT_VERSION}/packages/{ARCH}/packages `
   - Supported OpenWRT Version : ` 21.xx 22.xx 23.xx `
   - Architecture Supported :
     ```
     x86_64
     mips_24kc
     mipsel_24kc
     arm_cortex-a7_neon-vfpv4
     aarch64_cortex-a53
     aarch64_cortex-a72
     aarch64_generic 
     ```
3. Run ` opkg update ` at ` Terminal ` or ` Update List ` at LUCI Dashboard ` System > Software `
   