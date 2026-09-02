#!/usr/bin/env bash
#
# Extract module metadata into a JSON manifest beside the .sqsh artefact.
#
#   sudo ./scripts/06_extract_metadata.sh <name> [--parent NAME|none]
#                                                [--version V]
#                                                [--requested "pkg [pkg...]"]
#
# Why this exists:
#   Until now the checker read /var/lib/dpkg/status straight out of the build
#   tree, so metadata-only validation still needed a few hundred MB of chroot
#   per module. This writes the same information next to the artefact, so
#   base.sqsh + base.json is everything a consistency check needs. The build
#   tree becomes disposable scratch, which is what it was always meant to be.
#
# What lands in the file:
#   - identity  : module, version, parent, snapshot, suite, arch, build time
#   - the ARCHITECTURE section 5 module-dependency layer, empty for now
#   - requested : the packages actually asked for on the build command line
#   - artifact  : .sqsh name, size and sha256 (reproducibility evidence)
#   - packages  : ONLY this module's contribution -- packages whose
#                 (name, version) differ from the parent's. Full dpkg
#                 relations for each: Depends, Pre-Depends, Conflicts,
#                 Breaks, Replaces, Provides.
#   - removed   : packages the parent had and this module does not
#
#   Consumers rebuild the merged view as:
#       effective(m) = parent.packages | m.packages  -  m.removed
#
# Re-running is safe: hand-written requires/conflicts/provides/version, and a
# previously recorded requested list, are carried over rather than wiped.
#
# Output: $MOD_DIR/<name>.json

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"
need_root

NAME=""
PARENT="base"
MOD_VERSION=""
REQUESTED=""

while [ $# -gt 0 ]; do
    case "$1" in
        --parent)
            [ $# -ge 2 ] || die "--parent needs a value"
            PARENT="$2"; shift 2 ;;
        --version)
            [ $# -ge 2 ] || die "--version needs a value"
            MOD_VERSION="$2"; shift 2 ;;
        --requested)
            [ $# -ge 2 ] || die "--requested needs a value"
            REQUESTED="$2"; shift 2 ;;
        -*)
            die "unknown option: $1" ;;
        *)
            [ -z "$NAME" ] || die "unexpected argument: $1"
            NAME="$1"; shift ;;
    esac
done

[ -n "$NAME" ] || die "usage: $0 <name> [--parent NAME|none] [--version V] [--requested \"pkg ...\"]"

# Base keeps its full rootfs in <name>.dir; deltas keep only the overlay
# upperdir in <name>.upper. Either one carries a complete dpkg status file:
# apt rewrites status wholesale, so a delta's copy lands in the upperdir.
module_tree() {          # module_tree <name> -> path on stdout, empty if none
    local n="$1"
    if   [ -d "${MOD_DIR}/${n}.upper" ]; then echo "${MOD_DIR}/${n}.upper"
    elif [ -d "${MOD_DIR}/${n}.dir"   ]; then echo "${MOD_DIR}/${n}.dir"
    fi
}

TREE="$(module_tree "$NAME")"
[ -n "$TREE" ] || die "no build tree for '${NAME}' in ${MOD_DIR} (expected ${NAME}.upper or ${NAME}.dir)"
[ -f "${TREE}/var/lib/dpkg/status" ] || die "no dpkg status in ${TREE}"

PARENT_TREE=""
case "$PARENT" in
    ""|none|NONE|None)
        PARENT="" ;;
    *)
        PARENT_TREE="$(module_tree "$PARENT")"
        [ -n "$PARENT_TREE" ] || die "no build tree for parent '${PARENT}' in ${MOD_DIR}"
        [ -f "${PARENT_TREE}/var/lib/dpkg/status" ] || die "no dpkg status in ${PARENT_TREE}"
        ;;
esac

SQSH="${MOD_DIR}/${NAME}.sqsh"
OUT="${MOD_DIR}/${NAME}.json"
[ -f "$SQSH" ] || warn "artefact ${SQSH} not found; artifact block will be null"

log "extracting metadata for '${NAME}'"
log "  tree   : ${TREE}"
log "  parent : ${PARENT:-<none>}"

export M_NAME="$NAME"
export M_TREE="$TREE"
export M_PARENT="$PARENT"
export M_PARENT_TREE="$PARENT_TREE"
export M_VERSION="$MOD_VERSION"
export M_REQUESTED="$REQUESTED"
export M_SNAPSHOT="$SNAPSHOT_ID"
export M_SUITE="$SUITE"
export M_ARCH="$ARCH"
export M_SQSH="$SQSH"
export M_OUT="$OUT"
export M_BUILT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

python3 - <<'PY' || die "metadata extraction failed"
import hashlib, json, os, sys, tempfile

E = os.environ
SCHEMA = 1

def warn(msg):
    sys.stderr.write("\033[1;33m[warn]\033[0m %s\n" % msg)

# JSON key -> dpkg control field. All six relation types are captured even
# though today's checker only consults Conflicts/Breaks: Replaces is what
# file-collision detection (class 4) will need, Provides is what virtual
# package checking will need, and neither can be recovered once the build
# tree is deleted.
RELATIONS = [
    ("depends",     "Depends"),
    ("pre_depends", "Pre-Depends"),
    ("conflicts",   "Conflicts"),
    ("breaks",      "Breaks"),
    ("replaces",    "Replaces"),
    ("provides",    "Provides"),
]

# ---------------------------------------------------------------- parsing
def stanzas(path):
    """RFC822-ish records separated by blank lines (dpkg status format)."""
    if not os.path.exists(path):
        return []
    with open(path, encoding='utf-8', errors='replace') as f:
        blob = f.read()
    return [s for s in blob.split('\n\n') if s.strip()]

def fields(text):
    """One stanza -> {field: value}, folding continuation lines."""
    out, key = {}, None
    for line in text.split('\n'):
        if not line.strip():
            continue
        if line[0] in ' \t':
            if key:
                out[key] += ' ' + line.strip()
        elif ':' in line:
            k, _, v = line.partition(':')
            key = k.strip()
            out[key] = v.strip()
        else:
            key = None
    return out

def installed(f):
    """Status is '<want> <error> <state>'. Compare the state word exactly:
    a substring test for 'installed' also matches 'not-installed'."""
    st = (f.get('Status') or '').split()
    return len(st) == 3 and st[2] == 'installed'

def strip_arch(name):
    return name.split(':')[0]

def load_status(tree):
    pkgs = {}
    for s in stanzas(os.path.join(tree, 'var/lib/dpkg/status')):
        f = fields(s)
        n = f.get('Package')
        if not n or not installed(f):
            continue
        pkgs[strip_arch(n)] = f
    return pkgs

def load_auto(tree):
    """Packages apt marked Auto-Installed. The checker uses this to pick the
    roots of a dependency chain -- without it, C1 cannot explain WHY a base
    package got upgraded."""
    p = os.path.join(tree, 'var/lib/apt/extended_states')
    auto = set()
    if not os.path.exists(p):
        warn("no extended_states under %s; auto flags default to false" % tree)
        return auto
    for s in stanzas(p):
        f = fields(s)
        n = f.get('Package')
        if n and (f.get('Auto-Installed') or '0').strip() == '1':
            auto.add(strip_arch(n))
    return auto

def sha256(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for chunk in iter(lambda: f.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()

# ---------------------------------------------------------------- load
tree        = E['M_TREE']
parent      = E.get('M_PARENT') or None
parent_tree = E.get('M_PARENT_TREE') or None
out_path    = E['M_OUT']

own = load_status(tree)
if not own:
    sys.stderr.write("no installed packages found in %s\n" % tree)
    sys.exit(2)

parent_pkgs = load_status(parent_tree) if parent_tree else {}
if parent_tree and not parent_pkgs:
    sys.stderr.write("no installed packages found in parent %s\n" % parent_tree)
    sys.exit(2)

auto = load_auto(tree)

# ------------------------------------------------- carry over hand-written
# Week 3 fills requires/conflicts/provides in by hand. A rebuild must not
# throw that away, so anything already present and not overridden on the
# command line survives.
prev = {}
if os.path.exists(out_path):
    try:
        with open(out_path, encoding='utf-8') as f:
            prev = json.load(f)
    except Exception as exc:
        warn("could not read existing %s (%s); starting fresh" % (out_path, exc))
        prev = {}

version = E.get('M_VERSION') or prev.get('version') or ''
if not version:
    version = '0'
    warn("no --version given for '%s'; defaulting to \"0\". ARCHITECTURE "
         "section 5 requires explicit module versions." % E['M_NAME'])

requested = [x for x in (E.get('M_REQUESTED') or '').split() if x]
if not requested:
    requested = list(prev.get('requested') or [])

# ------------------------------------------------- the module's contribution
# Only what differs from the parent. Everything else is inherited and already
# described by the parent's own manifest -- storing it again would duplicate
# base's 113 packages into every sibling.
packages = {}
for name in sorted(own):
    f = own[name]
    pv = parent_pkgs.get(name)
    if pv is None:
        origin = 'added'
    elif pv.get('Version') != f.get('Version'):
        origin = 'upgraded'          # version differs from parent -- class 6
    else:
        continue                     # inherited unchanged

    entry = {
        'version': f.get('Version'),
        'arch':    f.get('Architecture'),
        'origin':  origin,
        'auto':    name in auto,
    }
    for key, field in RELATIONS:
        entry[key] = f.get(field)    # raw dpkg relation string, or None
    packages[name] = entry

removed = sorted(n for n in parent_pkgs if n not in own)

# ---------------------------------------------------------------- artifact
sqsh = E['M_SQSH']
if os.path.exists(sqsh):
    artifact = {
        'file':   os.path.basename(sqsh),
        'bytes':  os.path.getsize(sqsh),
        'sha256': sha256(sqsh),
    }
else:
    artifact = None

# ---------------------------------------------------------------- assemble
doc = {
    'schema':   SCHEMA,
    'module':   E['M_NAME'],
    'version':  version,
    'parent':   parent,
    'snapshot': E['M_SNAPSHOT'],
    'suite':    E['M_SUITE'],
    'arch':     E['M_ARCH'],
    'built':    E['M_BUILT'],

    # Module-level dependency layer, ARCHITECTURE section 5. Package
    # relations cannot express cross-module requirements, because apt only
    # ever sees one module's build. Filled in by hand in week 3; note these
    # are a different namespace from the per-package fields of the same name.
    'requires':  list(prev.get('requires')  or []),
    'conflicts': list(prev.get('conflicts') or []),
    'provides':  list(prev.get('provides')  or []),

    'requested': requested,
    'removed':   removed,
    'artifact':  artifact,
    'packages':  packages,
}

# Atomic replace, so an interrupted run never leaves a truncated manifest.
d = os.path.dirname(out_path) or '.'
fd, tmp = tempfile.mkstemp(dir=d, prefix='.module-', suffix='.json')
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as f:
        json.dump(doc, f, indent=2, ensure_ascii=False)
        f.write('\n')
    os.chmod(tmp, 0o644)             # readable without root: 05_check.sh
    os.replace(tmp, out_path)
except Exception:
    if os.path.exists(tmp):
        os.unlink(tmp)
    raise

added    = sum(1 for e in packages.values() if e['origin'] == 'added')
upgraded = sum(1 for e in packages.values() if e['origin'] == 'upgraded')
print("  packages : %d contributed (%d added, %d upgraded)"
      % (len(packages), added, upgraded))
print("  removed  : %d" % len(removed))
print("  requested: %s" % (' '.join(requested) if requested else '<none>'))
if artifact:
    print("  artifact : %s (%d bytes)" % (artifact['file'], artifact['bytes']))
    print("  sha256   : %s" % artifact['sha256'])
print("  written  : %s" % out_path)

# ------------------------------------------------- file ownership sidecar
# Conflict class 4 needs to know which package owns which PATH. That comes
# from dpkg's own /var/lib/dpkg/info/<pkg>.list files, which for a delta
# contain exactly the packages the delta installed -- overlayfs leaves the
# parent's list files in the lower layer. Written as a separate, compressed
# sidecar because it is 10-20x the size of module.json and only the
# file-collision check ever reads it.
#
# Directories are DROPPED. dpkg lists them in every owning package's .list,
# so co-ownership of /usr/bin is normal and would swamp the signal; on a
# merged-/usr system /bin, /lib and /sbin are symlinks to directories and
# must go too, which is why the test follows symlinks.
import glob as _glob
import subprocess as _sp

def is_dir(rel):
    for root in (tree, parent_tree):
        if root and os.path.isdir(os.path.join(root, rel.lstrip('/'))):
            return True
    return False

files, dirs_skipped = {}, 0
for lst in sorted(_glob.glob(os.path.join(tree, 'var/lib/dpkg/info/*.list'))):
    pkg = os.path.basename(lst)[:-5].split(':')[0]
    try:
        with open(lst, encoding='utf-8', errors='replace') as f:
            paths = f.read().split('\n')
    except OSError as exc:
        warn("cannot read %s (%s)" % (lst, exc)); continue
    for path in paths:
        if not path.startswith('/'):
            continue
        if is_dir(path):
            dirs_skipped += 1; continue
        files[path] = pkg

# dpkg diversions legitimise one package overriding another's file.
diversions = []
dpath = os.path.join(tree, 'var/lib/dpkg/diversions')
if os.path.exists(dpath):
    try:
        with open(dpath, encoding='utf-8', errors='replace') as f:
            lines = [l for l in f.read().split('\n') if l]
        for i in range(0, len(lines) - 2, 3):
            diversions.append({'path': lines[i], 'to': lines[i+1],
                               'by': None if lines[i+2] == ':' else lines[i+2]})
    except OSError as exc:
        warn("cannot read %s (%s)" % (dpath, exc))

sidecar = {'schema': SCHEMA, 'module': E['M_NAME'],
           'files': dict(sorted(files.items())), 'diversions': diversions}
side_path = out_path[:-5] + '.files.json.zst'
blob = json.dumps(sidecar, indent=None, sort_keys=False).encode('utf-8')
try:
    _sp.run(['zstd', '-q', '-f', '-19', '-o', side_path], input=blob, check=True)
    os.chmod(side_path, 0o644)
    print("  files    : %d path(s), %d dir(s) skipped, %d diversion(s) -> %s"
          % (len(files), dirs_skipped, len(diversions), os.path.basename(side_path)))
except Exception as exc:
    warn("could not write %s (%s); class-4 checking will skip this module"
         % (side_path, exc))
PY

log "metadata written -> ${OUT}"
