#!/bin/bash
# Shared package policy for the clean Viettel/SDMC NR3053 image.
# This file is intentionally sourced by other scripts.
# shellcheck disable=SC2034

readonly -a NR3053_REQUIRED_PACKAGES=(
    luci
    luci-base
    luci-mod-admin-full
    luci-theme-bootstrap
    adguardhome
    kmod-conninfra
    kmod-mediatek_hnat
    kmod-mt_wifi
    kmod-nf-flow
    kmod-warp
    luci-app-mtwifi-cfg
    luci-app-turboacc-mtk
)

readonly -a NR3053_FORBIDDEN_PACKAGES=(
    adblock
    luci-app-adblock
    luci-i18n-adblock-vi
    blockd

    luci-app-ddns
    luci-i18n-ddns-vi
    ddns-scripts
    ddns-scripts-cloudflare
    ddns-scripts-noip

    luci-app-upnp
    luci-i18n-upnp-vi
    miniupnpd

    kmod-wireguard
    wireguard-tools
    luci-proto-wireguard
    rpcd-mod-wireguard

    luci-theme-aurora
    luci-app-aurora-config

    luci-app-nr3053-throughwall
    luci-i18n-nr3053-throughwall-vi

    kmod-zram
    zram-swap

    tailscale
    luci-app-tailscale-community

    default-settings
    default-settings-chn
    default-settings-vn

    kmod-usb3
    kmod-usb-ledtrig-usbport
    automount
    autosamba
)

readonly -a NR3053_BBR_SYMBOLS=(
    CONFIG_KERNEL_TCP_CONG_BBR
    CONFIG_KERNEL_DEFAULT_BBR
    CONFIG_PACKAGE_TURBOACC_INCLUDE_BBR_CCA
    CONFIG_PACKAGE_luci-app-turboacc_INCLUDE_BBR_CCA
    CONFIG_PACKAGE_luci-app-turboacc-mtk_INCLUDE_BBR_CCA
)

readonly -a NR3053_SUPPORTED_DEVICES=(
    "viettel,nr3053"
    "sdmc,nr3053"
)