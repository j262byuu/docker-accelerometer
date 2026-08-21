# docker-accelerometer

A Docker image for [GGIR](https://wadpac.github.io/GGIR/) accelerometer data processing, published as `j262byuu/accelerometer`, built for high-throughput batch processing on HPC clusters.

> Renamed from `docker-GGIR-mkl` in August 2026, after Intel MKL was measured and
> removed — see [Phase 1](#phase-1-intel-mkl--tried-measured-removed). GitHub redirects
> the old repository URL, and **the Docker Hub image name has not changed**, so existing
> `docker pull` and `docker run` commands keep working unaltered.

## Acknowledgements

This image is built entirely upon the [GGIR R package](https://wadpac.github.io/GGIR/) by **Vincent van Hees** and the [wadpac](https://github.com/wadpac) community. GGIR is a foundational contribution to actigraphy and physical activity research.

When using this image, **please cite the original GGIR publications** (doi: 10.5281/zenodo.1051064).

## Quick Start

**Docker (Local / Cloud VMs)**

```bash
docker run --rm \
  -v /your/data:/data \
  -v /your/output:/output \
  j262byuu/accelerometer:05092026 \
  Rscript /data/GGIR.R
```

**Singularity / Apptainer (HPC Clusters)**

```bash
# Pull the image
apptainer pull ggir.sif docker://j262byuu/accelerometer:05092026

# Execute on compute node
apptainer exec \
  -B /your/data:/data \
  -B /your/output:/output \
  ggir.sif Rscript /data/GGIR.R
```

> **Before your first real run**, set `maxNcores` — see
> [Configuring parallelism](#configuring-parallelism). GGIR sizes its worker pool from
> the host, not from what your container or scheduler actually gave you, and the
> failure is silent.

## Available Tags

| Tag | GGIR | Notes |
|-----|------|-------|
| **08212026** (Latest) | 3.3-8 · [`62346165`](https://github.com/wadpac/GGIR/commit/62346165ce1dd43ac83c26343b8a2658be24fa7c) | **Intel MKL removed**; the image now uses the base image's OpenBLAS pinned to one thread. Measured indistinguishable from MKL at the settings this image ships with, and **4.34 GB → 1.92 GB**. Also removes a hard failure mode: with the thread variables unset the MKL build died on its first BLAS call, where OpenBLAS simply falls back to all cores. `OPENBLAS_NUM_THREADS=1` replaces `MKL_THREADING_LAYER`/`MKL_NUM_THREADS`. Details in [Phase 1](#phase-1-intel-mkl--tried-measured-removed). |
| 05092026 | 3.3-7 · [`388064b7`](https://github.com/wadpac/GGIR/commit/388064b707df4fcfb7f9b755c5a43a477d371092) | Added unisensR for Movisens (.unisens) format support — pairs with `libxml2-dev` that was previously bundled but unused. `MKL_THREADING_LAYER` switched from `GNU` to `SEQUENTIAL`: no OpenMP runtime loaded into R, so no per-thread address space reserved in each of GGIR's PSOCK workers. (Superseded by 08212026, which removed MKL entirely.) Container TZ explicitly UTC (pass `desiredtz=` to GGIR for participant local time). `/etc/ggir-version` stamps installed GGIR version + upstream commit SHA for provenance. Build-time smoke test prevents shipping broken images. |
| 04152026 | 3.3-4 | Rcpp pre-installed for compatibility with the [Rcpp-optimized GGIR fork](https://github.com/j262byuu/GGIR/tree/feature/rcpp-enmo). Intel MKL as default BLAS/LAPACK backend. GGIR installed from official upstream (wadpac/GGIR). `MKL_NUM_THREADS` locked to 1 by default to prevent thread contention during GGIR's file-level parallelization. UTF-8 locale set for timestamp parsing edge cases. |
| 04022026 | 3.3-4 | Intel MKL integrated (Debian `intel-mkl`, version 2020.4.304). GGIR from official upstream. Note this is where the image grew: `intel-mkl` pulls ~1.2 GB of MKL packages, ~1.0 GB of it `-dev` files a runtime image never opens. |
| 03262026 | 3.3-4 | Rebuilt from scratch with a minimal Dockerfile. Base image upgraded to `rocker/r-ver:4.5.3`. `mMARCH.AC` dropped. Image size reduced from 4.36 GB to 1.8 GB. |
| 03092026 | 3.3-4 | `mMARCH.AC` updated to 3.3.4.0. ⚠️ Avoid versions prior to 3.2-7 due to a start time bug ([issue #1311](https://github.com/wadpac/GGIR/issues/1311)) affecting parts 5 and 6. |
| 10142025 | 3.3-1 | Fix for part 6 failures with multithreading enabled. |
| 09182025 | 3.3-0 | Added auto-correct sleep guider. |
| 07242025 | 3.2-9 | Docker image flattened to reduce size. |

**Why the commit and not just the version.** The Dockerfile installs from
`wadpac/GGIR`'s default branch, which is the latest development state rather than the
latest release. Those are not the same thing: 3.3-8 was released on 2026-07-24, and the
commit shipped in 08212026 is from 2026-08-12 — three weeks of further commits, all
still declaring version 3.3-8. So two images can both say "3.3-8" and contain different
code, and the commit is what actually pins it.

Any image from 05092026 onward carries the stamp:

```bash
docker run --rm j262byuu/accelerometer:08212026 cat /etc/ggir-version
# 3.3-8 62346165ce1dd43ac83c26343b8a2658be24fa7c
```

Earlier tags predate that file. For those, read it out of the installed package
instead — this is the same field `/etc/ggir-version` is generated from:

```bash
docker run --rm j262byuu/accelerometer:04152026 \
  Rscript -e 'cat(packageDescription("GGIR")$RemoteSha)'
```

That returns nothing if the image in question installed GGIR from CRAN rather than
from GitHub. The tags above have not each been checked.

<details>
<summary>Archived Tags</summary>

These tags have been removed from the registry. Listed for reference only.

| Tag | GGIR | Notes |
|-----|------|-------|
| 05022025 | 3.2-6 | Sleep regularity index introduced. |
| 01112025 | 3.1-10 | — |
| 12042024 | 3.1-7 | Added `part2_eventsummary.csv`. |
| 11152024 | 3.1-6 | GitHub-only; `nonwear_range_threshold` reset to 150. |
| 10112024 | 3.1-5 | Added `image.plot` fields in module 5 and system-level pandoc. |
| 09172024 | 3.1-5 | Added rmarkdown and r.jive. |
| 09132024 | 3.1-4 | mMARCH.AC 2.9.4.0. |

</details>

## Configuring parallelism

Read this before your first real run. The defaults are wrong for containers and for
scheduled cluster jobs, and the failure is silent.

### GGIR sizes its worker pool from the host, not from your allocation

GGIR picks its worker count like this, at all seven of its parallel sites
([`R/g.part1.R:363`](https://github.com/wadpac/GGIR/blob/62346165ce1dd43ac83c26343b8a2658be24fa7c/R/g.part1.R#L363-L368)):

```r
cores = parallel::detectCores()
Ncores = cores[1]
if (Ncores > 3) {
  if (length(params_general[["maxNcores"]]) == 0) params_general[["maxNcores"]] = Ncores
  Ncores2use = min(c(Ncores - 1, params_general[["maxNcores"]], (f1 - f0) + 1))
```

`(f1 - f0) + 1` is the number of files in the batch.

`parallel::detectCores()` reports the cores of the *machine*. It does not read the
cgroup CPU quota, so it does not know what your container or your scheduler actually
gave you. Measured on a 16-core host:

```console
$ docker run --rm --cpus=2 rocker/r-ver:4.5.3 Rscript -e 'cat(parallel::detectCores())'
16
$ docker run --rm --cpus=2 rocker/r-ver:4.5.3 cat /sys/fs/cgroup/cpu.max
200000 100000        # quota / period = 2 CPUs
```

With `maxNcores` left unset, that 2-CPU container starts **up to 15 worker processes**
— one per file, capped at `detectCores() - 1`. The same thing happens under a
scheduler: a 4-slot LSF allocation on a large node reports `detectCores()` = 128.

**Always pass `maxNcores` explicitly.** Match it to what you were allocated, not to
what the node has:

```r
GGIR(
  ...,
  do.parallel = TRUE,
  maxNcores   = as.integer(Sys.getenv("LSB_DJOB_NUMPROC", "4"))   # or SLURM_CPUS_PER_TASK, or your --cpus value
)
```

The workers are PSOCK — separate R processes, not forks — so each one is a full R
session with its own memory and its own BLAS. Nothing is shared with the parent.

### Thread environment variables

Each worker must keep its BLAS single-threaded, or `N` workers x `M` BLAS threads
oversubscribe the CPU. This image ships `OPENBLAS_NUM_THREADS=1` and
`OMP_NUM_THREADS=1`, so that is already handled; the table is here for when you change
the BLAS, or run the same script outside the container.

| Library | Variable | Note |
|---|---|---|
| OpenBLAS | `OPENBLAS_NUM_THREADS`, else `GOTO_NUM_THREADS`, else `OMP_NUM_THREADS` | first one set wins |
| Intel MKL | `MKL_THREADING_LAYER`, `MKL_NUM_THREADS` | |
| Apple Accelerate | `VECLIB_MAXIMUM_THREADS` | macOS only |
| data.table | `OMP_NUM_THREADS` | via `initDTthreads()` |

A threaded BLAS also reserves per-thread buffers when the library loads, before any
BLAS call is made. Measured on `rocker/r-ver:4.5.3`: **136 MB of address space per
thread** for OpenBLAS 0.3.26, so 2.2 GB of `VmSize` at a 16-thread default. This is
reserved address space, not resident memory: `VmRSS` moved by 1.2 MB across those same
15 extra threads. It is harmless until something enforces a virtual-memory limit
(`ulimit -v`, LSF `-v`, SGE `h_vmem`), where sixteen workers reserving 2.2 GB apiece
will kill a job whose RSS never passed 1 GB.

### data.table is capped to one thread in this image

`OMP_NUM_THREADS=1` is baked in, and `data.table::initDTthreads()` ends in
`imin(ans, omp_get_max_threads())`, so data.table follows it. Measured on data.table
1.18.2.1:

```
unset              -> getDTthreads() = 8
OMP_NUM_THREADS=1  -> getDTthreads() = 1
```

That is what you want for GGIR batch runs, where every worker should stay
single-threaded. If you are doing downstream data.table work in the same container,
raise it for that step only:

```r
data.table::setDTthreads(4)
```

### Raising the thread count for downstream work

The thread caps are right for GGIR batch runs and wrong for interactive linear
algebra. Raise them for that step only, rather than unsetting them image-wide:

```bash
OPENBLAS_NUM_THREADS=8 OMP_NUM_THREADS=8 Rscript your_analysis.R
```

Do not do this for GGIR runs with `do.parallel = TRUE` — you would be multiplying the
worker count by the thread count.

Unsetting them entirely is survivable but rarely what you want: OpenBLAS then takes
every core it can see, which on a scheduled node is the host's core count rather than
your allocation, and reserves 136 MB of address space per thread. Earlier tags of this
image, which used Intel MKL, did not even survive it — see
[Phase 1](#phase-1-intel-mkl--tried-measured-removed).

## Performance Optimization Roadmap

Systematic profiling of GGIR Part 1 on a 251 MB Axivity CWA file (7-day, 100Hz) revealed the following time distribution:

| Component | Time | Share |
|---|---|---|
| `GGIRread::readAxivity` (I/O + CWA parsing) | 337 s | 75% |
| `g.applymetrics` (ENMO epoch aggregation) | 33 s | 7% |
| `g.calibrate` (auto-calibration) | 5.7 s | 1% |
| Other (non-wear detection, data management) | 76 s | 17% |
| **Total** | **451 s** | |

Two things this profile does not show. It was taken **without** the Verisense step
counter, which dominates everything here when it is enabled — see Phase 3. And the
75% term lives in `GGIRread`, a separate package, so it is out of scope for this
image and for the GGIR branches in Phase 2.

### Phase 1: Intel MKL — tried, measured, removed

From tag 04022026 to 05092026 this image replaced R's BLAS/LAPACK with Debian's Intel
MKL. Tag 08212026 removes it and uses the base image's OpenBLAS pinned to one thread.
This section is kept rather than deleted, because the reasoning that led in was sound
and the measurement that led back out is the useful part.

**Why it looked promising.** Profiling GGIR's source showed the core computations
(ENMO, epoch aggregation, non-wear detection) are element-wise vector operations that
never call BLAS, and that `g.calibrate`'s ellipsoid fit uses `lm.wfit` on matrices of
only three columns. So the case for MKL was never throughput — it was per-worker memory
footprint, on the theory that a threaded BLAS pre-allocates buffers that scale with the
core count and that MKL under `SEQUENTIAL` allocates none.

**What the measurement showed.** Both images derive from `rocker/r-ver:4.5.3` (both
report R 4.5.3 on Ubuntu 24.04.4), run back to back on the same 16-core host, min of 3
reps, seconds:

| Arm | matmul 3000 | crossprod 3000 | chol 3000 | svd 800 | Address space per BLAS thread |
|---|---|---|---|---|---|
| MKL `SEQUENTIAL`, 1 thread | 2.30 | 1.36 | 0.46 | 0.61 | none reserved |
| OpenBLAS, 1 thread | 2.29 | 1.28 | 0.46 | 0.64 | none reserved |
| MKL `GNU`, 8 threads | 0.54 | 0.37 | 0.13 | 0.30 | 72 MB |
| OpenBLAS, 8 threads | 0.57 | 0.42 | 0.17 | 0.45 | 136 MB |

Three readings, in the order they mattered.

*At one thread — the only setting this image ever used — MKL and OpenBLAS are
indistinguishable.* 2.30 s against 2.29 s, 0.46 s against 0.46 s, and OpenBLAS is
marginally ahead on `crossprod`. Neither reserves per-thread address space. **The
premise was wrong**: the memory saving that justified MKL comes from running the BLAS
single-threaded, not from the vendor, and `OPENBLAS_NUM_THREADS=1` delivers it for
free.

*MKL's genuine advantage is real but unreachable here.* Threaded, it is 5% faster than
OpenBLAS on `matmul` and 33% on `svd`, and reserves half the address space per thread —
72 MB against 136 MB, so 576 MB against 1088 MB at eight threads. All of that requires
threading, which this image disables on purpose.

*The stronger memory claim earlier revisions made does not survive.* It is address
space, not resident memory, even after real BLAS work: running a 1000×1000 multiply,
`VmRSS` was 106.6 MB at one thread and 108.9 MB at sixteen. The buffers are reserved
and never touched. Virtual-memory limits notice; the OOM killer does not.

**What it cost.** Two things, neither of which showed up until they were looked for.

*Size.* Debian's `intel-mkl` metapackage pulls roughly 1.2 GB of MKL packages, about
1.0 GB of it `-dev` files a runtime image never opens — `libmkl-computational-dev` at
640 MB, `libmkl-threading-dev` at 270 MB, `libmkl-interface-dev` at 124 MB. Removing
MKL took the image from **4.34 GB to 1.92 GB**.

*A hard failure mode.* With `MKL_THREADING_LAYER`, `MKL_NUM_THREADS` and
`OMP_NUM_THREADS` all unset, R in the MKL image died on its first BLAS call:

```
R: symbol lookup error: /usr/lib/x86_64-linux-gnu/libmkl_intel_thread.so:
   undefined symbol: __kmpc_global_thread_num
```

`libmkl_intel_thread.so` needs Intel's own OpenMP runtime, `libiomp5`, which Ubuntu
24.04 does not package at all — so this was not a missing `apt install`.
`MKL_THREADING_LAYER=SEQUENTIAL` had been documented as a memory optimisation; it was
in fact the thing keeping the image alive. The OpenBLAS build has no such edge: unset
the same variables and it simply falls back to all cores.

It is also worth recording that Debian ships MKL **2020.4.304**. Every number above is
a statement about a 2020 release, not about oneAPI. A current MKL would fix the
threading-layer failure and sharpen the threaded kernels — but not the finding that
decided this, which is structural rather than versional: GGIR's hot paths do not call
BLAS, so no BLAS is going to move them.

**Verification of the replacement.** Same probe, both images:

| | 08212026 (OpenBLAS) | 05092026 (MKL) |
|---|---|---|
| matmul 1000, as shipped | 0.10 s | 0.09 s |
| BLAS threads, as shipped | 1 | 1 |
| `getDTthreads()`, as shipped | 1 | 1 |
| all thread variables unset | works; 16 threads, 0.03 s | **R dies on first BLAS call** |
| image size | **1.92 GB** | 4.34 GB |

### Phase 2: Upstream patches to GGIR — measured, not yet submitted

Fifteen branches on [j262byuu/GGIR](https://github.com/j262byuu/GGIR/branches/all) —
fourteen below plus the one in Phase 3 — of which thirteen are proposed for upstream
submission. The two that are not are marked *held* and *withdrawn* in the last table. Every figure below is paired
against `main`: both arms built from the same source, run back to back inside one LSF
job on one physical host, seven replicates over ten UK Biobank `.cwa` recordings
(100 Hz, ~6.9 days each). "7/7" means the branch was faster in all seven pairs.

**Combined, thirteen branches merged into one, whole pipeline, ten recordings:**

| Image | BLAS | Effect | Sign |
|---|---|---|---|
| this image, already thread-capped (measured on 05092026, when it was MKL `SEQUENTIAL`; 08212026 is single-threaded OpenBLAS and behaves the same way here) | single-threaded | **−21.88 s** / −3.32% | 7/7 |
| `rocker/r-ver:4.5.3`, a default install | openblas-pthread | **−113.54 s** / −12.19% | 7/7 |

Quote the absolute figure rather than the percentage: the two baselines differ (658 s
against 932 s) precisely because the unoptimised one is slower, so the ratio moves with
both terms. Both figures **understate a large cohort**, because the four cohort-scale
branches below contribute nothing at ten recordings by construction.

The gap between those two rows is almost entirely one branch,
`fix/nested-parallelism-thread-explosion`. **Users of this image already have that
benefit** — the thread variables baked into the Dockerfile do the same job from
outside, and that was true of the MKL build and is true of the OpenBLAS one — which is
why this image's row is the smaller one.

#### Largest and self-contained

| Branch | Effect | Equivalence |
|---|---|---|
| [`perf/haspt-runmed`](https://github.com/j262byuu/GGIR/tree/perf/haspt-runmed) | **part 3 −34.0%** (−11.362 s, sd 0.877, 7/7) | bit-identical; `HASPT` falls from 51.8% of part 3 to 0.6% |
| [`perf/detecmidnight-vectorise`](https://github.com/j262byuu/GGIR/tree/perf/detecmidnight-vectorise) | **part 3 −5.4%** (−2.064 s, sd 0.377, 7/7) | bit-identical; the vectorised step is 0.870 s → 0.044 s |

Both replace a per-epoch R closure — `zoo::rollapply` with a median callback, and a
`strsplit()` timestamp parser — that ran on the order of 10⁴–10⁵ times per night.

#### Parallelism: one correctness fix and one speedup that depends on it

| Order | Branch | Effect |
|---|---|---|
| 1 | [`perf/stopcluster-onexit`](https://github.com/j262byuu/GGIR/tree/perf/stopcluster-onexit) | Not a speedup. All seven parallel sections registered `on.exit(stopCluster(cl))` only *after* the `%dopar%` loop, so an interrupt during the parallel section leaked workers for the rest of the session. On interrupt `main` leaves 4 open worker sockets; this leaves 0 |
| 2 | [`fix/nested-parallelism-thread-explosion`](https://github.com/j262byuu/GGIR/tree/fix/nested-parallelism-thread-explosion) | **part 1 −18.9%** (−113.80 s, sd 62.75, 7/7) on a threaded-BLAS build, and **nothing** where the BLAS is already sequential — see the note above |

The second sits on the first and was measured against it, so they go up in that order.
Related to [wadpac/GGIR#1442](https://github.com/wadpac/GGIR/issues/1442).

#### Quadratic in cohort size — zero at ten recordings, large at 640

These measure as exactly nothing at the scale a functional test uses. That is a
statement about the cohort, not about the code, so each one carries its curve rather
than a single number.

| Branch | At 640 recordings | Shape |
|---|---|---|
| [`perf/part5-file-index`](https://github.com/j262byuu/GGIR/tree/perf/part5-file-index) | 4.550 s → 0.007 s (**650x**) | O(F²): a `dir()` per recording over a directory of F files |
| [`perf/write-parquet-index`](https://github.com/j262byuu/GGIR/tree/perf/write-parquet-index) | 305.076 s → 2.791 s (**109x**) | O(N²) → O(N) key lookup. Nothing inside GGIR calls it; reached only via the exported `write_dashboard_parquet` |
| [`perf/report-part4-index`](https://github.com/j262byuu/GGIR/tree/perf/report-part4-index) | 0.075 s → 0.003 s (**25x**) | O(F²), small constant |
| [`perf/report-part5-aggregate-column`](https://github.com/j262byuu/GGIR/tree/perf/report-part5-aggregate-column) | 0.680 s → 0.103 s (**6.6x**) at 89,600 rows | **Linear** — 13 columns aggregated where 1 is read. A constant factor, not a scaling fix |

#### Measured at or near zero — conditional, held, or withdrawn

Listed because a measurement that came back empty is still a result, and because
each one names the condition under which it would not be.

| Branch | Measured | Status |
|---|---|---|
| [`perf/part5-timestamp-hoist`](https://github.com/j262byuu/GGIR/tree/perf/part5-timestamp-hoist) | part 5 −2.3% (−0.523 s, sd 0.340, 7/7) | Small but consistent |
| [`perf/part1-chunkloop-deadwork`](https://github.com/j262byuu/GGIR/tree/perf/part1-chunkloop-deadwork) | −5.367 s, sd 9.377 | To be split. The `ClipLog` half is clean dead-work removal — the whole matrix was re-divided on every loop iteration |
| [`perf/applymetrics-en-guard`](https://github.com/j262byuu/GGIR/tree/perf/applymetrics-en-guard) | no timing obtained | Conditional, and the default configuration is not one of the conditions: `do.enmo` is on by default, so the skip never fires. Only helps runs asking for angle or zero-crossing metrics alone |
| [`perf/part6-timestamp-hoist`](https://github.com/j262byuu/GGIR/tree/perf/part6-timestamp-hoist) | +0.100 s, sd 0.261 | Real at 5 s epochs, absent under `part5_agg2_60seconds = TRUE`, which makes the series 12x shorter. Would be wrong to claim unconditionally |
| [`perf/part4-version-hoist`](https://github.com/j262byuu/GGIR/tree/perf/part4-version-hoist) | −0.068 s, sd 0.245 | **Held.** `installed.packages()` costs 3 ms once R caches it, not the 10 ms assumed. No measurable gain and no bug fixed |
| [`perf/reuse-parsed-header`](https://github.com/j262byuu/GGIR/tree/perf/reuse-parsed-header) | +4.031 s, sd 24.575 | **Withdrawn.** The cache does engage, but `readAxivity` spends no measurable time parsing the header. The underlying bug is real — `main` reads `accread$header`, a field that does not exist on that object, on every chunk of every file — and is filed upstream as an issue instead |

### Phase 3: Verisense step counting — check which copy you are running

The single largest effect found, and it is not a GGIR defect. In a configuration that
runs the Verisense step counter, that one external function is about 90% of pipeline
wall clock — more than every branch above combined, by two orders of magnitude.

GGIR's bundled `user-scripts/verisense_count_steps.R` is **already the fast form**. The
slow copy was our own lab's, and this is worth checking if you inherited a
`myfun` from somewhere:

| Change | Effect | Equivalence |
|---|---|---|
| lab copy → GGIR's bundled copy | **9.24x on part 1**, end to end (n = 5 pairs) | 15/15 chunks `identical()` |
| bundled copy → [`perf/verisense-vectorise`](https://github.com/j262byuu/GGIR/tree/perf/verisense-vectorise) | **11.9x** (56.8 s → 4.8 s) | 15/15 `identical()` |

The vectorised rewrite keeps the same signature, the same coefficient order and the
same `fs = 15`, bug-for-bug. `user-scripts/` is in `.Rbuildignore` so the file does not
ship with the package, but the vignettes link to it, so it is the canonical copy.

These figures are **not additive** with Phase 2's: they were measured against a
different starting point and change a different thing.

### What is deliberately not claimed

- The combined figure was measured before `perf/reuse-parsed-header` was withdrawn and
  before `perf/verisense-vectorise` existed, so the merged set is not exactly the set
  now proposed. Neither swap moves the number materially, but it has not been
  re-measured.
- `mode = 1:6` in one job yields a pipeline total, so the combined run gives no
  per-stage split. Per-stage figures come from the individual branches.
- None of these branches has been submitted upstream yet. Until they are merged, the
  only way to use them is to install the branch directly.

## Contact

Feel free to reach out on [LinkedIn](https://www.linkedin.com/in/xiaoyu-zong-0a733ba0/)

欢迎研究者联系交流，LinkedIn 加我或者发邮件都可以。
