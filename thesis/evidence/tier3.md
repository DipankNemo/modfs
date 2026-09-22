# Tier 3 — QEMU UEFI boot runs

**Chapter: Evaluation**

## T3.0 Summary

| verdict | bundles |
|---|---|
| ABORTED | 4 |
| BROKEN | 2 |
| FAIL | 5 |
| PASS | 6 |
| no result.json | 3 |

_**2 of 20 bundles describe artefacts that still exist unchanged**; the rest were superseded by a later rebuild and are retained as history, not as current evidence. A `FAIL` verdict with all probes passing is the signature of class 8: the packages compose, the services cannot coexist._

## T3.1 Every run bundle

_One row per run bundle under `/srv/modfs/results`. A bundle is never overwritten, so this table is the complete boot history, including the runs where the harness rather than the system under test was the failure._

_Catalogue today: 40 modules · newest run 2026-09-18 23:19:43Z · 20 bundles_

| run | N | verdict | exit | systemd state | failed units | probes | dpkg audit | port ownership | s | note |
|---|---|---|---|---|---|---|---|---|---|---|
| acct-mp-20260916T142443Z | 2 | PASS | 0 | starting | 0 | 2/2 | PASS | 127.0.0.1:3306→mariadbd; 127.0.0.1:5432→postgres; 127.0.0.53%lo:53→systemd-resolve; [::… | 330 | **superseded**: mysql, postgres rebuilt since this run |
| acct-pm-20260916T134737Z | 2 | ABORTED | 2 | — | — | — | — | — | 170 | no serial.log — the guest never reached the harness; **superseded**: mysql, postgres rebuilt since this run |
| acct-pm-20260916T135532Z | 2 | BROKEN | 2 | (no marker) | 0 | — | — | (not recorded) | 324 | no LISTEN block in serial.log; **superseded**: mysql, postgres rebuilt since this run |
| acct-pm-20260916T140556Z | 2 | BROKEN | 2 | (no marker) | 0 | — | — | (not recorded) | 331 | no LISTEN block in serial.log; **superseded**: mysql, postgres rebuilt since this run |
| acct-pm-20260916T141529Z | 2 | PASS | 0 | starting | 0 | 2/2 | PASS | 127.0.0.1:3306→mariadbd; 127.0.0.1:5432→postgres; 127.0.0.53%lo:53→systemd-resolve; [::… | 316 | **superseded**: mysql, postgres rebuilt since this run |
| base-apache-curl-dnsutils-docker-emacs-fake-cuda-fake-nvidia-20260917T081459Z | 36 | ABORTED | 1 | — | — | — | — | — | 3 | no serial.log — the guest never reached the harness; **superseded**: curl, emacs, jq, nc-traditional and 3 more rebuilt since this run |
| base-apache-curl-dnsutils-docker-emacs-fake-cuda-fake-nvidia-20260917T081715Z | 36 | ABORTED | 0 | (no marker) | 0 | — | — | (not recorded) | 2142 | no LISTEN block in serial.log; **superseded**: curl, emacs, jq, nc-traditional and 3 more rebuilt since this run |
| gpu-stack-20260918T231701Z | 2 | ABORTED | 2 | — | — | — | — | — | 119 | no serial.log — the guest never reached the harness |
| gpu-stack-20260918T231943Z | 2 | PASS | 0 | running | 0 | 2/2 | PASS | 127.0.0.53%lo:53→systemd-resolve | 198 |  |
| m1-nginx-20260903T074039Z | 1 | no result | — | — | — | — | — | — | — | no serial.log — the guest never reached the harness; no result.json — run did not finish; **superseded**: webserver rebuilt since this run |
| m1-nginx-20260903T075510Z | 1 | no result | — | — | — | — | — | — | — | no serial.log — the guest never reached the harness; no result.json — run did not finish; **superseded**: webserver rebuilt since this run |
| m1-nginx-20260903T080001Z | 1 | PASS | 0 | running | 0 | 1/1 | PASS | 0.0.0.0:80→nginx; 127.0.0.53%lo:53→systemd-resolve; [::]:80→nginx | 232 | **superseded**: webserver rebuilt since this run |
| m2-apache-20260903T074546Z | 1 | no result | — | — | — | — | — | — | — | no serial.log — the guest never reached the harness; no result.json — run did not finish; **superseded**: apache rebuilt since this run |
| m2-apache-20260903T080409Z | 1 | PASS | 0 | running | 0 | 1/1 | PASS | (none) | 199 | **superseded**: apache rebuilt since this run |
| m2-apache-20260903T081752Z | 1 | PASS | 0 | running | 0 | 1/1 | PASS | *:80→apache2; 127.0.0.53%lo:53→systemd-resolve | 284 | **superseded**: apache rebuilt since this run |
| m3-nginx-apache-20260903T080746Z | 2 | FAIL | 1 | degraded | apache2.service | 2/2 | PASS | 0.0.0.0:80→nginx; 127.0.0.53%lo:53→systemd-resolve; [::]:80→nginx | 191 | **superseded**: apache, webserver rebuilt since this run |
| m4-apache-nginx-20260903T081112Z | 2 | FAIL | 1 | degraded | apache2.service | 2/2 | PASS | 0.0.0.0:80→nginx; 127.0.0.53%lo:53→systemd-resolve; [::]:80→nginx | 194 | **superseded**: apache, webserver rebuilt since this run |
| maxsub-20260916T154758Z | 36 | FAIL | 1 | starting | apache2.service | 34/36 | PASS | 0.0.0.0:80→nginx; 127.0.0.1:11211→memcached; 127.0.0.1:3306→mariadbd; 127.0.0.1:44359→c… | 189 | **superseded**: apache, curl, dnsutils, docker and 32 more rebuilt since this run |
| maxsub-20260917T075714Z | 36 | FAIL | 1 | starting | apache2.service | 35/36 | PASS | 0.0.0.0:80→nginx; 127.0.0.1:11211→memcached; 127.0.0.1:3306→mariadbd; 127.0.0.1:38621→c… | 204 | **superseded**: curl, emacs, jq, nc-traditional and 3 more rebuilt since this run |
| probes-20260918T123806Z | 36 | FAIL | 1 | starting | apache2.service | 36/36 | PASS | 0.0.0.0:80→nginx; 127.0.0.1:11211→memcached; 127.0.0.1:3306→mariadbd; 127.0.0.1:39853→c… | 183 | **superseded**: curl, emacs, jq, nc-traditional and 3 more rebuilt since this run |
