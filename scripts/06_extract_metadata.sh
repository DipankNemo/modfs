#!/usr/bin/env bash
#
# Extract module metadata into a JSON manifest beside the .sqsh artefact.
#
#   sudo ./scripts/06_extract_metadata.sh <name> [--parent NAME|none]
#                                                [--version V]
#                                                [--requested "pkg [pkg...]"]
#                                                [--new-build]
#                                                [--adopt-generation]
#                                                [--check]
#
#   --new-build          label a fresh delta with the current generation
#   --adopt-generation   adopt a legacy manifest that has no generation
#   --check              re-derive and compare with the manifest; write nothing
#
# Why: with the manifest beside it, <name>.sqsh + <name>.json is everything a
# consistency check needs, and the build tree is disposable scratch.
#
# What lands in the file:
#   - identity  : module, version, parent, snapshot, suite, arch, build time
#   - requires, conflicts, provides : module-dependency layer (ARCHITECTURE
#                 section 5), from specs/modules.yaml
#   - requested : the packages actually asked for on the build command line
#   - artifact  : .sqsh name, size and sha256 (reproducibility evidence)
#   - binding   : what this manifest was derived from, and a digest over the
#                 fields the checks depend on (see "Binding" below)
#   - packages  : only this module's contribution -- packages whose
#                 (name, version) differ from the parent's. Full dpkg
#                 relations for each: Depends, Pre-Depends, Conflicts,
#                 Breaks, Replaces, Provides.
#   - removed   : packages the parent had and this module does not
#   - accounts, units, uid_range, identity_audit : identity data for class 7
#   - generation : the archive view and exact base artefact built against
#
#   Consumers rebuild the merged view as:
#       effective(m) = parent.packages | m.packages  -  m.removed
#
# Re-running is safe: hand-written requires/conflicts/provides/version, and a
# previously recorded requested list, are carried over rather than wiped.
#
# Binding the manifest to the artefact:
#
#   1. Derivation. The manifest is derived from the artefact, mounted
#      read-only, not from the build tree (which still holds paths that
#      SQUASH_EXCLUDES drops), so the content fields and the recorded digest
#      come from the same bytes. `binding.source` records which was used.
#
#   2. Omission. `binding.fields_sha256` is a canonical digest over exactly
#      the fields the checks read, so a field that is edited or removed does
#      not pass unnoticed. `binding.sidecar_sha256` does the same for the
#      class-4 sidecar.
#
#   This is integrity, not authenticity: the digest lives in the document it
#   protects, so anyone who can rewrite the manifest can rewrite the digest
#   (as with `artifact.sha256`). It catches drift, partial refreshes and
#   omission. Authenticity needs a key outside the artefact set and is out of
#   scope.
#
# Output: $MOD_DIR/<name>.json and $MOD_DIR/<name>.files.json.zst (class 4)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"
need_root

NAME=""
PARENT="base"
MOD_VERSION=""
REQUESTED=""
CHECK_ONLY=0
NEW_BUILD=0
ADOPT_GENERATION=0

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
        --new-build) NEW_BUILD=1; shift ;;
        --adopt-generation) ADOPT_GENERATION=1; shift ;;
        --check)
            # Re-derive from the artefact and compare against the manifest on
            # disk instead of writing. Used by 12_verify_binding.sh.
            CHECK_ONLY=1; shift ;;
        -*)
            die "unknown option: $1" ;;
        *)
            [ -z "$NAME" ] || die "unexpected argument: $1"
            NAME="$1"; shift ;;
    esac
done

[ -n "$NAME" ] || die "usage: $0 <name> [--parent NAME|none] [--version V] [--requested \"pkg ...\"]"
# Module names reach paths and mount options, so validate them here.
require_ident "$NAME" "module name"
case "$PARENT" in ""|none|NONE|None) ;; *) require_ident "$PARENT" "parent module name" ;; esac

# Base keeps its full rootfs in <name>.dir; deltas keep only the overlay
# upperdir in <name>.upper. Either one carries a complete dpkg status file:
# apt rewrites status wholesale, so a delta's copy lands in the upperdir.
module_tree() {          # module_tree <name> -> path on stdout, empty if none
    local n="$1"
    if   [ -d "${MOD_DIR}/${n}.upper" ]; then echo "${MOD_DIR}/${n}.upper"
    elif [ -d "${MOD_DIR}/${n}.dir"   ]; then echo "${MOD_DIR}/${n}.dir"
    fi
}

# The artefact is the source of truth; the build tree is the fallback.
# Mounting costs milliseconds and this runs once per build.
MOUNT_ROOT="${BUILD_DIR}/metadata-${NAME}.$$"
# Sets ARTIFACT_MNT rather than printing it: `$(mount_artifact ...)` would
# mount in a subshell whose track_mount push is lost, so the EXIT trap would
# never unmount it.
ARTIFACT_MNT=""
mount_artifact() {       # mount_artifact <name>  -> sets ARTIFACT_MNT ('' if none)
    local n sq mp
    n="$1"; sq="${MOD_DIR}/${n}.sqsh"; mp="${MOUNT_ROOT}/${n}"
    ARTIFACT_MNT=""
    [ -f "$sq" ] || return 0
    mkdir -p "$mp" || return 0
    if mount -o loop,ro "$sq" "$mp" 2>/dev/null; then
        track_mount "$mp"; ARTIFACT_MNT="$mp"
    fi
}

SOURCE=artifact
mount_artifact "$NAME"; TREE="$ARTIFACT_MNT"
if [ -z "$TREE" ]; then
    SOURCE=tree
    TREE="$(module_tree "$NAME")"
    [ -n "$TREE" ] || die "no artefact ${MOD_DIR}/${NAME}.sqsh and no build tree in ${MOD_DIR}"
    warn "deriving from the BUILD TREE ${TREE}, not the artefact;"
    warn "  binding.source will say 'tree' and 12_verify_binding.sh will not pass"
fi
[ -f "${TREE}/var/lib/dpkg/status" ] || die "no dpkg status in ${TREE}"

PARENT_TREE=""
case "$PARENT" in
    ""|none|NONE|None)
        PARENT="" ;;
    *)
        # The parent is read from its artefact too: `removed` and every
        # package's origin are computed against it.
        mount_artifact "$PARENT"; PARENT_TREE="$ARTIFACT_MNT"
        if [ -z "$PARENT_TREE" ]; then
            SOURCE=tree
            PARENT_TREE="$(module_tree "$PARENT")"
            [ -n "$PARENT_TREE" ] || die "no artefact or build tree for parent '${PARENT}'"
        fi
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
export M_CHECK_ONLY="$CHECK_ONLY"
export M_NEW_BUILD="$NEW_BUILD"
export M_ADOPT_GENERATION="$ADOPT_GENERATION"
export M_BUILT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# The assigned window, so the manifest records the policy the build ran under.
# base has none: it is the baseline, not a partitioned sibling.
if [ -n "$PARENT" ]; then
    M_UID_RANGE="$(uid_range_for "$NAME" 2>/dev/null || true)"
else
    M_UID_RANGE=""
fi
export M_UID_RANGE
export M_SOURCE="$SOURCE"
export M_SQUASH_EXCLUDES="$SQUASH_EXCLUDES"
export M_SPEC_DIR="$SPEC_DIR"

# --check exits 1 on a mismatch, which is a verdict and not a crash, so the
# status is captured rather than turned into die().
RC=0
python3 - <<'PY' || RC=$?
import hashlib, json, os, sys, tempfile

E = os.environ
SCHEMA = 1

def warn(msg):
    sys.stderr.write("\033[1;33m[warn]\033[0m %s\n" % msg)

# JSON key -> dpkg control field. All six relation types are recorded; the
# checks in 05 read every one of them.
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
# A rebuild must not throw away hand-written fields, so anything already
# present and not overridden survives.
prev = {}
if os.path.exists(out_path):
    try:
        with open(out_path, encoding='utf-8') as f:
            prev = json.load(f)
    except Exception as exc:
        warn("could not read existing %s (%s); starting fresh" % (out_path, exc))
        prev = {}

# Module-level relations come from the hand-written catalogue when it
# declares them, and are otherwise carried over from a previous manifest so a
# hand edit survives a rebuild. The catalogue is the authority when both exist.
cat_requires = cat_conflicts = cat_provides = None
cat_version = None
spec_path = os.path.join(E.get('M_SPEC_DIR') or '', 'modules.yaml')
if os.path.exists(spec_path):
    try:
        import yaml as _yaml
        for entry in ((_yaml.safe_load(open(spec_path, encoding='utf-8')) or {})
                      .get('modules') or []):
            if entry.get('name') == E['M_NAME']:
                cat_requires  = entry.get('requires')
                cat_conflicts = entry.get('conflicts')
                cat_provides  = entry.get('provides')
                if entry.get('version') is not None:
                    cat_version = str(entry['version'])
                break
    except Exception as exc:
        warn("could not read %s (%s); module relations not refreshed" % (spec_path, exc))

version = E.get('M_VERSION') or cat_version or prev.get('version') or ''
if not version:
    version = '0'
    warn("no --version given for '%s'; defaulting to \"0\". ARCHITECTURE "
         "section 5 requires explicit module versions." % E['M_NAME'])

requested = [x for x in (E.get('M_REQUESTED') or '').split() if x]
if not requested:
    requested = list(prev.get('requested') or [])

# ------------------------------------------------- the module's contribution
# Only what differs from the parent; everything else is inherited and
# described by the parent's own manifest.
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

sys.path.insert(0, os.path.join(E['MODFS_SRC'], 'scripts'))
from account_schema import FIELDS
from generation import extraction_generation
# Snapshot provenance lives in the shipped sources.list. Never label existing
# bytes using only the caller's environment during a metadata refresh.
import re
source_path = os.path.join(tree, 'etc/apt/sources.list')
if not os.path.exists(source_path) and parent_tree:
    source_path = os.path.join(parent_tree, 'etc/apt/sources.list')
sources = open(source_path, encoding='utf-8').read()
pins = set(re.findall(r'snapshot\.ubuntu\.com/ubuntu/(\d{8}T\d{6}Z)', sources))
if pins != {E['M_SNAPSHOT']}:
    raise ValueError('artefact snapshot %r differs from requested pin %s' % (pins, E['M_SNAPSHOT']))


# Check before writing any sidecar or manifest, so refusal is non-mutating.
base_path = os.path.join(E['MOD_DIR'], (parent or E['M_NAME']) + '.sqsh')
resolved_generation = extraction_generation(
    dict(snapshot=E['M_SNAPSHOT'], suite=E['M_SUITE'], arch=E['M_ARCH'], parent=parent),
    prev, sha256(base_path), new_build=E.get('M_NEW_BUILD') == '1',
    adopt=E.get('M_ADOPT_GENERATION') == '1')

# ------------------------------------------------- accounts and unit identity
# Conflict class 7. The account databases are rewritten wholesale by
# maintainer scripts, so they are not package-owned and never appear in the
# class-4 sidecar, and two modules can give one number to different names.
#
# Record additions, changed numeric identities and explicit removals. A delta
# without an account file inherits its parent; absence is not deletion.
# Password hashes are not stored: checking that a shadow record exists needs
# only the name.
def colon_table(tree, rel, key_at, want):
    out = {}
    # Field counts come from account_schema.FIELDS, shared with the merger
    # and the verifier.
    expected = FIELDS[rel]
    path = os.path.join(tree, rel)
    if not os.path.exists(path):
        return out
    try:
        fh = open(path, encoding='utf-8', errors='replace')
    except OSError as exc:
        # /etc/shadow is 0640: unreadable without root. Degrade rather than
        # abort -- a missing shadow record is a check the class-7 verifier can
        # report as unknown, not a reason to lose the whole manifest.
        warn("cannot read %s (%s); account records from it are omitted" % (path, exc))
        return out
    with fh as f:
        for line in f:
            line = line.rstrip('\n')
            if not line or line.startswith('#'):
                continue
            parts = line.split(':')
            if len(parts) != expected or not parts[key_at]:
                raise ValueError('%s: malformed %s record %r' %
                                 (path, rel, line[:40]))
            if parts[key_at] in out:
                raise ValueError('%s: duplicate %s record %r' %
                                 (path, rel, parts[key_at]))
            out[parts[key_at]] = {name: parts[i] for i, name in want}
    return out

def account_view(tree):
    return (colon_table(tree, 'etc/passwd', 0, [(2, 'uid'), (3, 'gid')]),
            colon_table(tree, 'etc/group', 0, [(2, 'gid'), (3, 'members')]),
            set(colon_table(tree, 'etc/shadow', 0, []).keys()),
            set(colon_table(tree, 'etc/gshadow', 0, []).keys()))

own_u, own_g, own_sh, own_gsh = account_view(tree)
par_u, par_g, par_sh, par_gsh = account_view(parent_tree) if parent_tree else ({}, {}, set(), set())

users = {n: {'uid': v['uid'], 'gid': v['gid']}
         for n, v in own_u.items() if n not in par_u or v != par_u[n]}
groups = {n: {'gid': v['gid'],
              'members': [x for x in v['members'].split(',') if x]}
          for n, v in own_g.items() if n not in par_g or v['gid'] != par_g[n]['gid']}
# Numeric file owners. Class 7 compares account records, but ownership on
# disk is a number: a module that allocates no account can still ship a file
# owned by uid 2500 (a tarball or pip install preserving ownership). Recording
# the numbers lets class 7 compare what is on disk, not only what is declared.
file_ids = {'uids': set(), 'gids': set()}
for _dp, _dn, _fn in os.walk(tree):
    for _n in _dn + _fn:
        try:
            _st = os.lstat(os.path.join(_dp, _n))
        except OSError:
            continue
        file_ids['uids'].add(_st.st_uid); file_ids['gids'].add(_st.st_gid)

accounts = {'users': dict(sorted(users.items())),
            'groups': dict(sorted(groups.items())),
            'shadow': sorted(own_sh - par_sh),
            'gshadow': sorted(own_gsh - par_gsh),
            'file_uids': sorted(file_ids['uids']),
            'file_gids': sorted(file_ids['gids'])}

# Only an explicit replacement database can remove inherited identities.
for kind, rel, own, inherited in (('users', 'etc/passwd', own_u, par_u),
                               ('groups', 'etc/group', own_g, par_g)):
    if os.path.lexists(os.path.join(tree, rel)):
        removed = sorted(set(inherited) - set(own))
        if removed:
            accounts['removed_' + kind] = removed

# ---- post-build identity audit ------------------------------------------
# Prevention is not proof. Every account the module created must be either a
# Debian-global static allocation (base-passwd territory, uid < 100, e.g.
# www-data=33) or inside this module's assigned window. Anything else escaped
# the policy -- typically a maintainer script with a hardcoded id, or a tool
# that consults neither adduser.conf nor login.defs -- and is reported rather
# than quietly accepted.
DEBIAN_STATIC_MAX = 99          # Debian Policy 9.2.2: 0-99 globally allocated
NOBODY = 65534

uid_range = None
rr = os.environ.get('M_UID_RANGE') or ''
if rr:
    try:
        lo, hi = (int(x) for x in rr.split())
        uid_range = {'start': lo, 'end': hi}
    except ValueError:
        warn("malformed M_UID_RANGE %r; audit will treat every id as out of range" % rr)

DEBIAN_DYNAMIC_MAX = 999        # Debian Policy 9.2.2: 100-999 dynamic system

def classify(num):
    try:
        n = int(num)
    except (TypeError, ValueError):
        return 'malformed'
    if n <= DEBIAN_STATIC_MAX or n == NOBODY:
        return 'static-reserved'
    if uid_range and uid_range['start'] <= n <= uid_range['end']:
        return 'in-range'
    # base has no window: it is the baseline every module inherits, built
    # before partitioning applies, so its accounts legitimately sit in
    # Debian's 100-999 dynamic system range.
    if uid_range is None and n <= DEBIAN_DYNAMIC_MAX:
        return 'base-dynamic'
    return 'out-of-range'

audit = {'static-reserved': [], 'in-range': [], 'base-dynamic': [],
         'out-of-range': [], 'malformed': []}
for n, rec in users.items():
    audit[classify(rec['uid'])].append('user %s=%s' % (n, rec['uid']))
for n, rec in groups.items():
    audit[classify(rec['gid'])].append('group %s=%s' % (n, rec['gid']))
identity_audit = {k: sorted(v) for k, v in audit.items()}

# systemd units name identities that must resolve in the composed account
# view. Collected over-inclusively (any User=/Group=/SupplementaryGroups=
# line, not only those under [Service]) because a false positive here costs a
# harmless extra resolution check while a miss costs a boot failure.
units = {}
for unit_dir in ('lib/systemd/system', 'usr/lib/systemd/system', 'etc/systemd/system'):
    d = os.path.join(tree, unit_dir)
    if not os.path.isdir(d):
        continue
    for entry in sorted(os.listdir(d)):
        if not entry.endswith(('.service', '.socket', '.mount', '.timer')):
            continue
        fp = os.path.join(d, entry)
        if not os.path.isfile(fp) or os.path.islink(fp):
            continue
        rec = {'user': None, 'group': None, 'supplementary': []}
        try:
            with open(fp, encoding='utf-8', errors='replace') as f:
                for line in f:
                    line = line.strip()
                    if line.startswith('User='):
                        rec['user'] = line[5:].strip() or None
                    elif line.startswith('Group='):
                        rec['group'] = line[6:].strip() or None
                    elif line.startswith('SupplementaryGroups='):
                        rec['supplementary'] += line[20:].split()
        except OSError:
            continue
        if rec['user'] or rec['group'] or rec['supplementary']:
            units[entry] = rec

# ---------------------------------------------------------------- assemble
# ------------------------------------------------- file ownership sidecar
# Conflict class 4 needs to know which package owns which path. That comes
# from dpkg's /var/lib/dpkg/info/<pkg>.list files, which for a delta cover
# exactly the packages the delta installed (the parent's list files stay in
# the lower layer). It is a separate, compressed sidecar because it is 10-20x
# the size of the manifest and only the file-collision check reads it.
import glob as _glob
import subprocess as _sp

# Directories are dropped because dpkg names them in every owning package's
# .list, so co-ownership of /usr/bin is normal and would swamp the signal; on a
# merged-/usr system /bin, /lib and /sbin are symlinks to directories and must
# go too, which is why the test follows symlinks.
def is_dir(rel):
    for root in (tree, parent_tree):
        if root and os.path.isdir(os.path.join(root, rel.lstrip('/'))):
            return True
    return False

# Paths in SQUASH_EXCLUDES are not shipped. Packages still list them
# (base-files owns /dev, /tmp, /run ...; apt owns the archive caches), and
# since they are absent from the artefact, is_dir() would call them files.
#
# The test is the exclude list itself, not "absent from the artefact": on
# merged-/usr jammy a delta's /lib/systemd/system/<unit>.service exists only
# in the merged view (the /lib -> usr/lib symlink lives in base), and such
# real files are exactly what class 4 must see.
EXCLUDED = tuple('/' + x for x in (E.get('M_SQUASH_EXCLUDES') or '').split() if x)
def excluded(rel):
    return any(rel == x or rel.startswith(x + '/') for x in EXCLUDED)

files, dirs_skipped, not_shipped = {}, 0, 0
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
        if excluded(path):
            not_shipped += 1; continue
        if is_dir(path):
            dirs_skipped += 1; continue
        files[path] = pkg

# dpkg diversions legitimise one package overriding another's file.
diversions = []
dpath = os.path.join(tree, 'var/lib/dpkg/diversions')
if os.path.exists(dpath):
    try:
        with open(dpath, encoding='utf-8', errors='replace') as f:
            lines = f.read().splitlines()
        if len(lines) % 3 or any(not line for line in lines):
            raise ValueError('%s: malformed diversions (expected three nonempty lines per record)' % dpath)
        for i in range(0, len(lines), 3):
            diversions.append({'path': lines[i], 'to': lines[i+1],
                               'by': None if lines[i+2] == ':' else lines[i+2]})
    except OSError as exc:
        warn("cannot read %s (%s)" % (dpath, exc))

sidecar = {'schema': SCHEMA, 'module': E['M_NAME'],
           'files': dict(sorted(files.items())), 'diversions': diversions}
side_path = out_path[:-5] + '.files.json.zst'
blob = json.dumps(sidecar, indent=None, sort_keys=False).encode('utf-8')
# Digest of the uncompressed sidecar, so it does not depend on the zstd level
# or version. This is what binds class 4's input to the manifest that names it.
sidecar_sha256 = hashlib.sha256(blob).hexdigest()
if E.get('M_CHECK_ONLY') == '1':
    # The blob and its digest are already computed; writing is the only part
    # that is skipped, so --check exercises exactly the same derivation.
    print("  files    : %d path(s), %d dir(s), %d not shipped, %d diversion(s)"
          " [not written]"
          % (len(files), dirs_skipped, not_shipped, len(diversions)))
else:
    try:
        _sp.run(['zstd', '-q', '-f', '-19', '-o', side_path], input=blob, check=True)
        os.chmod(side_path, 0o644)
        print("  files    : %d path(s), %d dir(s), %d not shipped, %d diversion(s)"
              " -> %s" % (len(files), dirs_skipped, not_shipped, len(diversions),
                          os.path.basename(side_path)))
    except Exception as exc:
        warn("could not write %s (%s); class-4 checking will skip this module"
             % (side_path, exc))
# ------------------------------------------------- manifest binding
# BIND_FIELDS (manifest_binding.py) lists the keys the checks read. It is
# stored in the manifest too, so a verifier can reproduce the digest without
# this version of the code. Class 4 reads the sidecar (bound separately by its
# own digest) plus `packages`; class 7 reads `accounts` and `units`; PRE reads
# parent/snapshot/suite/arch/version; class 6 reads `packages` and `removed`;
# the module-dependency layer reads requires/conflicts/provides.
sys.path.insert(0, os.path.join(E['MODFS_SRC'], 'scripts'))
from manifest_binding import BIND_FIELDS, bind_digest

doc = {
    'schema':   SCHEMA,
    'module':   E['M_NAME'],
    'version':  version,
    'parent':   parent,
    'snapshot': E['M_SNAPSHOT'],
    'suite':    E['M_SUITE'],
    'arch':     E['M_ARCH'],
    'built':    E['M_BUILT'],

    # Module-level dependency layer (ARCHITECTURE section 5), from the
    # catalogue or carried over. Package relations cannot express
    # cross-module requirements, because apt only ever sees one module's
    # build. These are a different namespace from the per-package fields of
    # the same name.
    'requires':  list(cat_requires  if cat_requires  is not None else (prev.get('requires')  or [])),
    'conflicts': list(cat_conflicts if cat_conflicts is not None else (prev.get('conflicts') or [])),
    'provides':  list(cat_provides  if cat_provides  is not None else (prev.get('provides')  or [])),

    'requested': requested,
    'removed':   removed,
    'uid_range': uid_range,
    'accounts':  accounts,
    'identity_audit': identity_audit,
    'units':     units,
    'artifact':  artifact,
    'packages':  packages,
}

doc['generation'] = resolved_generation

# Computed over the finished doc, then inserted, so the digest covers exactly
# what a reader sees. `binding` itself is never one of BIND_FIELDS -- a digest
# cannot cover the field that holds it.
doc['binding'] = {
    'schema':          SCHEMA,
    'source':          E.get('M_SOURCE') or 'tree',
    'artifact_sha256': (artifact or {}).get('sha256'),
    'sidecar_sha256':  sidecar_sha256,
    'fields':          list(BIND_FIELDS),
    'fields_sha256':   bind_digest(doc, BIND_FIELDS),
}

if E.get('M_CHECK_ONLY') == '1':
    # Compare, do not write. Only the bound fields are compared: `built` is a
    # wall-clock stamp outside the binding, so a manifest does not become
    # "wrong" merely by being older than a re-derivation.
    old = prev or {}
    ob = (old.get('binding') or {})
    nb = doc['binding']
    problems = []
    if not ob.get('fields_sha256'):
        problems.append("manifest carries no binding")
    elif ob.get('fields') != nb['fields']:
        problems.append("binding covers different fields: %s vs %s"
                        % (ob.get('fields'), nb['fields']))
    else:
        # Two questions. First, recompute the digest from the manifest as it
        # is on disk: comparing only the stored digest would pass fields that
        # were edited while the digest was left alone. Then compare that with
        # the re-derivation.
        old_actual = bind_digest(old, ob['fields'])
        if old_actual != ob['fields_sha256']:
            differing = [k for k in ob['fields'] if old.get(k) != doc.get(k)]
            problems.append("manifest fields were edited after extraction"
                            " (digest says %s, content hashes to %s); differs"
                            " from the artefact in: %s"
                            % (ob['fields_sha256'][:16], old_actual[:16],
                               ', '.join(differing) or '<none: digest only>'))
        elif old_actual != nb['fields_sha256']:
            differing = [k for k in nb['fields'] if old.get(k) != doc.get(k)]
            problems.append("re-derivation differs from the manifest in: %s"
                            % (', '.join(differing) or '<canonicalisation only>'))
    if ob.get('sidecar_sha256') != nb['sidecar_sha256']:
        problems.append("class-4 sidecar differs from a re-derivation")
    if ob.get('artifact_sha256') != nb['artifact_sha256']:
        problems.append("binding names a different artefact digest")
    if nb['source'] != 'artifact':
        problems.append("could not read the artefact; derived from %r" % nb['source'])
    for x in problems:
        print("  MISMATCH %s: %s" % (E['M_NAME'], x))
    print("  %s: %s" % (E['M_NAME'], "re-derived from the artefact and identical"
                        if not problems else "DOES NOT MATCH ITS ARTEFACT"))
    sys.exit(1 if problems else 0)

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
print("  accounts : %d user(s), %d group(s); %d unit(s) name an identity"
      % (len(users), len(groups), len(units)))
if uid_range:
    print("  uid range: %d-%d" % (uid_range['start'], uid_range['end']))
for kind in ('static-reserved', 'in-range', 'base-dynamic'):
    if identity_audit[kind]:
        print("  audit    : %-15s %s" % (kind, ', '.join(identity_audit[kind])))
for kind in ('out-of-range', 'malformed'):
    if identity_audit[kind]:
        warn("IDENTITY AUDIT %s: %s -- escaped the assigned window"
             % (kind, ', '.join(identity_audit[kind])))
if artifact:
    print("  artifact : %s (%d bytes)" % (artifact['file'], artifact['bytes']))
    print("  sha256   : %s" % artifact['sha256'])
print("  source   : %s" % doc['binding']['source'])
print("  binding  : fields %s  sidecar %s"
      % (doc['binding']['fields_sha256'][:16], doc['binding']['sidecar_sha256'][:16]))
print("  written  : %s" % out_path)

PY

unmount_all
rmdir "${MOUNT_ROOT}"/* "${MOUNT_ROOT}" 2>/dev/null || true

if [ "$CHECK_ONLY" = 1 ]; then
    exit "$RC"
fi
[ "$RC" -eq 0 ] || die "metadata extraction failed"
log "metadata written -> ${OUT}"
