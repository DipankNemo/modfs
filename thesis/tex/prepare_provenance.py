#!/usr/bin/env python3
"""Rebuild the source-digest appendix without running ModFS experiments."""
from pathlib import Path
import hashlib, json, subprocess
ROOT=Path(__file__).resolve().parent
REPO=ROOT.parent.parent
origin=json.loads((ROOT/'evidence/origin.json').read_text())
items=[
(r'\Cref{fig:timing,tab:physical}', 'evidence/current/tier2-by-n.csv'),
(r'\Cref{fig:timing,tab:fits,eq:combined-time}', 'evidence/current/tier2-fit.csv'),
('Historical fit comparison', 'evidence/previous/tier2-fit.csv'),
(r'\Cref{tab:admission}', 'evidence/current/tier1-totals.csv'),
(r'\Cref{tab:causes}', 'evidence/current/tier1-classes.csv'),
('Control and set extension', 'evidence/current/tier1-control.csv'),
('Set-extension cross-check', 'evidence/current/tier1-crosscheck.csv'),
('Non-monotone exceptions', 'evidence/current/tier1-nonmonotone.csv'),
('Permitted overlap', 'evidence/current/tier1-measured.csv'),
('V1--V8 outcomes', 'evidence/current/tier2-checks.csv'),
(r'\Cref{fig:storage,tab:storage,eq:storage}', 'evidence/current/storage-cohorts.csv'),
('Storage exclusions', 'evidence/current/storage-sensitivity.csv'),
(r'\Cref{tab:calibration}', 'evidence/current/storage-model-check.csv'),
(r'\Cref{tab:module-inventory}', 'evidence/current/storage-per-module.csv'),
(r'\Cref{tab:boots}; boot durations', 'evidence/current/tier3.csv'),
('Catalogue classification', 'evidence/current/catalogue.csv'),
('Historical fat-base model; timing exclusions', 'evidence/current/claims.md'),
('Evidence corrections', 'evidence/current/inconsistencies.md'),
('Upstream identities and dates', 'evidence/current/provenance.md'),
('Previous upstream identities', 'evidence/previous/provenance.md'),
('Base bytes and recorded artefact identities', 'evidence/current/provenance-artefacts.csv'),
(r'\Cref{fig:architecture,tab:taxonomy,tab:digests}', 'ARCHITECTURE.md'),
(r'\Cref{tab:manifest}', 'docs/DATA_MODEL.md'),
('Registry discovery; schema history', 'JOURNAL.md'),
('Physical sampling and guest observation', 'docs/SAMPLING_AND_BOOT.md'),
('Merger counterexamples', 'tests/round4_attacks.py'),
('Equal-size substitution', 'tests/round2_attacks.py'),
('Evidence-pipeline counterexamples', 'tests/round3_evidence.py'),
('Registry implementation', 'scripts/reconcile.py'),
('Registry formats and implementation boundaries', 'docs/REGISTRY_FORMATS.md'),
('Independent monolith construction', 'scripts/02_build_delta.sh'),
('Separate flattened-root comparator', 'scripts/15_measure_monolith.sh'),
('Independent rebuild mechanisms and userspace GPU test', 'docs/evidence/remote-verification-2026-09-20/REPORT.md'),
('Declaration and disclosure requirements', 'thesis/thesis guidelines/AI_usage_in_thesis_work.pdf'),
]
rows=[]
for target,path in items:
    local=path.startswith('evidence/')
    file=(ROOT if local else REPO)/path
    if local:
        data=file.read_bytes()
        date='2026-09-22' if '/previous/' in path else '2026-09-23'
    else:
        data=subprocess.check_output(['git','show',origin['previous_revision']+':'+path],cwd=REPO)
        assert file.read_bytes()==data, 'Qualitative source changed: '+path
        date=subprocess.check_output(['git','log','-1','--format=%cs',origin['previous_revision'],'--',path],cwd=REPO,text=True).strip()
    rows.append(target+r' & \filepath{'+path+r'}\newline '+date+r' & \texttt{\seqsplit{'+hashlib.sha256(data).hexdigest()+r'}} \\')
parts=[r'\begingroup\footnotesize',r'\begin{longtable}{@{}p{3.1cm}p{5.4cm}p{4.1cm}@{}}',r'\caption{Source mapping for figures, tables, and supporting findings. Dates are evidence-export dates for frozen inputs and last-change dates at the pinned revision for repository documents; they are not all measurement dates. Digests identify source-file bytes.}\label{tab:provenance}\\',r'\toprule Figure / result & Source file and date & SHA-256 \\',r'\midrule\endfirsthead',r'\toprule Figure / result & Source file and date & SHA-256 \\',r'\midrule\endhead',*rows,r'\bottomrule\end{longtable}\endgroup']
(ROOT/'tables-provenance.tex').write_text('\n'.join(parts)+'\n')
print('Wrote',len(rows),'provenance entries.')
