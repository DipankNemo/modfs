# Catalogue — every module, what it is, and why it is here

**Chapter: Implementation**

_40 entries: 1 control, 36 real, 3 synthetic. `base` is not a sibling and has no UID window._

_**Catalogue: 40 modules** · measured 2026-09-18 22:58:43Z · source `/home/kaptan/modfs/specs/modules.yaml` · UID windows are 100 wide from 2000, append-only_

| module | kind | requested packages | artefact MB | packages in delta | UID window | provokes | status |
|---|---|---|---:|---:|---|---|---|
| apache | real | apache2 | 28.1 | 31 | 2700–2799 | runtime-port | built |
| control-oldsnap | control (snapshot 20250401T000000Z) | curl | 1.6 | 10 | 3200–3299 | positive-control | built |
| cuda-runtime | real | libcudart11.0, libcublas11, libcufft10, libcura… | 680.2 | 11 | 5900–5999 | scale | built |
| curl | real | curl | 1.6 | 10 | 3300–3399 | benign-overlap | built |
| dnsutils | real | bind9-dnsutils | 16.0 | 12 | 4400–4499 | benign-overlap | built |
| docker | real | docker.io | 83.1 | 13 | 5400–5499 | service-account | built |
| emacs | real | emacs-nox | 37.0 | 13 | 2100–2199 | alternatives | built |
| fake-cuda | synthetic | sl | 0.2 | 1 | 5600–5699 | module-dependency | built |
| fake-nvidia-driver | synthetic | hello | 0.2 | 1 | 5500–5599 | module-dependency | built |
| gawk | real | gawk | 3.1 | 5 | 2200–2299 | alternatives | built |
| gcc | real | build-essential | 84.0 | 47 | 4800–4899 | scale | built |
| git | real | git | 17.1 | 18 | 3500–3599 | benign-overlap | built |
| htop | real | htop | 0.4 | 3 | 3900–3999 | benign-overlap | built |
| java | real | default-jdk-headless | 141.6 | 31 | 4900–4999 | scale | built |
| jq | real | jq, moreutils | 0.6 | 3 | 3600–3699 | benign-overlap | built |
| llvm | real | llvm, clang | 128.2 | 47 | 5100–5199 | shared-toolchain | built |
| memcached | real | memcached | 10.3 | 9 | 4700–4799 | benign-overlap | built |
| mta-msmtp | real | msmtp-mta | 2.6 | 10 | 2800–2899 | virtual-provider | built |
| mta-nullmailer | real | nullmailer | 0.5 | 1 | 2900–2999 | virtual-provider | built |
| mysql | real | mariadb-server | 56.6 | 39 | 5300–5399 | service-account | built |
| nc-openbsd | real | netcat-openbsd | 0.3 | 3 | 2400–2499 | diversions | built |
| nc-traditional | real | netcat-traditional | 0.3 | 1 | 2500–2599 | diversions | built |
| nvidia-driver-535 | real | linux-objects-nvidia-535-5.15.0-185-generic, nv… | 231.6 | 12 | 5800–5899 | scale | built |
| original-awk | real | original-awk | 0.3 | 1 | 2300–2399 | alternatives | built |
| pgclient | real | postgresql-client | 12.1 | 15 | 4500–4599 | benign-overlap | built |
| pipdemo | synthetic | python3-pip | 15.5 | 19 | 5700–5799 | dpkg-blindness | built |
| postgres | real | postgresql | 82.1 | 29 | 5200–5299 | service-account | built |
| pytools | real | python3-numpy, python3-pip | 25.8 | 24 | 3000–3099 | base-upgrade | built |
| pyyaml | real | python3-yaml | 10.1 | 15 | 3100–3199 | benign-overlap | built |
| redis | real | redis-server | 1.7 | 8 | 4600–4699 | runtime-port | built |
| rsync | real | rsync | 0.7 | 2 | 3700–3799 | benign-overlap | built |
| rust | real | rustc, cargo | 175.5 | 45 | 5000–5099 | shared-toolchain | built |
| socat | real | socat | 0.6 | 2 | 4000–4099 | benign-overlap | built |
| sqlite | real | sqlite3 | 1.9 | 4 | 4200–4299 | benign-overlap | built |
| tcpdump | real | tcpdump | 1.1 | 3 | 4300–4399 | benign-overlap | built |
| tmux | real | tmux | 0.7 | 3 | 3800–3899 | benign-overlap | built |
| vim | real | vim | 18.1 | 15 | 2000–2099 | alternatives | built |
| webserver | real | nginx | 21.0 | 42 | 2600–2699 | runtime-port | built |
| wget | real | wget | 0.6 | 2 | 3400–3499 | benign-overlap | built |
| zstd | real | zstd | 0.9 | 1 | 4100–4199 | benign-overlap | built |

## C2 Cohort and kind, as declared

_`kind` comes from the `provokes` field in `modules.yaml` via a declared map, and the large/small cohort from a declared set — neither is inferred from artefact size, so neither can drift silently as the catalogue grows._

| kind | meaning | members |
|---|---|---|
| control | built from a different archive snapshot; must be refused against every sibling | control-oldsnap |
| synthetic | exists to exercise a mechanism, not to be a realistic workload | fake-cuda, fake-nvidia-driver, pipdemo |
| large realistic | real workload in the large storage cohort | cuda-runtime, docker, gcc, java, llvm, mysql, nvidia-driver-535, postgres, rust |
