#!/bin/bash

#SBATCH -J lammps_run
#SBATCH -o %x-%j.out
#SBATCH -A <proj>
#SBATCH -t 10
#SBATCH -N 2
#SBATCH -C nvme

# This directly copies the build environment. See build scripts for comments:
module load PrgEnv-amd
module load cray-fftw
module load cpe/23.12
module load amd/5.7.1
module load hwloc

# All default versions of CrayPE libraries (ie, mpich, fftw) are sym-linked to the same directory
# This is done so that all of CrayPE can be linked by adding a single entry to LD_LIBRARY_PATH
# If you are NOT using default versions of CrayPE, you need to have this following line:
export LD_LIBRARY_PATH=$CRAY_LD_LIBRARY_PATH:$LD_LIBRARY_PATH

# Turn on GPU-aware MPI:
export MPICH_GPU_SUPPORT_ENABLED=1

exe=$(realpath ../build/lammps/install/bin/lmp)
echo "Using $exe"

# SBCAST --- ignore this section if you don't want to sbcast yet -------------------------
# sbcast places the executable on each node in node-local storage
# significantly alleviates overhead of launching at >100 nodes
base_exe=$(basename $exe)
ldd ${exe} &> ldd.presbcast.log

echo "Beginning SBCAST"
sbcast --send-libs --exclude=NONE -pf ${exe} /mnt/bb/$USER/$base_exe
echo "SBCAST exit code: $?"

echo "Adding symlinks to several libraries"
srun -N ${SLURM_NNODES} -n ${SLURM_NNODES} --ntasks-per-node=1 --label -D /mnt/bb/$USER/${base_exe}_libs \
    bash -c "if [ -f libhsa-runtime64.so.1 ]; then ln -s libhsa-runtime64.so.1 libhsa-runtime64.so; fi; if [ -f libamdhip64.so.5 ]; then ln -s libamdhip64.so.5 libamdhip64.so; fi"
echo "Finished adding symlinks"

echo "Patching LD_LIBRARY_PATH"
# Tell ld to find all your libraries in your sbcast'd directory -- not needed if you RPATH'd the build
# libfabric dlopen's a few libraries which aren't caught by `sbcast`, so we need to keep that path in LD_LIBRARY_PATH
export LD_LIBRARY_PATH=/mnt/bb/$USER/${base_exe}_libs:$(pkg-config --variable=libdir libfabric)

ldd /mnt/bb/$USER/${base_exe} &> ldd.postsbcast.log
exe=/mnt/bb/$USER/${base_exe}
# END SBCAST -----------------------------------------------------------------------------

export OMP_NUM_THREADS=7

srun -u -N ${SLURM_NNODES} -n $((SLURM_NNODES*8)) -c 7 \
    --gpus-per-node=8 --gpu-bind=closest \
    $exe -sf gpu -pk gpu 1 \
    -in in.lj -log none -v x 10 -v y 10 -v z 10

