# =============================================================================
# GGIR Docker Image
# Base: rocker/r-ver (Ubuntu-based, minimal, version-locked)
# Target: batch processing on HPC (Singularity/Apptainer compatible)
# GGIR source: GitHub master (wadpac/GGIR), always latest version
# Parallel: foreach + doParallel over PSOCK workers (separate R processes, not fork)
# BLAS/LAPACK: the base image's OpenBLAS, pinned to one thread (see below)
# =============================================================================
FROM rocker/r-ver:4.5.3
LABEL maintainer="j262byuu@gmail.com" \
      description="GGIR for batch accelerometer data processing on HPC"
# -----------------------------------------------------------------------------
# Locale & timezone: UTF-8 + UTC to avoid edge cases in GGIR's timestamp parsing
# -----------------------------------------------------------------------------
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
ENV TZ=Etc/UTC
# -----------------------------------------------------------------------------
# BLAS threading (CRITICAL FOR GGIR)
#
# GGIR parallelises with parallel::makeCluster(Ncores2use), no type= argument,
# at all seven of its parallel sites, so the workers are PSOCK — separate R
# processes sharing nothing with the parent at any point. Each loads its own
# BLAS, so N workers x M BLAS threads oversubscribe the CPU and each worker
# reserves its own thread buffers, strictly linear in the worker count.
#
# A threaded OpenBLAS reserves those buffers when the library loads, before any
# BLAS call: measured 136 MB of address space per thread on this base image
# (OpenBLAS 0.3.26), so 2.2 GB of VmSize at a 16-thread default. It is reserved
# address space, not resident memory — VmRSS moved 1.2 MB across 15 extra
# threads, even after a real matrix multiply. Harmless until something enforces
# a virtual-memory limit (ulimit -v, LSF -v, SGE h_vmem), where sixteen workers
# reserving 2.2 GB each kill a job whose RSS never passed 1 GB.
#
# OPENBLAS_NUM_THREADS=1: OpenBLAS reads this first, then GOTO_NUM_THREADS, then
#   OMP_NUM_THREADS, so setting the first one settles it.
#
# OMP_NUM_THREADS=1: covers other OpenMP consumers. Note this also caps
#   data.table, whose initDTthreads() ends in imin(ans, omp_get_max_threads())
#   — measured 8 threads -> 1 on data.table 1.18.2.1. Right for GGIR batch runs,
#   where each worker should stay single-threaded; override it for downstream
#   analysis inside this container. See README, "Configuring parallelism".
#
# Intel MKL was used here from tag 04022026 to 05092026 and has been removed.
# It was measured against OpenBLAS on this base image and, at the settings this
# image ships with, the two are indistinguishable: 1000x1000 matmul 2.30 s
# against 2.29 s, same reserved address space. MKL cost ~1.2 GB of image and
# brought a hard failure mode — Debian's intel-mkl needs libiomp5, which Ubuntu
# 24.04 does not package, so its default threading layer could not load and R
# died on the first BLAS call whenever the thread variables were unset. Full
# numbers in the README, "Phase 1".
# -----------------------------------------------------------------------------
ENV OPENBLAS_NUM_THREADS=1
ENV OMP_NUM_THREADS=1
# -----------------------------------------------------------------------------
# System dependencies
# Rationale for each:
#   libssl-dev           : read.gt3x, GGIRread, remotes (HTTPS downloads)
#   libcurl4-openssl-dev : remotes (GitHub install)
#   libxml2-dev          : unisensR (XML parsing for Movisens format)
#   zlib1g-dev           : data.table (compression)
#   git                  : remotes::install_github
# No BLAS package: the base image already ships OpenBLAS as the default
# libblas/liblapack alternative, which is what this image now uses.
# -----------------------------------------------------------------------------
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libssl-dev \
      libcurl4-openssl-dev \
      libxml2-dev \
      zlib1g-dev \
      git \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
      /usr/share/man/man*
# -----------------------------------------------------------------------------
# R packages
# - Rcpp     : build dependency for packages with compiled code
# - remotes  : needed to install from GitHub
# - unisensR : enables GGIR's Movisens (.unisens) reader; pairs with libxml2-dev
# - GGIR     : installed from official upstream (wadpac/GGIR)
# - dependencies=NA: only Imports + Depends, skips Suggests
# - doParallel/foreach pulled in automatically as GGIR Imports
#
# Build-time smoke test: load GGIR and check g.shell.GGIR is exported.
# Fails the build immediately if upstream master is broken or a transitive
# dep is incompatible — prevents shipping a broken image to users.
#
# /etc/ggir-version: stamps installed GGIR version + commit SHA for downstream
# debugging and methods-section provenance.
# -----------------------------------------------------------------------------
RUN install2.r --error --skipinstalled remotes Rcpp unisensR \
 && Rscript -e 'remotes::install_github("wadpac/GGIR", dependencies = NA, upgrade = "never")' \
 && Rscript -e 'suppressMessages(library(GGIR)); stopifnot(exists("g.shell.GGIR")); cat("GGIR", as.character(packageVersion("GGIR")), "loaded OK\n")' \
 && Rscript -e 'x <- matrix(runif(4e4), 200); y <- x %*% x; stopifnot(is.finite(y[1,1])); cat("BLAS:", sessionInfo()$BLAS, "OK\n")' \
 && Rscript -e 'd <- packageDescription("GGIR"); sha <- if (is.null(d$RemoteSha)) "NA" else d$RemoteSha; cat(sprintf("%s %s\n", d$Version, sha))' > /etc/ggir-version \
 && rm -rf /tmp/downloaded_packages /tmp/Rtmp*
# -----------------------------------------------------------------------------
# Singularity/Apptainer notes
# - No USER directive: Singularity maps container root to calling user
# - outputdir should be bind-mounted at runtime, not baked into image
# Usage:
#   Docker:      docker run --rm -v /data:/data -v /out:/output \
#                  j262byuu/accelerometer /data/GGIR.R
#   Singularity: apptainer exec ggir.sif Rscript /path/to/GGIR.R
# -----------------------------------------------------------------------------
CMD ["/bin/bash"]
