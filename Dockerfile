# =============================================================================
# GGIR Docker Image
# Base: rocker/r-ver (Ubuntu-based, minimal, version-locked)
# Target: batch processing on HPC (Singularity/Apptainer compatible)
# GGIR source: GitHub master (wadpac/GGIR), always latest version
# Parallel: foreach + doParallel over PSOCK workers (separate R processes, not fork)
# BLAS/LAPACK: Intel MKL (Math Kernel Library) for hardware acceleration
# =============================================================================
FROM rocker/r-ver:4.5.3
LABEL maintainer="j262byuu@gmail.com" \
      description="GGIR for batch accelerometer data processing with Intel MKL"
# -----------------------------------------------------------------------------
# Locale & timezone: UTF-8 + UTC to avoid edge cases in GGIR's timestamp parsing
# -----------------------------------------------------------------------------
ENV LC_ALL=C.UTF-8
ENV LANG=C.UTF-8
ENV TZ=Etc/UTC
# -----------------------------------------------------------------------------
# MKL & Threading Environment Variables (CRITICAL FOR GGIR)
#
# DO NOT REMOVE THESE THREE LINES. Two of them are load-bearing for correctness,
# not performance: with all three unset, R in this image dies on its first BLAS
# call with
#
#   libmkl_intel_thread.so: undefined symbol: __kmpc_global_thread_num
#
# The Debian intel-mkl package ships libmkl_intel_thread.so, which needs Intel's
# own OpenMP runtime (libiomp5); that runtime is not installed here — only
# libgomp is. So libmkl_rt's default INTEL threading layer cannot load. Either
# SEQUENTIAL or the thread caps avoids it; dropping all three does not.
# GNU is the working multithreaded layer, because libgomp is present.
#
# Why single-threaded at all: GGIR parallelises with
# parallel::makeCluster(Ncores2use), no type= argument, at all seven of its
# parallel sites, so the workers are PSOCK — separate R processes sharing
# nothing with the parent at any point. Each loads its own BLAS and reserves its
# own thread buffers, so cost is strictly linear in the worker count, with none
# of the copy-on-write relief a forked pool would give. N workers × M BLAS
# threads also oversubscribe the CPU.
#
# The memory side is address space, not resident memory. A threaded BLAS reserves
# per-thread buffers at library load, before any BLAS call: measured 136 MB per
# thread for OpenBLAS 0.3.26 and 72 MB per thread for MKL under GNU. RSS does not
# move. That is harmless until something enforces a virtual-memory limit —
# ulimit -v, LSF -v, SGE h_vmem — where sixteen workers reserving 2.2 GB each
# kill a job whose RSS never passed 1 GB.
#
# MKL_THREADING_LAYER=SEQUENTIAL: load no threading runtime inside MKL at all,
#   rather than loading one and capping it at a single thread.
#
# MKL_NUM_THREADS=1: redundant while SEQUENTIAL holds, kept because it is the arm
#   that still protects the image if anyone overrides the threading layer.
#
# OMP_NUM_THREADS=1: covers components outside MKL that consult it. Note this
#   also caps data.table, whose initDTthreads() ends in
#   imin(ans, omp_get_max_threads()) — measured 8 threads -> 1 on data.table
#   1.18.2.1. Right for GGIR batch runs, where each worker should stay
#   single-threaded; override it for downstream analysis inside this container.
#   See README, "Configuring parallelism".
# -----------------------------------------------------------------------------
ENV MKL_THREADING_LAYER=SEQUENTIAL
ENV MKL_NUM_THREADS=1
ENV OMP_NUM_THREADS=1
# -----------------------------------------------------------------------------
# System dependencies
# Rationale for each:
#   libssl-dev           : read.gt3x, GGIRread, remotes (HTTPS downloads)
#   libcurl4-openssl-dev : remotes (GitHub install)
#   libxml2-dev          : unisensR (XML parsing for Movisens format)
#   zlib1g-dev           : data.table (compression)
#   git                  : remotes::install_github
#   intel-mkl            : Intel Math Kernel Library for BLAS/LAPACK acceleration
# -----------------------------------------------------------------------------
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      libssl-dev \
      libcurl4-openssl-dev \
      libxml2-dev \
      zlib1g-dev \
      git \
      intel-mkl \
 && update-alternatives --set libblas.so.3-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/libmkl_rt.so \
 && update-alternatives --set liblapack.so.3-x86_64-linux-gnu /usr/lib/x86_64-linux-gnu/libmkl_rt.so \
 && apt-get clean \
 && rm -rf /var/lib/apt/lists/* \
      /usr/share/doc/intel-mkl* \
      /usr/share/man/man*
# -----------------------------------------------------------------------------
# R packages
# - Rcpp     : required for GGIR's Rcpp-accelerated ENMO path (j262byuu/GGIR
#              fork) and as a build dependency for packages with compiled code
# - remotes  : needed to install from GitHub
# - unisensR : enables GGIR's Movisens (.unisens) reader; pairs with libxml2-dev
# - GGIR     : installed from official upstream (wadpac/GGIR)
#              To use the Rcpp-optimized fork instead:
#              remotes::install_github("j262byuu/GGIR@feature/rcpp-enmo", ...)
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
