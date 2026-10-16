#!/usr/bin/env python3
"""Copy programs and their shared libraries from a chroot into a rootfs WITHOUT running anything.
Usage: copydeps.py <chroot> <rootfs> bin <name>...        copy programs (+ libs), prints where they went
       copydeps.py <chroot> <rootfs> libs <soname>...     copy libraries by name
       copydeps.py <chroot> <rootfs> file <src> <dest> [octal-mode]"""
import os, re, shutil, subprocess, sys

def die(msg):
    print("copydeps: " + msg, file=sys.stderr)
    sys.exit(1)

if len(sys.argv) < 5:
    die("usage: copydeps.py <chroot> <rootfs> <bin|libs|file> args...")
CH = os.path.abspath(sys.argv[1]); RFS = os.path.abspath(sys.argv[2])
MODE = sys.argv[3]; ARGS = sys.argv[4:]
SEARCH_BIN = ["/usr/sbin", "/usr/bin", "/sbin", "/bin"]

def resolve(path):
    """Follow symlinks as if CH were the filesystem root."""
    parts = [p for p in path.split("/") if p]
    cur, hops = "/", 0
    while parts:
        p = parts.pop(0)
        if p == ".":
            continue
        if p == "..":
            cur = os.path.dirname(cur) or "/"
            continue
        nxt = os.path.join(cur, p)
        if os.path.islink(CH + nxt):
            hops += 1
            if hops > 40:
                die("symlink loop: " + path)
            tgt = os.readlink(CH + nxt)
            if tgt.startswith("/"):
                cur = "/"
            parts = [x for x in tgt.split("/") if x] + parts
        else:
            cur = nxt
    return cur

def real_file(path):
    f = CH + resolve(path)
    return f if os.path.isfile(f) else None

def put(dest, src, mode=0o755):
    out = RFS + dest
    os.makedirs(os.path.dirname(out), exist_ok=True)
    if os.path.lexists(out):
        os.remove(out)
    shutil.copyfile(src, out)
    os.chmod(out, mode)

def libdirs():
    dirs = []
    for base in ("/lib", "/usr/lib"):
        full = CH + resolve(base)
        if not os.path.isdir(full):
            continue
        for e in sorted(os.listdir(full)):
            if e.endswith("-linux-gnu") and os.path.isdir(os.path.join(full, e)):
                dirs.append(base + "/" + e)
        dirs.append(base)
    dirs.append("/lib64")
    return dirs

LIBDIRS = libdirs()
done = set()

def scan(real):
    out = subprocess.run(["readelf", "-d", "-l", real], capture_output=True, text=True).stdout
    m = re.search(r"Requesting program interpreter: ([^\]]+)\]", out)
    if m:
        interp = m.group(1).strip()
        if interp not in done:
            done.add(interp)
            src = real_file(interp)
            if not src:
                die("missing interpreter: " + interp)
            put(interp, src)
    for so in re.findall(r"\(NEEDED\)\s+Shared library: \[([^\]]+)\]", out):
        add_lib(so)

def add_lib(so):
    if so in done:
        return
    done.add(so)
    for d in LIBDIRS:
        src = real_file(d + "/" + so)
        if src:
            put(d + "/" + so, src)
            scan(src)
            return
    die("library not found in chroot: " + so)

if MODE == "bin":
    for name in ARGS:
        cands = [name] if name.startswith("/") else [d + "/" + name for d in SEARCH_BIN]
        for c in cands:
            src = real_file(c)
            if src:
                put(c, src)
                scan(src)
                print(c)
                break
        else:
            die("program not found in chroot: " + name)
elif MODE == "libs":
    for so in ARGS:
        add_lib(so)
elif MODE == "file":
    src = real_file(ARGS[0])
    if not src:
        die("file not found in chroot: " + ARGS[0])
    put(ARGS[1], src, int(ARGS[2], 8) if len(ARGS) > 2 else 0o644)
else:
    die("unknown mode: " + MODE)
