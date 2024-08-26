#!/bin/bash

# LAMMPS build script
# - Uses `cmake` to build a Kokkos-enabled binary of LAMMPS with the HIP backend of the GPU package
# - With support for GPU-aware MPI

# Caveats:
# - We recommend considering the Kokkos acceleration package in addition to GPU package, as more AMDGPU-related features exist in Kokkos package

# Author: Nick Hagerty (hagertynl@ornl.gov)
# Last modified: May 20, 2024

# Frontier has 3 PrgEnv (programming environments) available:
#   PrgEnv-cray -- HPE/Cray, clang-based
#   PrgEnv-amd -- AMD, clang-based
#   PrgEnv-gnu -- GNU compiler toolchain
# All 3 PrgEnv's supply `cc/CC/ftn` as the compiler wrapper around `C/C++/Fortran` compilers
# These wrappers automatically link cray-mpich and some other things, depending on loaded modules

# However, our LAMMPS build uses ``hipcc`` as the compiler, so we use PrgEnv-amd
# ``hipcc`` is making calls to ``amdclang++``, so it makes the most sense to load PrgEnv-amd
module load PrgEnv-amd

# If we're using PrgEnv-cray or gnu, we need to explicitly load device libraries.
# The `rocm` module is provides the ROCm device toolchain.
# As of the Cray/HPE Programming Environment (CPE) December 2023 release, the `rocm` module must be loaded for ALL compiler toolchains.
# PrgEnv-amd no longer automatically provides the ROCm toolkit.

# FFTW3 for host-based FFT
module load cray-fftw

# We will use the latest available version of the CrayPE components (mainly cray-mpich) in this build:
module load cpe/23.12

# PrgEnv-amd uses the `amd` module to load a version of ROCm compilers, so load an `amd` version that we're happy with
module load amd/5.7.1
module load rocm/5.7.1

# The `cmake` module is needed for building with `cmake`
module load cmake

[ ! -d ./lammps ] && git clone https://github.com/lammps/lammps.git

cd lammps

rm -rf ./build ./install

mkdir build install

LMP_MACH=frontier_gfx90a
INSTDIR=${PWD}/install
# Explanation of compile flags:
#   -fdenormal-fp-math=ieee         -- specify to handle denormals in the same way that CUDA devices would
#   -fgpu-flush-denormals-to-zero   -- specify to handle denormals in the same way that CUDA devices would
#   -munsafe-fp-atomics             -- Tell the compiler to try to use hardware-based atomics on the GPU. Doesn't pose danger to correctness
#   -I${MPICH_DIR}/include          -- only necessary if not using Cray compiler wrappers
FLAGS='-fdenormal-fp-math=ieee -fgpu-flush-denormals-to-zero -munsafe-fp-atomics -I${MPICH_DIR}/include'

# Explanation of link flags:
#   -L${MPICH_DIR}/lib -lmpi        -- link cray-mpich
#   ${PE_MPICH_GTL_DIR_amd_gfx90a} ${PE_MPICH_GTL_LIBS_amd_gfx90a}      -- These environment variables are provided by cray-mpich.
#                                                                          They specify the library needed to use GPU-aware MPI.
#                                                                          Setting MPICH_GPU_SUPPORT_ENABLED=1 at run-time requires this library to be linked.
LINKFLAGS="-L${MPICH_DIR}/lib -lmpi ${PE_MPICH_GTL_DIR_amd_gfx90a} ${PE_MPICH_GTL_LIBS_amd_gfx90a}"

cd build

cmake \
       -DPKG_GPU=on -DGPU_API=HIP -DHIP_ARCH=gfx90a \
       -DPKG_MOLECULE=on \
       -DPKG_KSPACE=on \
       -DPKG_BODY=on \
       -DPKG_RIGID=on \
       -DBUILD_MPI=on \
       -DCMAKE_INSTALL_PREFIX=$INSTDIR \
       -DMPI_CXX_COMPILER=${ROCM_PATH}/bin/hipcc \
       -DCMAKE_CXX_COMPILER=${ROCM_PATH}/bin/hipcc \
       -DCMAKE_BUILD_TYPE=RelWithDebInfo \
       -DFFT=FFTW3 \
       -DFFTW3_INCLUDE_DIRS=$FFTW_ROOT/include \
       -DFFTW3_LIBRARIES=$FFTW_ROOT/lib \
       -DBUILD_OMP=on \
       -DCMAKE_CXX_STANDARD=14 \
       -DCMAKE_CXX_FLAGS="${FLAGS}" \
       -DCMAKE_EXE_LINKER_FLAGS="${LINKFLAGS}" \
       -DLAMMPS_MACHINE=${LMPMACH} \
       ../cmake

make VERBOSE=1 -j 8 install
