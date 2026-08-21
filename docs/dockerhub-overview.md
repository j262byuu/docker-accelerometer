<!--
Source of truth for the "Repository overview" on
https://hub.docker.com/r/j262byuu/accelerometer

Docker Hub has no version control for this text, which is how the previous
version kept two claims that had already been corrected here — "fork-based
parallelization" (GGIR uses PSOCK) and "hardware accelerated" (MKL measured as
no faster). Edit this file, then paste it into the Hub UI, so the two cannot
drift apart silently.
-->

R with [GGIR](https://wadpac.github.io/GGIR/) and its dependencies, for batch
accelerometer data processing on HPC clusters.

Full documentation, including the measurements behind the notes below:
**[github.com/j262byuu/docker-accelerometer](https://github.com/j262byuu/docker-accelerometer)**

Please cite the original GGIR publications (doi: 10.5281/zenodo.1051064).

## Quick start

```bash
docker run --rm -v /your/data:/data -v /your/output:/output \
  j262byuu/accelerometer:08212026 Rscript /data/GGIR.R
```

```bash
apptainer pull ggir.sif docker://j262byuu/accelerometer:08212026
apptainer exec -B /your/data:/data -B /your/output:/output \
  ggir.sif Rscript /path/to/GGIR.R
```

## Read this before your first real run

**Pass `maxNcores` explicitly.** GGIR sizes its worker pool with
`min(detectCores() - 1, maxNcores, n_files)`, and `parallel::detectCores()` reports the
cores of the *machine* — it does not read the cgroup CPU quota. On a 16-core host,
`docker run --cpus=2` still reports 16, so a 2-CPU container will start up to 15 worker
processes. A 4-slot LSF allocation on a large node reports 128. The failure is silent.

```r
GGIR(..., do.parallel = TRUE,
     maxNcores = as.integer(Sys.getenv("LSB_DJOB_NUMPROC", "4")))
```

**The image pins the BLAS to one thread** (`OPENBLAS_NUM_THREADS=1`,
`OMP_NUM_THREADS=1`), which is what you want for GGIR's PSOCK worker pool. Note this
also caps `data.table` to one thread; raise it with `setDTthreads()` for downstream
analysis.

## Provenance

Each image stamps the exact GGIR commit it was built from — the version number alone
does not identify the code, since the build tracks `wadpac/GGIR`'s default branch:

```bash
docker run --rm j262byuu/accelerometer:08212026 cat /etc/ggir-version
# 3.3-8 62346165ce1dd43ac83c26343b8a2658be24fa7c
```

## Tags

| Tag | GGIR | Notes |
|-----|------|-------|
| **08212026** | 3.3-8 | **Intel MKL removed**, replaced by the base image's OpenBLAS pinned to one thread. Measured indistinguishable from MKL at the settings this image ships with (matmul 3000: 2.30 s vs 2.29 s), and 4.34 GB → 1.92 GB uncompressed. Also removes a hard failure mode: with the thread variables unset the MKL build died on its first BLAS call, because Debian's `intel-mkl` needs `libiomp5`, which Ubuntu 24.04 does not package. |
| 05092026 | 3.3-7 | unisensR added for Movisens (.unisens) support. Container TZ explicitly UTC — pass `desiredtz=` for participant local time. `/etc/ggir-version` provenance stamp introduced. Build-time smoke test. |
| 04152026 | 3.3-4 | Rcpp pre-installed. `MKL_NUM_THREADS` pinned to 1. UTF-8 locale. |
| 04022026 | 3.3-4 | Intel MKL introduced as the BLAS/LAPACK backend. Later measured to give no benefit at this image's settings and removed in 08212026. |
| 03262026 | 3.3-4 | Rebuilt on `rocker/r-ver:4.5.3`. `mMARCH.AC` dropped. |
| 03092026 | 3.3-4 | ⚠️ Avoid GGIR before 3.2-7 — start-time bug affecting parts 5 and 6 ([#1311](https://github.com/wadpac/GGIR/issues/1311)). |

Older tags have been removed from the registry.
