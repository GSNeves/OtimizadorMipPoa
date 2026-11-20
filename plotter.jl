module Plotter

using JuMP
using Plots

export generate_visualization

function generate_visualization(V, E, L, x, y, export_to_graphml)
    println("Solução encontrada! Gerando mapa...")

    # Configuração da área de desenho
    p = plot(legend=false, aspect_ratio=:equal, grid=false, axis=false, 
             size=(1200, 1000), bg=:white, title="Mapa Esquemático - Porto Alegre")
    
    # Iterar sobre as arestas para desenhar as linhas
    for (edge, routes) in E
        u, v = edge
        
        # Recupera as coordenadas OTIMIZADAS (Inteiras)
        x1, y1 = value(x[u]), value(y[u])
        x2, y2 = value(x[v]), value(y[v])
        
        # Recupera a cor da rota principal desta aresta
        route_id = first(routes) # Pega qualquer rota que passa aqui para definir a cor
        color_hex = "000000" # Preto padrão
        
        if haskey(L, route_id)
            # L[route_id] = (cor, nome)
            c_str = L[route_id][1]
            if !isempty(c_str)
                color_hex = c_str
            end
        end
        
        # Desenha o segmento de linha
        plot!(p, [x1, x2], [y1, y2], color="#$color_hex", linewidth=2, alpha=0.8)
    end
    
    # Desenhar os pontos das estações
    x_nodes = [value(x[v]) for v in keys(V)]
    y_nodes = [value(y[v]) for v in keys(V)]
    scatter!(p, x_nodes, y_nodes, markercolor=:black, markersize=1.5, markerstrokewidth=0)
    
    # Salvar o resultado
    output_file = "mapa_otimizado_poa.png"
    savefig(p, output_file)
    println("Mapa salvo com sucesso em: $output_file")
    
    # Exportar GraphML
    optimized_V = Dict{Int, Tuple{Float64, Float64, String}}()
    for (v, (_, _, name)) in V
        optimized_V[v] = (Float64(value(y[v])), Float64(value(x[v])), name)
    end
    export_to_graphml(optimized_V, E, L; filename="mapa_otimizado_poa_single.graphml", single_route_per_edge=true)
    export_to_graphml(optimized_V, E, L; filename="mapa_otimizado_poa_multiple.graphml", single_route_per_edge=false)
end

end