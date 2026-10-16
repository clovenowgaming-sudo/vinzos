#!/usr/bin/env python3
"""Print the module files (relative paths) needed for the given modules, with dependencies.
Usage: modclosure.py <modules dir with modules.dep> <module name>..."""
import os, sys

base, wanted = sys.argv[1], sys.argv[2:]
dep = {}
with open(os.path.join(base, "modules.dep")) as f:
    for line in f:
        if ":" not in line:
            continue
        path, deps = line.rstrip("\n").split(":", 1)
        dep[path] = deps.split()

def modname(p):
    return os.path.basename(p).split(".ko")[0].replace("-", "_")

by_name = {modname(p): p for p in dep}
need = set()

def add(p):
    if p in need:
        return
    need.add(p)
    for d in dep.get(p, []):
        add(d)

for w in wanted:
    k = w.replace("-", "_")
    if k in by_name:
        add(by_name[k])
    else:
        print("skip (not built): " + w, file=sys.stderr)

for p in sorted(need):
    print(p)
