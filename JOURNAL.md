# Lab journal

Two lines per experiment. Dated. This becomes the Implementation and
Evaluation chapters — do not skip it.

## 2026-08-22
- New machine set up from scratch; repo initialised.
- TODO: restore scripts, rebuild base, verify checker still reports 0/0.

- Fresh machine (ketchup): full pipeline reproduced from git.
  base 113 pkgs / 40 MB, webserver +42 / 21 MB, pytools +24 / 25 MB.
  Checker: 0 errors, 0 warnings. Pinning reproducible across machines.

## 2026-08-22
- Fresh machine (ketchup), clean checkout: full pipeline reproduced.
  base 113 pkgs / 40 MB, webserver +42 / 21 MB, pytools +24 / 25 MB.
  libexpat1 2.4.7-1ubuntu0.7 identical in both deltas.
  Checker: 0 errors, 0 warnings.
- Byte-identical to the original machine => snapshot pinning is reproducible
  across hosts, not just across builds on one host.
