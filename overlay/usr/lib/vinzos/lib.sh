# VinzOS shared helpers (BusyBox ash)

human_size() { # $1 = size in 512-byte sectors
    mb=$(( $1 / 2048 ))
    if [ "$mb" -ge 1024 ]; then
        echo "$(( mb / 1024 )).$(( (mb % 1024) * 10 / 1024 )) GB"
    else
        echo "$mb MB"
    fi
}

list_disks() {
    for p in /sys/block/*; do
        d=${p##*/}
        case "$d" in loop*|ram*|zram*|fd*|md*|dm-*) continue ;; esac
        echo "$d"
    done
}

disk_model() {
    m=""
    [ -r "/sys/block/$1/device/model" ] && m=$(cat "/sys/block/$1/device/model" 2>/dev/null)
    m=$(echo $m)
    echo "${m:-Unknown device}"
}

dev_sectors() { cat "/sys/class/block/$1/size"; }

part_name() {
    case "$1" in
        *[0-9]) echo "${1}p1" ;;
        *)      echo "${1}1" ;;
    esac
}

disk_parts() {
    for p in /sys/block/$1/*/partition; do
        [ -e "$p" ] || continue
        d=${p%/partition}
        echo "${d##*/}"
    done
}

dev_info() { # $1 = device name, $2 = TYPE | LABEL | UUID
    blkid "/dev/$1" 2>/dev/null | sed -n "s/.* $2=\"\([^\"]*\)\".*/\1/p"
}

mount_point_of() { awk -v d="/dev/$1" '$1==d {print $2; exit}' /proc/mounts; }

disk_is_busy() {
    for n in "$1" $(disk_parts "$1"); do
        [ -n "$(mount_point_of "$n")" ] && return 0
    done
    return 1
}

# make_partition <disk> [boot] : one DOS partition covering the whole disk
make_partition() {
    d=$1
    if [ "$2" = boot ]; then
        printf 'o\nn\np\n1\n\n\na\n1\nw\n' | fdisk "/dev/$d" >/dev/null 2>&1
    else
        printf 'o\nn\np\n1\n\n\nw\n' | fdisk "/dev/$d" >/dev/null 2>&1
    fi
    p=$(part_name "$d")
    i=0
    while [ ! -b "/dev/$p" ] && [ "$i" -lt 15 ]; do sleep 1; i=$((i+1)); done
    [ -b "/dev/$p" ]
}
