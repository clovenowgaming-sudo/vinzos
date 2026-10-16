#!/usr/bin/env bash
# VinzOS builder. Usage: ./build.sh <x86_64|i386>
set -Eeuo pipefail
trap 'echo "build.sh failed at line $LINENO: $BASH_COMMAND" >&2' ERR
ARCH="${1:-x86_64}"
KVER="${KVER:-6.12.1}"
BBVER="${BBVER:-1.36.1}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
case "$ARCH" in
  x86_64) DEBARCH=amd64; LABEL=64bit; BBM32="" ;;
  i386)   DEBARCH=i386;  LABEL=32bit; BBM32="-m32" ;;
  *) echo "usage: $0 <x86_64|i386>" >&2; exit 1 ;;
esac
SRC="$ROOT/work/src"; WORK="$ROOT/work/$ARCH"; OUT="$ROOT/out/$ARCH"
RFS="$WORK/rootfs"; CH="$WORK/chroot"
JOBS="${JOBS:-$(nproc)}"
mkdir -p "$SRC" "$WORK" "$OUT"

# ---------------------------------------------------------------- kernel
echo "==> [$ARCH] Kernel $KVER"
cd "$SRC"
[ -f linux-$KVER.tar.xz ] || wget -q "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-$KVER.tar.xz"
[ -d linux-$KVER ] || tar xf linux-$KVER.tar.xz
grep -q '<stdio.h>' linux-$KVER/certs/extract-cert.c || sed -i '1i #include <stdio.h>\n#include <string.h>' linux-$KVER/certs/extract-cert.c

KB="$WORK/kbuild"; rm -rf "$KB"; mkdir -p "$KB"
KMAKE=(make -C "$SRC/linux-$KVER" O="$KB" ARCH="$ARCH")
CFG=("$SRC/linux-$KVER/scripts/config" --file "$KB/.config")
cfg_y() { for s in "$@"; do "${CFG[@]}" --enable "$s"; done; }
cfg_m() { for s in "$@"; do "${CFG[@]}" --module "$s"; done; }
cfg_n() { for s in "$@"; do "${CFG[@]}" --disable "$s"; done; }

"${KMAKE[@]}" defconfig
cfg_n MODULE_SIG MODULE_SIG_ALL SYSTEM_TRUSTED_KEYRING SECONDARY_TRUSTED_KEYRING SYSTEM_REVOCATION_LIST
if [ "$ARCH" = i386 ]; then cfg_n NOHIGHMEM; cfg_y HIGHMEM4G; fi
# base system, storage, filesystems, input, usb
cfg_y DEVTMPFS DEVTMPFS_MOUNT UEVENT_HELPER MODULES BLK_DEV_INITRD \
  SCSI BLK_DEV_SD ATA ATA_PIIX ATA_GENERIC SATA_AHCI VIRTIO_BLK BLK_DEV_NVME \
  EXT4_FS VFAT_FS FAT_FS MSDOS_FS ISO9660_FS JOLIET EXFAT_FS NTFS3_FS \
  NLS_CODEPAGE_437 NLS_ISO8859_1 NLS_UTF8 \
  USB USB_PCI USB_XHCI_HCD USB_EHCI_HCD USB_OHCI_HCD USB_UHCI_HCD USB_STORAGE \
  HID HID_GENERIC USB_HID INPUT_KEYBOARD KEYBOARD_ATKBD SERIO_I8042
# wired network (built in, so Ethernet works with no module loading)
cfg_y NETDEVICES ETHERNET NET_VENDOR_INTEL NET_VENDOR_REALTEK NET_VENDOR_BROADCOM \
  NET_VENDOR_ATHEROS NET_VENDOR_MARVELL NET_VENDOR_VIA NET_VENDOR_NVIDIA \
  E100 E1000 E1000E IGB IGC R8169 8139TOO TIGON3 BNX2 ATL1C ATL1E SKY2 FORCEDETH VIA_RHINE VIRTIO_NET \
  USB_NET_DRIVERS USB_USBNET USB_NET_CDCETHER USB_NET_CDC_NCM USB_NET_CDC_EEM USB_NET_RNDIS_HOST \
  USB_NET_AX8817X USB_NET_AX88179_178A USB_RTL8152
# crypto needed by WPA (built in)
cfg_y CRYPTO_AES CRYPTO_CCM CRYPTO_GCM CRYPTO_CTR CRYPTO_CMAC CRYPTO_ECB CRYPTO_CBC CRYPTO_HMAC \
  CRYPTO_SHA1 CRYPTO_SHA256 CRYPTO_SHA512 CRYPTO_MD5 CRYPTO_GHASH CRYPTO_LIB_ARC4 FW_LOADER
# WiFi
cfg_y WIRELESS RFKILL WLAN WLAN_VENDOR_INTEL WLAN_VENDOR_ATH WLAN_VENDOR_REALTEK WLAN_VENDOR_RALINK \
  WLAN_VENDOR_MEDIATEK WLAN_VENDOR_BROADCOM WLAN_VENDOR_MARVELL WLAN_VENDOR_ZYDAS
cfg_m CFG80211 MAC80211 \
  IWLWIFI IWLDVM IWLMVM \
  ATH5K ATH9K ATH9K_HTC ATH10K ATH10K_PCI ATH10K_USB ATH11K ATH11K_PCI ATH12K \
  RTL8187 RTLWIFI RTL8192CE RTL8192CU RTL8192SE RTL8192DE RTL8723AE RTL8723BE RTL8188EE RTL8192EE RTL8821AE RTL8XXXU \
  RTW88 RTW88_8822BE RTW88_8822CE RTW88_8723DE RTW88_8821CE RTW88_8822BU RTW88_8822CU RTW88_8723DU RTW88_8821CU \
  RTW89 RTW89_8851BE RTW89_8852AE RTW89_8852BE RTW89_8852CE RTW89_8922AE \
  BRCMSMAC BRCMFMAC BRCMFMAC_PCIE BRCMFMAC_USB \
  RT2X00 RT2400PCI RT2500PCI RT2500USB RT61PCI RT73USB RT2800PCI RT2800USB \
  MT7601U MT76x0U MT76x0E MT76x2E MT76x2U MT7603E MT7615E MT7915E MT7921E MT7921U MT7925E MT7925U \
  MWIFIEX MWIFIEX_PCIE MWIFIEX_USB ZD1211RW
"${KMAKE[@]}" olddefconfig
"${KMAKE[@]}" -j"$JOBS" bzImage modules
cp "$KB/arch/x86/boot/bzImage" "$OUT/bzImage"
KREL=$(cat "$KB/include/config/kernel.release")
echo "==> kernel release: $KREL"
STAGE="$WORK/modstage"; rm -rf "$STAGE"
"${KMAKE[@]}" modules_install INSTALL_MOD_PATH="$STAGE" INSTALL_MOD_STRIP=1

# ---------------------------------------------------------------- busybox
echo "==> [$ARCH] BusyBox $BBVER"
cd "$SRC"
[ -f busybox-$BBVER.tar.bz2 ] || wget -q https://busybox.net/downloads/busybox-$BBVER.tar.bz2
[ -d busybox-$BBVER ] || tar xf busybox-$BBVER.tar.bz2
BB="$WORK/bb"; rm -rf "$BB"; mkdir -p "$BB"
BBMAKE=(make -C "$SRC/busybox-$BBVER" O="$BB")
"${BBMAKE[@]}" defconfig
sed -i "s/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/; s/^CONFIG_TC=y/# CONFIG_TC is not set/; s|^CONFIG_EXTRA_CFLAGS=.*|CONFIG_EXTRA_CFLAGS=\"$BBM32\"|; s|^CONFIG_EXTRA_LDFLAGS=.*|CONFIG_EXTRA_LDFLAGS=\"$BBM32\"|" "$BB/.config"
(yes "" || true) | "${BBMAKE[@]}" oldconfig >/dev/null
"${BBMAKE[@]}" -j"$JOBS"
rm -rf "$RFS"
"${BBMAKE[@]}" CONFIG_PREFIX="$RFS" install

# ---------------------------------------------------------------- tool chroot
echo "==> [$ARCH] Tool chroot (Debian bookworm / $DEBARCH)"
sudo rm -rf "$CH"
sudo debootstrap --arch="$DEBARCH" --variant=minbase \
  --include=extlinux,syslinux-common,e2fsprogs,kmod,wpasupplicant,iw,curl,ca-certificates,wireless-regdb \
  bookworm "$CH" http://deb.debian.org/debian

CD=(python3 "$ROOT/tools/copydeps.py" "$CH" "$RFS")

# ---------------------------------------------------------------- rootfs
echo "==> [$ARCH] Rootfs"
cd "$RFS"
mkdir -p proc sys dev tmp root var/lib/vp var/run mnt boot lib/firmware usr/share/vinzos/syslinux etc/ssl/certs
cp -a "$ROOT/overlay/." .

"${CD[@]}" bin mke2fs extlinux wpa_supplicant wpa_cli wpa_passphrase iw curl kmod
KMOD_PATH=$("${CD[@]}" bin kmod)
for t in modprobe depmod insmod lsmod rmmod modinfo; do
  rm -f "sbin/$t" "bin/$t"; ln -s "$KMOD_PATH" "bin/$t"
done
"${CD[@]}" libs libnss_files.so.2 libnss_dns.so.2 libresolv.so.2
"${CD[@]}" file /etc/mke2fs.conf /etc/mke2fs.conf 644 || true
"${CD[@]}" file /usr/lib/syslinux/mbr/mbr.bin /usr/share/vinzos/syslinux/mbr.bin 644
"${CD[@]}" file /usr/lib/syslinux/modules/bios/ldlinux.c32 /usr/share/vinzos/syslinux/ldlinux.c32 644
"${CD[@]}" file /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt 644
for f in regulatory.db regulatory.db.p7s; do
  "${CD[@]}" file "/lib/firmware/$f" "/lib/firmware/$f" 644 || echo "note: $f not found"
done
printf 'hosts: files dns\n' > etc/nsswitch.conf
echo '127.0.0.1 localhost' > etc/hosts
printf 'nameserver 1.1.1.1\nnameserver 8.8.8.8\n' > etc/resolv.conf

# WiFi kernel modules: only what WiFi needs, plus dependencies
echo "==> [$ARCH] WiFi modules"
WANTED="cfg80211 mac80211 iwlwifi iwldvm iwlmvm ath5k ath9k ath9k_htc ath10k_pci ath10k_usb ath11k_pci ath12k \
rtl8187 rtl8192ce rtl8192cu rtl8192se rtl8192de rtl8723ae rtl8723be rtl8188ee rtl8192ee rtl8821ae rtl8xxxu \
rtw88_8822be rtw88_8822ce rtw88_8723de rtw88_8821ce rtw88_8822bu rtw88_8822cu rtw88_8723du rtw88_8821cu \
rtw89_8851be rtw89_8852ae rtw89_8852be rtw89_8852ce rtw89_8922ae brcmsmac brcmfmac \
rt2400pci rt2500pci rt2500usb rt61pci rt73usb rt2800pci rt2800usb \
mt7601u mt76x0e mt76x0u mt76x2e mt76x2u mt7603e mt7615e mt7915e mt7921e mt7921u mt7925e mt7925u \
mwifiex_pcie mwifiex_usb zd1211rw"
MODSRC="$STAGE/lib/modules/$KREL"
python3 "$ROOT/tools/modclosure.py" "$MODSRC" $WANTED | while read -r p; do
  install -D -m 644 "$MODSRC/$p" "$RFS/lib/modules/$KREL/$p"
done
for f in modules.order modules.builtin modules.builtin.modinfo; do
  [ -f "$MODSRC/$f" ] && cp "$MODSRC/$f" "$RFS/lib/modules/$KREL/$f"
done
depmod -b "$RFS" "$KREL"
echo "modules installed: $(find "$RFS/lib/modules/$KREL" -name '*.ko*' | wc -l)"

cd "$RFS"
cp "$OUT/bzImage" boot/bzImage
chmod +x init bin/vp bin/vnet bin/vstorage bin/vwifi bin/help sbin/install-vinzos sbin/shutdown sbin/uevent-helper etc/init.d/rcS etc/udhcpc.script
find . | cpio -o -H newc -R 0:0 2>/dev/null | gzip -9 > "$OUT/initramfs.gz"

# ---------------------------------------------------------------- ISO (BIOS, USB-bootable)
echo "==> [$ARCH] ISO"
ISO="$WORK/iso"; rm -rf "$ISO"; mkdir -p "$ISO/boot"
cp "$OUT/bzImage" "$OUT/initramfs.gz" "$ISO/boot/"
cp /usr/lib/ISOLINUX/isolinux.bin /usr/lib/syslinux/modules/bios/ldlinux.c32 "$ISO/"
cat > "$ISO/isolinux.cfg" << 'CFG'
DEFAULT vinzos
PROMPT 0
TIMEOUT 10
LABEL vinzos
  KERNEL /boot/bzImage
  APPEND initrd=/boot/initramfs.gz console=tty0
CFG
xorriso -as mkisofs -V VINZOS -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
  -o "$OUT/vinzos-$LABEL.iso" -b isolinux.bin -c boot.cat \
  -no-emul-boot -boot-load-size 4 -boot-info-table "$ISO"
echo "==> [$ARCH] Done"; ls -lh "$OUT"
