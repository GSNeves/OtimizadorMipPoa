#!/bin/bash
#SBATCH --job-name=run-cplex
#SBATCH --partition=cidia
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=32
#SBATCH --time=02:00:00
#SBATCH --output=run_%j.out
#SBATCH --error=run_%j.err

set -euo pipefail

echo "===== Informações do Job ====="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Scratch: $SCRATCH"

# Ir para o projeto

echo "===== Verificando images ====="
podman images

echo "===== Copiando pra SCRATCH ====="
mkdir -p "$SCRATCH/otimizadorMIP-2026"
cp -r $HOME/otimizadorMIP-2026/* $SCRATCH/otimizadorMIP-2026/

echo "===== Iniciando execucao ====="

podman run --rm \
    -v $SCRATCH/otimizadorMIP-2026:/workspace \
    julia-mip-cplex \
	julia map.jl -r T1 T2 T3 T4
	
echo "===== Copiando pra HOME ====="

cp $SCRATCH/otimizadorMIP-2026/mapa_otimizado_poa* $HOME/otimizadorMIP-2026/