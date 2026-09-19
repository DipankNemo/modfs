#!/usr/bin/env bash
#
# Cohort storage ratios, computed from the artefacts rather than by hand.
#
#   ./scripts/13_storage_ratios.sh                 # table to stdout
#   ./scripts/13_storage_ratios.sh --csv out.csv   # also write a CSV
#
# Needs no root: it reads artefact SIZES only.
#
# WHY THIS EXISTS. The cohort table in ARCHITECTURE section 7 was computed ad
# hoc on 2026-09-16 and the JOURNAL entry for that day says so outright: "there
# is no aggregate storage script; the cohort table is computed ad hoc from
# artefact sizes. If that table is going to be regenerated on every rebuild it
# should become one." It is regenerated on every rebuild. This is it.
#
# THE RATIO, and what it does and does not say:
#
#     stored      = B + sum(d_i)              one base, N deltas
#     monolithic  = N*B + sum(d_i)            one whole image per use case
#     ratio       = monolithic / stored
#
# so it tends to N as deltas shrink and to 1 as they grow. The monolithic
# column is MODELLED as B + d, and that model is checked here against the six
# real monolithic builds `02_build_delta.sh --compare` produces: measured comes
# in 0.2-0.9 % BELOW the model, because squashfs compresses one whole tree
# slightly better than a base and a delta compressed separately. The model
# therefore mildly OVERSTATES the saving. The bias is small, it has a direction
# and a cause, and it is printed rather than assumed.
#
# The cohort split is a JUDGEMENT and is declared here, not derived from size,
# so that it cannot drift silently as modules are added.

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
# The two GPU modules joined this cohort on 2026-09-19. They are the largest
# artefacts in the catalogue and they are real; putting them anywhere else
# would be flattering the number.

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

rows = []
for label, cohort in (('small adversarial', [n for n in names if n not in LARGE]),
                      ('large realistic',   [n for n in names if n in LARGE]),
                      ('whole catalogue',   names)):
    d = sum(size(n) for n in cohort)
    N = len(cohort)
    stored, model = B + d, N * B + d
    rows.append((label, N, stored, model, (model / stored) if stored else 0,
                 (d / N / 1048576.0) if N else 0))

# DECIMAL MB (10^6), because that is the unit every published figure in
# ARCHITECTURE section 7 uses. mksquashfs and the build scripts' human() print
# BINARY MiB under the label "MB", so the two differ by 4.9 % and an undeclared
# unit is exactly the kind of thing that turns into a wrong number in a thesis.
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
