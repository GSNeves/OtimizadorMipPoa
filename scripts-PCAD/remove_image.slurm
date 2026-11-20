#!/bin/bash
#SBATCH --job-name=Remove_Image
#SBATCH --partition=shared
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=04:00:00
#SBATCH --output=%x_%j.out
#SBATCH --error=%x_%j.err

echo "===== Removendo image ====="

podman rmi julia-mip-cplex

echo "==== Garantindo que nada sobrou ===="

podman images