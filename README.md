# docker-GGIR

A Docker image for [GGIR](https://wadpac.github.io/GGIR/) accelerometer data processing (`j262byuu/accelerometer`), optimized for high-throughput batch processing on HPC clusters.

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

> **Before your first real run**, set `maxNcores` and leave the image's thread
> variables alone — see [Configuring parallelism](#configuring-parallelism). The
> defaults are wrong for containers and scheduled jobs, and the failure is silent.

## Available Tags

| Tag | GGIR | Notes |
|-----|------|-------|
| **05092026** (Latest) | 3.3-7 | Added unisensR for Movisens (.unisens) format support — pairs with `libxml2-dev` that was previously bundled but unused. `MKL_THREADING_LAYER` switched from `GNU` to `SEQUENTIAL`: no OpenMP runtime loaded into R, so no per-thread address space reserved in each of GGIR's PSOCK workers. (Resident memory is unaffected — see [Configuring parallelism](#thread-environment-variables). This setting also turns out to be what keeps the image working if the thread caps are ever removed.) Container TZ explicitly UTC (pass `desiredtz=` to GGIR for participant local time). `/etc/ggir-version` stamps installed GGIR version + upstream commit SHA for provenance. Build-time smoke test prevents shipping broken images. |
| 04152026 | 3.3-4 | Rcpp pre-installed for compatibility with the [Rcpp-optimized GGIR fork](https://github.com/j262byuu/GGIR/tree/feature/rcpp-enmo). Intel MKL as default BLAS/LAPACK backend. GGIR installed from official upstream (wadpac/GGIR). `MKL_NUM_THREADS` locked to 1 by default to prevent thread contention during GGIR's file-level parallelization. UTF-8 locale set for timestamp parsing edge cases. |
| 04022026 | 3.3-4 | Intel MKL integrated. GGIR from official upstream. |
| 03262026 | 3.3-4 | Rebuilt from scratch with a minimal Dockerfile. Base image upgraded to `rocker/r-ver:4.5.3`. `mMARCH.AC` dropped. Image size reduced from 4.36 GB to 1.8 GB. |
| 03092026 | 3.3-4 | `mMARCH.AC` updated to 3.3.4.0. ⚠️ Avoid versions prior to 3.2-7 due to a start time bug ([issue #1311](https://github.com/wadpac/GGIR/issues/1311)) affecting parts 5 and 6. |
| 10142025 | 3.3-1 | Fix for part 6 failures with multithreading enabled. |
| 09182025 | 3.3-0 | Added auto-correct sleep guider. |
| 07242025 | 3.2-9 | Docker image flattened to reduce size. |

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
oversubscribe the CPU. This image sets that up already; the table is here for when you
change the BLAS, or run the same script outside the container.

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

### Do not unset the MKL variables

With `MKL_THREADING_LAYER`, `MKL_NUM_THREADS` and `OMP_NUM_THREADS` all unset, R in
this image dies on its first BLAS call:

```
R: symbol lookup error: /usr/lib/x86_64-linux-gnu/libmkl_intel_thread.so:
   undefined symbol: __kmpc_global_thread_num
```

The Debian `intel-mkl` package ships `libmkl_intel_thread.so`, which needs Intel's own
OpenMP runtime (`libiomp5`). That runtime is not installed — only `libgomp` is — so
MKL's default `INTEL` threading layer cannot load. Either `MKL_THREADING_LAYER=SEQUENTIAL`
or the thread caps prevents this; dropping all three does not.

If you want multithreaded MKL for downstream analysis, use the `GNU` layer, which works
because `libgomp` is present:

```bash
MKL_THREADING_LAYER=GNU OMP_NUM_THREADS=8 Rscript your_analysis.R
```

Do not do this for GGIR runs with `do.parallel = TRUE`.

## Performance Optimization Roadmap

Systematic profiling of GGIR Part 1 on a 251 MB Axivity CWA file (7-day, 100Hz) revealed the following time distribution:

| Component | Time | Share |
|---|---|---|
| `GGIRread::readAxivity` (I/O + CWA parsing) | 337 s | 75% |
| `g.applymetrics` (ENMO epoch aggregation) | 33 s | 7% |
| `g.calibrate` (auto-calibration) | 5.7 s | 1% |
| Other (non-wear detection, data management) | 76 s | 17% |
| **Total** | **451 s** | |

### Phase 1: Intel MKL ✅

Replaced default R BLAS/LAPACK with Intel MKL. After profiling GGIR's source code, I confirmed that GGIR's core computations (ENMO, epoch aggregation, non-wear detection) are element-wise vector operations that do not call BLAS. The `g.calibrate` ellipsoid fitting uses `lm.wfit` (QR decomposition), but on matrices of only 3 columns, too small for MKL to make a measurable difference.

**What this actually bought, measured rather than assumed.** Both images below derive
from `rocker/r-ver:4.5.3` (both report R 4.5.3 on Ubuntu 24.04.4), run back to back on
the same 16-core host, min of 3 reps, seconds:

| Arm | matmul 3000 | crossprod 3000 | chol 3000 | svd 800 | Address space per BLAS thread |
|---|---|---|---|---|---|
| MKL `SEQUENTIAL`, 1 thread — **as shipped** | 2.30 | 1.36 | 0.46 | 0.61 | none reserved |
| OpenBLAS, 1 thread | 2.29 | 1.28 | 0.46 | 0.64 | none reserved |
| MKL `GNU`, 8 threads | 0.54 | 0.37 | 0.13 | 0.30 | 72 MB |
| OpenBLAS, 8 threads | 0.57 | 0.42 | 0.17 | 0.45 | 136 MB |

Read honestly, that says three things.

*At the settings this image ships with, MKL is indistinguishable from OpenBLAS.* 2.30 s
against 2.29 s, 0.46 s against 0.46 s, and OpenBLAS is marginally ahead on `crossprod`.
Neither reserves per-thread address space at one thread. Earlier versions of this README
attributed the per-worker memory saving to MKL; that was wrong. The saving comes from
running the BLAS single-threaded, and `OPENBLAS_NUM_THREADS=1` would deliver it just as
well.

*MKL's real advantage only appears threaded* — 5% faster than OpenBLAS on `matmul` at
eight threads, rising to 33% on `svd`, and about half the address space per thread.
This image disables threading on purpose, so it collects neither.

*For general linear algebra this image is slower than the base it is built on* — 4x
against the eight-thread OpenBLAS arm above, and more than that against the stock
default, which is not capped at eight. That is the correct trade for GGIR batch
processing, where the thread discipline is the point, and the wrong one for interactive
modelling. Raise the thread count for that work: see
[Do not unset the MKL variables](#do-not-unset-the-mkl-variables) for the safe recipe.

One cost of the MKL choice, worth stating plainly: Debian's `intel-mkl` ships a default
threading layer that cannot load in this image, so `MKL_THREADING_LAYER=SEQUENTIAL` is
load-bearing for the image to work at all, not an optimisation. OpenBLAS would not have
brought that fragility. Details in the same section.

### Phase 2: Fused Rcpp ENMO Path ✅ (validated, pending upstream merge)

Replaced `g.applymetrics`' ENMO computation chain (`EuclideanNorm` -> subtract -> clamp -> `cumsum`-based epoch averaging) with a single-pass C++ implementation (`enmoFusedCpp`). Fork: [j262byuu/GGIR@feature/rcpp-enmo](https://github.com/j262byuu/GGIR/tree/feature/rcpp-enmo). Not yet included in the Docker image; will be integrated after upstream merge or when stability is fully confirmed. To use it now:

```r
remotes::install_github("j262byuu/GGIR@feature/rcpp-enmo", dependencies = NA, upgrade = "never")
```

Benchmarked on simulated 7-day 100Hz data (60.5M samples):

| Metric | Original R | Rcpp | Improvement |
|---|---|---|---|
| Time per call | 10.16 s | 1.45 s | **7.0x faster** |
| Peak memory | 6,597 MB | 2,806 MB | **57% less** |
| Correctness | Reference | max diff < 1e-11 | **PASS** |
| NA handling | cumsum propagates NA forward | NA limited to affected epoch | **Improved** |

The implementation accepts a `NumericMatrix` (zero-copy from R) rather than three separate column vectors, trading a small amount of speed (7x vs 8.6x with separate vectors) for less memory allocation at the R call boundary.

The primary value of this optimization is **memory reduction in parallel processing**. Each worker saves ~3.8 GB of transient allocations, allowing more concurrent workers on HPC nodes.

Note: end-to-end Part 1 speedup is modest because ENMO computation accounts for only 7% of total runtime. The dominant bottleneck is CWA/CSV file I/O (75%), which is addressed in Phase 3.

### Phase 3: CWA Reader Acceleration 🔧

Targeting `GGIRread::readAxivity`, which accounts for 75% of Part 1 runtime. Profiling breakdown:

- `readBin` (R-level binary I/O): 77.5 s, 490K R function calls for per-block reading
- `readDataBlock` (block parsing loop): 67.6 s, per-block header/checksum/unpack in R
- `resample` (interpolation to uniform grid): 26.9 s, already C-implemented in GGIRread
- `timestampDecoder` + `AxivityNumUnpack` + bit operations: 20 s

A C prototype replacing the per-block R loop with a single-pass C parser achieved **6.1x speedup** (176 s -> 29 s) on a 251 MB CWA file. Correctness validation is in progress. This work targets the GGIRread package (separate from GGIR).

Additionally, Part 1 reads each file twice (`g.calibrate` + `g.getmeta`), which doubles I/O cost. A single-read architecture could further halve I/O time.

## Contact

Feel free to reach out on [LinkedIn](https://www.linkedin.com/in/xiaoyu-zong-0a733ba0/)

欢迎研究者联系交流，LinkedIn 加我或者发邮件都可以。
