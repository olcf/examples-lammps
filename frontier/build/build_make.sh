#!/bin/bash

# LAMMPS build script
# - Uses `make` to build a Kokkos-enabled binary of LAMMPS with the HIP backend + hipFFT
# - Contains support for GPU-aware MPI

# Author: Nick Hagerty (hagertynl@ornl.gov)
# Last modified: May 20, 2024

# Frontier has 3 PrgEnv (programming environments) available:
#   PrgEnv-cray -- HPE/Cray, clang-based
#   PrgEnv-amd -- AMD, clang-based, automatically includes setup of device libraries (no need to load amd-mixed/rocm)
#   PrgEnv-gnu -- GNU gcc compiler
# All 3 PrgEnv's use `cc/CC/ftn` as the compiler wrapper around `C/C++/Fortran`.
# These wrappers automatically link cray-mpich and some other things, depending on loaded modules

# However, our LAMMPS build uses ``hipcc`` as the compiler, since that's what Kokkos currently requires, so we use PrgEnv-amd
module load PrgEnv-amd

# If we're using PrgEnv-cray, we need to explicitly load device libraries.
# The `rocm` module provides the ROCm toolkit for all programming environments.
# As of the Cray/HPE Programming Environment (CPE) December 2023 release, the `rocm` module must be loaded for ALL compiler toolchains.
# PrgEnv-amd no longer automatically provides the ROCm toolkit.

# FFTW3 for host-based FFT
module load cray-fftw

# We will use the latest available version of the CrayPE components (mainly cray-mpich) in this build:
module load cpe/23.12

# PrgEnv-amd uses the `amd` module to load a version of the AMD compilers, so load an `amd` version that we're happy with
# `rocm` is needed to load the ROCm device toolchain
module load amd/5.7.1
#module load rocm/5.7.1

# HWLOC is optional. No real performance benefit or gain
module load hwloc

startdir=${PWD}

[ ! -d ./lammps ] && git clone https://github.com/lammps/lammps.git

cd lammps/src

echo "Running clean-all..."
make clean-all

echo "Uninstalling all packages..."
make no-all

echo "Copying Makefile.gfx90a..."
rm -f ./MAKE/MINE/Makefile.gfx90a
cp ${startdir}/build_files/Makefile.gfx90a ./MAKE/MINE/Makefile.gfx90a

echo "Installing packages..."
for package in kokkos class2 kspace rigid molecule; do
    make yes-$package
done

echo "Running make gfx90a..."
make -j 8 gfx90a
echo "Finished. Exit code: $?"
