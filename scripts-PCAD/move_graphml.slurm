#!/bin/bash
#SBATCH --job-name=move-graphml
#SBATCH --partition=cidia
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=02:00:00
#SBATCH --output=move_%j.out
#SBATCH --error=move_%j.err

set -euo pipefail

echo "===== Informações do Job ====="
echo "Job ID: $SLURM_JOB_ID"
echo "Node: $(hostname)"
echo "Scratch: $SCRATCH"
	
echo "===== Copiando pra HOME ====="

cp $SCRATCH/otimizadorMIP-2026/mapa_otimizado_poa* $HOME/otimizadorMIP-2026/