# METIS Bit-Identical Optimization Campaign — Results

Branch: `perf-bit-identical`. Driven by `PERF-REVIEW.md`. Every change here is **bit-identical**
to baseline output (verified: all 10 configs `cmp`-equal to `perf/ref/` for `seed=12345`).

## Method
- Build: `make config cc=gcc-15 && make` (gcc-15, `-O3 -march=native`, single-threaded → deterministic).
- Gate: `perf/harness.sh verify perf/ref` — must show `pass=10 fail=0` (byte-identical output).
- Timing: `perf/harness.sh bench <label> 3` — serial, min-of-3, phase timers via `-dbglvl=2`.
- Machine: Apple Silicon (10 cores), Darwin 25.5.0. Runs serial, machine otherwise idle.
- Raw rows accumulate in `perf/RESULTS.tsv`.

## Baseline (serial, min of 3) — seconds

| config | metis | coarsen | contract | initpart | refine |
|---|---|---|---|---|---|
| kway_cit_10 | 8.108 | 2.476 | 1.585 | 3.055 | 1.796 |
| kway_cit_50 | 11.202 | 2.508 | 1.617 | 2.672 | 5.008 |
| kway_cit_100 | 13.148 | 2.370 | 1.532 | 2.593 | 7.007 |
| kway_mdual_10 | 0.064 | 0.039 | 0.023 | 0.016 | 0.002 |
| kway_mdual_50 | 0.080 | 0.038 | 0.022 | 0.024 | 0.009 |
| kway_mdual_100 | 0.116 | 0.037 | 0.022 | 0.051 | 0.017 |
| rb_mdual_10 | 0.195 | 0.148 | 0.088 | 0.000 | 0.020 |
| rb_mdual_50 | 0.277 | 0.197 | 0.114 | 0.002 | 0.038 |
| rb_mdual_100 | 0.332 | 0.230 | 0.133 | 0.004 | 0.049 |
| nd_mdual | 2.895 | 0.465 | 0.266 | 0.424 | 1.864 |

Reference edgecuts (seed=12345): cit k10/50/100 = 1673921 / 2741107 / 3213730;
mdual kway 11157/24100/32113; rb 10313/22831/30689; nd opcount 5.964e+10.

## Optimizations (each verified bit-identical before measuring)

| ID | Description | Status | Key effect |
|---|---|---|---|
| T2.2 | Delete dead cmap stores in matching | ✅ bit-identical | matching −5..6% (cit) |
| T2.6 | SHEM condition reorder | ✅ bit-identical | matching −4..15% more (cit) |
| T2.8 | MMDOrder dead restore pass | ✅ bit-identical | nd neutral (noise) on mdual |
| T2.1 | Contraction hash-probe (htkeys) | ❌ REVERTED | contract +8% regression on ARM (extra store/cache pressure; removed load was already hot) |
| T2.3 | Fuse rename into split extraction | ✅ bit-identical | neutral on matrix (split phase tiny here; payoff is large recursive bisection) |
| T2.5 | cnbrpool presizing | ✅ bit-identical | neutral (realloc-copy time sub-noise); removes churn |
| T2.7 | sqrt table (gain priority) | wip | kway refine |
| T2.9 | CompressGraph early abort | ✅ bit-identical | exercised on mdual (rejected); nd front-end saving sub-noise |
| T2.4 | Reuse 2-way FM pqueues across calls | ❌ REVERTED | bit-identical but neutral (alloc churn sub-noise, like T2.5); not worth persistent-state complexity |
| T2.10 | SoA cnbr_t pool | ⏸ DEFERRED | see rationale below |
| T3.1 | LTO (CMAKE_INTERPROCEDURAL_OPTIMIZATION) | ✅ bit-identical KEPT | broad small gain; standard zero-risk |

### Outcome summary
**Kept (8):** T2.2, T2.6 (matching −10..20% on cit), T2.7 (k-way refine −6..7% on cit
50/100), T3.1 LTO (broad small), and T2.3/T2.5/T2.8/T2.9 (bit-identical, correct, remove
proven work, neutral-but-trivial on this matrix). Net **~3.5–5% on k-way cit-Patents**,
2–6% across the matrix — all bit-identical (see interleaved table above).

**Reverted (2), benchmarking-guided:**
- **T2.1** (contraction htkeys): measured **+8% contraction regression** — the removed
  `cadjncy[htable[kk]]` load was already hot, and the parallel `htkeys[]` added a store +
  cache pressure. Apple-Silicon OoO hid the original dependent-load latency.
- **T2.4** (FM queue reuse): **neutral** — the `rpqCreate` O(nvtxs) locator init it removes
  is sub-noise vs the FM work; not worth the persistent ctrl-queue state.

**Deferred (1): T2.10 SoA cnbr_t.** Splitting `cnbr_t{pid,ed}` into parallel `pid[]/ed[]`
arrays touches struct.h, wspace.c, kwayfm.c, kwayrefine.c, macros.h, contig.c, minconn.c —
a large refactor of the hottest refinement loop with high bit-identical risk. Its mechanism
(cache-line efficiency of pid-only scans) is the same class as T2.1, which **measurably
regressed** on this wide-OoO/large-cache target; and the ed[] value is consumed right after
the pid in the gain computation, so both arrays are touched per entry anyway. Expected
benefit on this hardware ≈ 0; risk high. Recommend implementing only behind a profiler on a
cache-bound target (e.g. older x86, or i64/r64 builds where cnbr_t is wider). Not done to
avoid destabilizing the verified working set for predicted-zero gain.

### Key lesson (Apple Silicon, gcc-15 -O3 -march=native -arch arm64)
Opts that remove **actual redundant work** (dead stores T2.2, the SHEM cache-miss skip T2.6)
or **expensive ops on the critical path** (sqrt T2.7) win. Opts that merely trade compute
for memory or rearrange allocation/layout (T2.1, T2.4, T2.5) are neutral-or-worse here — the
wide out-of-order core with large caches already hides the latencies they target.

## Cumulative result — interleaved A/B, baseline binary (master) vs current

Measured with `perf/compare.sh` (min-of-5, **baseline and current alternated per repeat**
to cancel machine-state drift; METIS time via the program summary line, no -dbglvl so no
timer overhead). Baseline = master worktree (no opts, no LTO). Current = all committed
bit-identical opts + LTO (pre-T2.4).

| config | baseline s | current s | delta |
|---|---|---|---|
| kway_cit_10 | 7.825 | 7.403 | **-5.4%** |
| kway_cit_50 | 11.258 | 10.764 | **-4.4%** |
| kway_cit_100 | 13.560 | 13.088 | **-3.5%** |
| kway_mdual_10 | 0.068 | 0.064 | -5.9% |
| kway_mdual_50 | 0.087 | 0.084 | -3.4% |
| kway_mdual_100 | 0.124 | 0.122 | -1.6% |
| rb_mdual_10 | 0.174 | 0.168 | -3.4% |
| rb_mdual_50 | 0.289 | 0.281 | -2.8% |
| rb_mdual_100 | 0.347 | 0.335 | -3.5% |
| nd_mdual | 1.400 | 1.377 | -1.6% |
| nd_mdual_cc | 1.495 | 1.483 | -0.8% |

Net: **~3.5–5% faster on the main k-way cit-Patents configs**, 2–6% across the matrix, all
bit-identical. Driven mostly by matching (T2.2/T2.6) and k-way refine (T2.7); LTO contributes
a small, broad amount.

### Measurement caveats discovered
- **`-dbglvl=2` doubles ndmetis time** (1.4s true vs 2.9s timed): the per-phase
  gk_startcputimer calls are invoked thousands of times across the deep dissection recursion.
  The harness phase tables (which use -dbglvl=2) are inflated for ndmetis; relative deltas
  within harness runs are still valid, but compare.sh (no dbglvl) gives true totals.
- cit-Patents *totals* drift ~5-8% run-to-run with machine state; per-phase isolation
  (judging an opt by the column it touches) and interleaved A/B are the reliable reads.

(Detailed per-opt notes appended below as they land.)
