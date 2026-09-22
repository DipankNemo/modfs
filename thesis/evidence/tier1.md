# Tier 1 — metadata admission over all pairs and higher-N sets

**Chapter: Evaluation**

## T1.1 Combinations and verdicts by set size

_**Catalogue: 40 modules** · measured 2026-09-22 22:06:27Z · source `/srv/modfs/logs/combinations.csv`_

| N | combinations | ACCEPT | BROKEN | REJECT |
|---|---|---|---|---|
| 2 | 780 | 667 | 0 | 113 |
| 3 | 9880 | 7806 | 1 | 2073 |

## T1.2 Rejections by conflict class

_A combination may exhibit more than one class, so the class columns do not sum to the rejection count. Class 1 (benign overlap) is accepted and measured, not a rejection reason; it is in T1.3._

_**Catalogue: 40 modules** · measured 2026-09-22 22:06:27Z · source `/srv/modfs/logs/combinations.csv`_

| N | REJECT | class 2 version skew | class 3 declared conflict | class 4 file collision | class 7 identity collision | module relation (ARCHITECTURE §5) | class 6 implicit base upgrade | precondition: not composable |
|---|---|---|---|---|---|---|---|---|
| 2 | 113 | 7 | 1 | 0 | 0 | 75 | 0 | 39 |
| 3 | 2073 | 245 | 38 | 0 | 0 | 1370 | 0 | 741 |

## T1.3 Classes that are measured rather than rejected

_**Catalogue: 40 modules** · measured 2026-09-22 22:06:27Z · source `/srv/modfs/logs/combinations.csv`_

| N | combinations | sets with class-1 overlap | class-1 instances | sets with a suppressed class-4 collision | suppressed instances |
|---|---|---|---|---|---|
| 2 | 780 | 168 | 667 | 1 | 4 |
| 3 | 9880 | 4585 | 25346 | 38 | 152 |

## T1.4 Arithmetic cross-check: is every higher-N rejection explained by a rejecting pair inside it?

_`rejecting pairs in the catalogue` = 113 of 780._

_**Catalogue: 40 modules** · measured 2026-09-22 22:06:27Z · source `/srv/modfs/logs/combinations.csv`_

| N | sets | sets containing a rejecting pair | REJECT | REJECT explained by an inner pair | REJECT **unexplained** | ACCEPT despite an inner rejecting pair |
|---|---|---|---|---|---|---|
| 3 | 9880 | 2145 | 2073 | 2073 | 0 | 72 |

### T1.4a Why a set can be admitted although a pair inside it is rejected

_The class of the inner rejecting pair, counted per containing set. Rejection is monotone under adding modules for every class EXCEPT an unsatisfied module relation, which a third module can satisfy._

| N | class of the inner rejecting pair | containing sets admitted |
|---|---|---|
| 3 | module_relation | 72 |

## T1.5 Self-validation: the positive control

_`control-oldsnap` is built from a different archive snapshot and MUST be refused against every sibling. Predicted = C(39, N−1) sets contain it; observed = sets flagged `not_composable`. An all-ACCEPT sweep would now mean the sweep is broken._

| control | N | predicted sets containing it | observed not-composable |
|---|---|---|---|
| control-oldsnap | 2 | 39 | 39 |
| control-oldsnap | 3 | 741 | 741 |
