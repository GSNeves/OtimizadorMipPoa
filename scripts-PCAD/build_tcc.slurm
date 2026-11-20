#!/bin/bash
#SBATCH --job-name=Build_MIP_Image
#SBATCH --partition=cidia
#SBATCH --nodes=1
#SBATCH --ntasks=1
#SBATCH --cpus-per-task=8
#SBATCH --time=04:00:00
#SBATCH --output=build_%j.out
#SBATCH --error=build_%j.err

echo "--- Iniciando o Job de Otimização ---"

echo "Copiando os dados para o diretório SCRATCH..."
mkdir -p $SCRATCH/otimizadorMIP-2026
# Agora que tudo está dentro da pasta otimizadorMIP-2026, isso copia o projeto 100% completo
cp -r $HOME/otimizadorMIP-2026/* $SCRATCH/otimizadorMIP-2026/

cd $SCRATCH/otimizadorMIP-2026

echo "Construindo a imagem OCI com Julia e CPLEX via Podman..."
podman build -t julia-mip-cplex .

echo "--- Fim do Job ---"