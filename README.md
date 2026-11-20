# Otimizador MIP para Mapas Esquemáticos de Transporte Público

Este repositório contém o projeto de Trabalho de Conclusão de Curso (TCC) do curso de Ciência da Computação do Instituto de Informática da UFRGS:

> **Otimização Inteira Mista Aplicada à Geração de Mapas Esquemáticos de Redes de Transporte: Um Estudo de Caso sobre o Sistema de Ônibus de Porto Alegre**  
> **Autor:** Gustavo Spellmeier Neves  
> **Orientador:** Prof. Dr. Lucas Mello Schnorr

O projeto implementa um pipeline de pré-processamento e abstração de dados geográficos no padrão **GTFS** (General Transit Feed Specification) da rede de ônibus de Porto Alegre, acoplado a um modelo de **Programação Inteira Mista (MIP)** em grade octilinear para geração automatizada de mapas esquemáticos.

---

## Estrutura do Projeto

* **`map.jl`**: Script principal que constrói e resolve o modelo MIP (via JuMP e CPLEX), executando também o loop iterativo de separação de vértices não-adjacentes e pós-processamento.
* **`data_parser.jl`**: Leitura dos arquivos GTFS (`arquivo-gtfs/`), construção do grafo de traçado (*shapes*) com projeção (*snapping*) das paradas, fusão de vértices próximos e contração de caminhos colineares.
* **`mip_constraints.jl`**: Definição das restrições e funções objetivo do modelo MIP (restrições octilineares, ordem circular, custo de dobras, posição relativa e comprimento de arestas).
* **`gtfs_to_xml.jl`**: Utilitário para exportar o grafo geográfico pré-processado (sem otimização MIP) diretamente para o formato `.graphml`.
* **`graphml_parser.jl`**: Parser para leitura de grafos de entrada no formato `.graphml`.
* **`util.jl`**: Funções auxiliares geométricas (cálculo de setores octilineares, distância de Haversine, projeção ponto-segmento, interseção de segmentos e reexpansão de paradas contraídas).
* **`plotter.jl`**: Módulo de geração de visualizações estáticas utilizando `Plots.jl`.
* **`arquivo-gtfs/`**: Conjunto de dados GTFS da rede de transporte público de Porto Alegre.
* **`scripts-PCAD/`**: `Dockerfile` e scripts Slurm utilizados para execução do modelo no cluster de computação de alto desempenho (PCAD/UFRGS).
* **`tcc-latex/`**: Código-fonte em LaTeX da monografia do TCC.
* **`slides/`**: Código-fonte em LaTeX (Beamer) dos slides de apresentação da defesa.

---

## Pré-requisitos

* **Julia** (recomendado $\ge$ 1.10)
* **IBM ILOG CPLEX Optimization Studio** instalado e configurado no sistema
* Pacotes Julia necessários:
  ```julia
  using Pkg
  Pkg.add(["JuMP", "CPLEX", "ArgParse", "CSV", "DataFrames", "EzXML", "Plots"])
  ```

---

## Como Executar

### 1. Gerar o mapa geográfico de entrada (sem otimização)

Converte os dados GTFS pré-processados em um arquivo `.graphml`, útil para inspeção da malha inicial ou comparação com o mapa esquemático otimizado:

```bash
julia gtfs_to_xml.jl [argumentos]
```

**Argumentos opcionais:**
* `-c, --colors <cor1> <cor2> ...`: Filtra as rotas pelas cores em formato hexadecimal das bacias do GTFS (ex.: `FF0000`, `0000FF`, `008000`, `CC7722`).
* `-r, --routes <rota1> <rota2> ...`: Filtra as rotas pelos nomes curtos das linhas (ex.: `T1 T2 T3`).
* `-s, --single-route-per-edge`: Exporta apenas uma rota por aresta para visualização simplificada.

### 2. Executar o otimizador MIP

Executa o modelo de otimização inteira mista para gerar o mapa esquemático octilinear:

```bash
julia map.jl [argumentos]
```

**Argumentos opcionais:**
* `-c, --colors <cor1> <cor2> ...`: Filtra as rotas pelas cores em formato hexadecimal (ex.: `FF0000`).
* `-r, --routes <rota1> <rota2> ...`: Filtra as rotas pelos nomes curtos (ex.: `T1 T2`).

**Saída:**
* Arquivos `.graphml` correspondentes a cada iteração do modelo (`mapa_otimizado_poa_iter<N>.graphml`).
* Arquivos finais com as paradas intermediárias reexpandidas (`mapa_final_expandido_single.graphml` e `mapa_final_expandido_multiple.graphml`).
