# Usa a imagem oficial do Julia com a versão 1.12.4 solicitada
FROM docker.io/library/julia:1.12.4

# Atualiza os pacotes e instala dependências básicas de sistema
#RUN apt-get update && apt-get install -y \
#    build-essential \
#    && rm -rf /var/lib/apt/lists/*

# Define o diretório de trabalho inicial no container
WORKDIR /workspace

# ---> A SOLUÇÃO DA RESTRIÇÃO DO PCAD <---
# Diz para o instalador do CPLEX usar a nossa pasta de trabalho para 
# arquivos temporários, fugindo da pasta /tmp que é bloqueada pelo Podman
#ENV IATEMPDIR=/workspace

# Copia os arquivos direto para o /workspace
COPY cplex*studio*.bin ./cplex_installer.bin
COPY response.properties ./response.properties

# Dá permissão, higieniza o arquivo por segurança e executa a instalação
# OBRIGATORIAMENTE usando caminhos absolutos (/workspace/...)
RUN chmod +x /workspace/cplex_installer.bin && \
    sed -i 's/\r$//' /workspace/response.properties && \
    GLIBC_TUNABLES=glibc.rtld.execstack=2 /workspace/cplex_installer.bin -f /workspace/response.properties && \
    rm /workspace/cplex_installer.bin /workspace/response.properties

# Configura as variáveis de ambiente obrigatórias para o pacote CPLEX.jl encontrar o solver
ENV CPLEX_STUDIO_BINARIES=/opt/ibm/ILOG/CPLEX_Studio222/cplex/bin/x86-64_linux
ENV LD_LIBRARY_PATH=/opt/ibm/ILOG/CPLEX_Studio222/cplex/bin/x86-64_linux:$LD_LIBRARY_PATH

# Instala as bibliotecas Julia manualmente
RUN julia -e 'using Pkg; Pkg.add(["JuMP", "CPLEX", "Plots", "CSV", "DataFrames", "EzXML", "ArgParse"]); Pkg.precompile();'

# Copia todo o código do seu projeto para o /workspace
# COPY . .

# Comando padrão executado quando o container iniciar
CMD ["julia", "map.jl"]
