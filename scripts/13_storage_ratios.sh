#!/usr/bin/env bash
#
# Cohort storage ratios, computed from the artefacts rather than by hand.
#
#   ./scripts/13_storage_ratios.sh                 # table to stdout
#   ./scripts/13_storage_ratios.sh --csv out.csv   # also write a CSV
#
# Needs no root: it reads artefact sizes only.
#
# The ratio:
#
#     stored      = B + sum(d_i)              one base, N deltas
#     monolithic  = N*B + sum(d_i)            one whole image per use case
#     ratio       = monolithic / stored
#
# It tends to N as deltas shrink and to 1 as they grow. The monolithic size is
# modelled as B + d and checked against the real monolithic builds that
# `02_build_delta.sh --compare` produces: squashfs compresses one whole tree
# slightly better than a base and a delta separately, so the model slightly
# overstates the saving. The measured error is printed, not assumed.
#
# The cohort split is a judgement, declared below rather than derived from
# size, so it cannot drift silently as modules are added.

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "${HERE}/config.sh"
source "${HERE}/scripts/lib.sh"

CSV=""
while [ $# -gt 0 ]; do
    case "$1" in
        --csv) [ $# -ge 2 ] || die "--csv needs a value"; CSV="$2"; shift 2 ;;
        *) die "unknown option: $1" ;;
    esac
done

python3 - "$MOD_DIR" "$CSV" <<'PY'
import os, sys

mod_dir, csv_out = sys.argv[1], sys.argv[2]

# Declared, not inferred. A module is "large realistic" because it is a real
# workload someone would deploy, not because it happens to exceed a threshold.
LARGE = {'gcc', 'java', 'rust', 'llvm', 'postgres', 'mysql', 'docker',
         'nvidia-driver-535', 'cuda-runtime'}
# The GPU modules are the largest real artefacts in the catalogue; leaving
# them out of this cohort would flatter its ratio.

def size(name):
    return os.path.getsize(os.path.join(mod_dir, name + '.sqsh'))

names = sorted({f[:-5] for f in os.listdir(mod_dir) if f.endswith('.json')}
               - {'base'})
missing = [n for n in names
           if not os.path.exists(os.path.join(mod_dir, n + '.sqsh'))]
if missing:
    sys.stderr.write('manifest without artefact: %s\n' % ', '.join(missing))
    sys.exit(2)
B = size('base')

unknown = LARGE - set(names)
if unknown:
    sys.stderr.write('declared large but not built: %s\n'
                     % ', '.join(sorted(unknown)))

# The symmetric case: a large module that is built but not declared would
# fall silently into "small adversarial" (e.g. a driver renamed in another
# release). Size does not decide the split, but an undeclared module at least
# as large as the smallest declared-large one is a decision nobody has made,
# so refuse rather than average it into the wrong cohort.
built_large = [n for n in names if n in LARGE]
if built_large:
    floor = min(size(n) for n in built_large)
    undeclared = sorted((n for n in names
                         if n not in LARGE and size(n) >= floor),
                        key=size, reverse=True)
    if undeclared:
        sys.stderr.write(
            'undeclared module at or above the large-cohort floor (%.1f MB): %s\n'
            'Add it to LARGE, or state in ARCHITECTURE section 7 why it is small.\n'
            % (floor / 1e6,
               ', '.join('%s (%.1f MB)' % (n, size(n) / 1e6) for n in undeclared)))
        sys.exit(2)

rows = []
for label, cohort in (('small adversarial', [n for n in names if n not in LARGE]),
                      ('large realistic',   [n for n in names if n in LARGE]),
                      ('whole catalogue',   names)):
    d = sum(size(n) for n in cohort)
    N = len(cohort)
    stored, model = B + d, N * B + d
    rows.append((label, N, stored, model, (model / stored) if stored else 0,
                 (d / N / 1000000.0) if N else 0))

# Decimal MB (10^6), the unit of every published figure. mksquashfs and
# lib.sh's human() print binary MiB labelled "MB"; the two differ by 4.9 %.
W = 1000000.0
print()
print('=' * 78)
print(' STORAGE RATIOS   base = %.1f MB (10^6)   (%s)'
      % (B / W, os.path.basename(mod_dir)))
print('=' * 78)
print(' %-20s %4s %12s %12s %8s %12s' %
      ('cohort', 'N', 'stored MB', 'monolith MB', 'ratio', 'mean delta'))
for label, N, stored, model, ratio, mean_d in rows:
    print(' %-20s %4d %12.1f %12.1f %8.2fx %10.1f MB'
          % (label, N, stored / W, model / W, ratio, mean_d))
print('=' * 78)

# Check the B + d model against every real monolithic build present.
checked = []
for n in sorted(names):
    mono = os.path.join(mod_dir, n + '-monolithic.sqsh')
    if os.path.exists(mono):
        measured = os.path.getsize(mono)
        modelled = B + size(n)
        checked.append((n, measured / W, modelled / W,
                        100.0 * (modelled / measured - 1.0)))
if checked:
    print(' MONOLITHIC MODEL CHECK  (modelled = base + delta, against real builds)')
    print(' %-18s %10s %10s %8s' % ('module', 'measured', 'modelled', 'error'))
    for n, meas, mod, err in checked:
        print(' %-18s %9.1f %10.1f %+7.2f %%' % (n, meas, mod, err))
    errs = [e for _, _, _, e in checked]
    print(' model overstates the saving by %.2f-%.2f %% across %d real builds'
          % (min(errs), max(errs), len(errs)))
else:
    print(' NO MONOLITHIC BASELINES PRESENT -- the ratio column is unchecked model.')
    print(' Rebuild them with: sudo ./scripts/02_build_delta.sh --compare <name> <pkg>')
print('=' * 78)
print()

if csv_out:
    with open(csv_out, 'w', encoding='utf-8') as f:
        f.write('cohort,n,stored_bytes,monolithic_bytes,ratio,mean_delta_bytes\n')
        for label, N, stored, model, ratio, mean_d in rows:
            f.write('%s,%d,%d,%d,%.4f,%d\n'
                    % (label, N, stored, model, ratio, int(mean_d * W)))
    print(' csv: %s' % csv_out)
PY
