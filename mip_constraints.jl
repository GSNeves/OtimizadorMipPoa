module MIPConstraints

using JuMP
include("util.jl")
using .Util

export build_direction_constraints!, build_circular_order_constraints!, build_crossing_constraints!, build_bend_cost_constraints!, build_relative_position_cost, build_edge_length_cost!

function build_direction_constraints!(model, V, E, x, y, z1, z2, L_MIN, M_BIG, merged_counts)
    # Section 4.1
    # Sets diagonals z1 and z2
    
    dir_vars = Dict()
    alpha_vars = Dict()
    for (edge, routes) in E
        u, v = edge

        # L_MIN dinâmico baseado no número de vértices fundidos
        merged_count = get(merged_counts, edge, 0)
        L_MIN_edge = L_MIN * (merged_count + 1)

        reverse_edge = (v, u)
        
        orig_sector = get_sector(V[u], V[v])
        reverse_sector = get_sector(V[v], V[u])
        
        # Definimos os 3 setores candidatos: [Anterior, Original, Posterior]
        sectors = [(orig_sector - 1 + 8) % 8, orig_sector, (orig_sector + 1) % 8]
        reverse_sectors = [(reverse_sector - 1 + 8) % 8, reverse_sector, (reverse_sector + 1) % 8]
        
        # 4.2 (1)
        alpha = @variable(model, [1:3], Bin)
        @constraint(model, sum(alpha) == 1)
        alpha_vars[edge] = alpha
    
        
        # 4.2 (2)
        dir_var = @variable(model, integer=true, lower_bound=0, upper_bound=7)
        reverse_dir_var = @variable(model, integer=true, lower_bound=0, upper_bound=7)
        @constraint(model, dir_var == sum(sectors[i] * alpha[i] for i in 1:3))
        @constraint(model, reverse_dir_var == sum(reverse_sectors[i] * alpha[i] for i in 1:3))
        dir_vars[edge] = dir_var
        dir_vars[reverse_edge] = reverse_dir_var
        
        # 4.2 (3)
        for i in 1:3
            sec = sectors[i]
            
            # Leste (x cresce, y constante)
            if sec == 0 
                @constraint(model, y[u] - y[v] <= M_BIG * (1 - alpha[i]))
                @constraint(model, y[u] - y[v] >= -M_BIG * (1 - alpha[i]))
                @constraint(model, x[v] - x[u] >= L_MIN_edge - M_BIG * (1 - alpha[i]))
                
            # Nordeste (z1 cresce | z2 constante)
            elseif sec == 1 
                @constraint(model, z2[u] - z2[v] <= M_BIG * (1 - alpha[i]))
                @constraint(model, z2[u] - z2[v] >= -M_BIG * (1 - alpha[i]))
                @constraint(model, z1[v] - z1[u] >= L_MIN_edge - M_BIG * (1 - alpha[i]))
                
            # Norte (x constante, y cresce)
            elseif sec == 2 
                @constraint(model, x[u] - x[v] <= M_BIG * (1 - alpha[i]))
                @constraint(model, x[u] - x[v] >= -M_BIG * (1 - alpha[i]))
                @constraint(model, y[v] - y[u] >= L_MIN_edge - M_BIG * (1 - alpha[i]))
                
            # Noroeste (z2 decresce, z1 constante)
            elseif sec == 3 
                @constraint(model, z1[u] - z1[v] <= M_BIG * (1 - alpha[i]))
                @constraint(model, z1[u] - z1[v] >= -M_BIG * (1 - alpha[i]))
                @constraint(model, z2[u] - z2[v] >= L_MIN_edge - M_BIG * (1 - alpha[i]))
    
            # Oeste (x decresce, y constante)
            elseif sec == 4 
                @constraint(model, y[u] - y[v] <= M_BIG * (1 - alpha[i]))
                @constraint(model, y[u] - y[v] >= -M_BIG * (1 - alpha[i]))
                @constraint(model, x[u] - x[v] >= L_MIN_edge - M_BIG * (1 - alpha[i]))
            
            # Sudoeste (z1 decresce, z2 constante)
            elseif sec == 5
                @constraint(model, z2[u] - z2[v] <= M_BIG * (1 - alpha[i]))
                @constraint(model, z2[u] - z2[v] >= -M_BIG * (1 - alpha[i]))
                @constraint(model, z1[u] - z1[v] >= L_MIN_edge - M_BIG * (1 - alpha[i]))
            
            # Sul (x constante, y decresce)
            elseif sec == 6 
                @constraint(model, x[u] - x[v] <= M_BIG * (1 - alpha[i]))
                @constraint(model, x[u] - x[v] >= -M_BIG * (1 - alpha[i]))
                @constraint(model, y[u] - y[v] >= L_MIN_edge - M_BIG * (1 - alpha[i]))
            
            # Sudeste (z2 cresce, z1 constante)
            elseif sec == 7 
                @constraint(model, z1[u] - z1[v] <= M_BIG * (1 - alpha[i]))
                @constraint(model, z1[u] - z1[v] >= -M_BIG * (1 - alpha[i]))
                @constraint(model, z2[v] - z2[u] >= L_MIN_edge - M_BIG * (1 - alpha[i]))
            end
        end
    end
    
    return alpha_vars, dir_vars
end

function build_circular_order_constraints!(model, V, E, dir_vars)
    # 4.3
    
    # Pega arestas adjacentes
    adj_list = Dict{Int, Vector{Int}}()
    for (edge, _) in E
        u, v = edge
        if !haskey(adj_list, u) adj_list[u] = [] end
        if !haskey(adj_list, v) adj_list[v] = [] end
        push!(adj_list[u], v)
        push!(adj_list[v], u)
    end
    
    #circular_slack_vars = VariableRef[]
    
    for (v, neighbors) in adj_list
        degree = length(neighbors)
        if degree < 2 continue end
        
        # Ordena vizinhos geometricamente (sentido anti-horário)
        sort!(neighbors, by = n -> get_angle_deg(V[v], V[n]))
        
        # 4.3 (4)
        beta = @variable(model, [1:degree], Bin)
        @constraint(model, sum(beta) == 1)
        
        # # 4.3 (5)
        # # Criação das variáveis de folga
        # slack = @variable(model, [1:degree], lower_bound=0)
        # append!(circular_slack_vars, slack) # <--- CAPTURA OS SLACKS AQUI
    
        for i in 1:degree
            u_curr, u_next = neighbors[i], neighbors[(i % degree) + 1]
            dir_curr, dir_next = dir_vars[v, u_curr], dir_vars[v, u_next]
            
            # Restrição com o slack incluído
            @constraint(model, dir_curr <= dir_next - 1 + 8 * beta[i])
        end
    end
    
    # for (v, neighbors) in adj_list
    #     degree = length(neighbors)
    #     if degree < 2 continue end
        
    #     # Ordena vizinhos geometricamente (sentido anti-horário)
    #     sort!(neighbors, by = n -> get_angle_deg(V[v], V[n]))
        
    #     # 4.3 (4)
    #     beta = @variable(model, [1:degree], Bin)
    #     @constraint(model, sum(beta) == 1)
        
    #     # 4.3 (5)
    #     for i in 1:degree
    #         u_curr = neighbors[i]
    #         u_next = neighbors[(i % degree) + 1] 
            
    #         dir_curr = dir_vars[v, u_curr]
    #         dir_next = dir_vars[v, u_next]
            
    #         @constraint(model, dir_curr <= dir_next - 1 + 8 * beta[i])
    #     end
    # end
    
    return adj_list
end

function build_crossing_constraints!(model, V, E, x, y, z1, z2, M_BIG)
    # #4.4 (Mais consome computacionalmente!!)
    # Aproximadamente 50 metros de distância
    LAT_THRESHOLD = 0.00045
    LON_THRESHOLD = 0.00052
    
    # count_h4 = 0
    # edges_list = collect(keys(E))
    # D_MIN = 2
    
    # for (e1, _) in E
    #     for (e2, _) in E
            
    #         u, v = e1
    #         r, s = e2
            
    #         # Verifica se são arestas disjuntas (não compartilham nenhum nó)
    #         if u == r || u == s || v == r || v == s
    #             continue
    #         end
    
    #         (u_lat, u_lon, _) = V[u]
    #         (v_lat, v_lon, _) = V[v]
    #         (r_lat, r_lon, _) = V[r]
    #         (s_lat, s_lon, _) = V[s]
    
    
    #         # Define as "Caixas" (Bounding Boxes) originais
    #         min_lat_1, max_lat_1 = min(u_lat, v_lat), max(u_lat, v_lat)
    #         min_lon_1, max_lon_1 = min(u_lon, v_lon), max(u_lon, v_lon)
            
    #         min_lat_2, max_lat_2 = min(r_lat, s_lat), max(r_lat, s_lat)
    #         min_lon_2, max_lon_2 = min(r_lon, s_lon), max(r_lon, s_lon)
            
    #         # 1. Filtro de Proximidade: Se estiverem muito longe, ignoramos
    #         # (O solver naturalmente não vai puxar uma linha da Zona Sul para a Zona Norte)
    #         dist_lat = max(0.0, min_lat_2 - max_lat_1, min_lat_1 - max_lat_2)
    #         dist_lon = max(0.0, min_lon_2 - max_lon_1, min_lon_1 - max_lon_2)
            
    #         if dist_lat > LAT_THRESHOLD || dist_lon > LON_THRESHOLD
    #             continue
    #         end
    
    #         gamma = @variable(model, [1:8], Bin)
    #         @constraint(model, sum(gamma) >= 1)
    
    #         # NORTE
    #         @constraint(model, y[r] - y[u] <= M_BIG * (1 - gamma[3]) - D_MIN)
    #         @constraint(model, y[r] - y[v] <= M_BIG * (1 - gamma[3]) - D_MIN)
    #         @constraint(model, y[s] - y[u] <= M_BIG * (1 - gamma[3]) - D_MIN)
    #         @constraint(model, y[s] - y[v] <= M_BIG * (1 - gamma[3]) - D_MIN)
    
    #         # SUL
    #         @constraint(model, -y[r] + y[u] <= M_BIG * (1 - gamma[7]) - D_MIN)
    #         @constraint(model, -y[r] + y[v] <= M_BIG * (1 - gamma[7]) - D_MIN)
    #         @constraint(model, -y[s] + y[u] <= M_BIG * (1 - gamma[7]) - D_MIN)
    #         @constraint(model, -y[s] + y[v] <= M_BIG * (1 - gamma[7]) - D_MIN)
    
    #         # LESTE
    #         @constraint(model, x[r] - x[u] <= M_BIG * (1 - gamma[1]) - D_MIN)
    #         @constraint(model, x[r] - x[v] <= M_BIG * (1 - gamma[1]) - D_MIN)
    #         @constraint(model, x[s] - x[u] <= M_BIG * (1 - gamma[1]) - D_MIN)
    #         @constraint(model, x[s] - x[v] <= M_BIG * (1 - gamma[1]) - D_MIN)
    
    #         # OESTE
    #         @constraint(model, -x[r] + x[u] <= M_BIG * (1 - gamma[5]) - D_MIN)
    #         @constraint(model, -x[r] + x[v] <= M_BIG * (1 - gamma[5]) - D_MIN)
    #         @constraint(model, -x[s] + x[u] <= M_BIG * (1 - gamma[5]) - D_MIN)
    #         @constraint(model, -x[s] + x[v] <= M_BIG * (1 - gamma[5]) - D_MIN)
    
    #         # NORDESTE
    #         @constraint(model, z1[r] - z1[u] <= M_BIG * (1 - gamma[2]) - D_MIN)
    #         @constraint(model, z1[r] - z1[v] <= M_BIG * (1 - gamma[2]) - D_MIN)
    #         @constraint(model, z1[s] - z1[u] <= M_BIG * (1 - gamma[2]) - D_MIN)
    #         @constraint(model, z1[s] - z1[v] <= M_BIG * (1 - gamma[2]) - D_MIN)
    
    #         # NOROESTE
    #         @constraint(model, -z2[r] + z2[u] <= M_BIG * (1 - gamma[4]) - D_MIN)
    #         @constraint(model, -z2[r] + z2[v] <= M_BIG * (1 - gamma[4]) - D_MIN)
    #         @constraint(model, -z2[s] + z2[u] <= M_BIG * (1 - gamma[4]) - D_MIN)
    #         @constraint(model, -z2[s] + z2[v] <= M_BIG * (1 - gamma[4]) - D_MIN)
    
    #         # SULDESTE
    #         @constraint(model, z2[r] - z2[u] <= M_BIG * (1 - gamma[8]) - D_MIN)
    #         @constraint(model, z2[r] - z2[v] <= M_BIG * (1 - gamma[8]) - D_MIN)
    #         @constraint(model, z2[s] - z2[u] <= M_BIG * (1 - gamma[8]) - D_MIN)
    #         @constraint(model, z2[s] - z2[v] <= M_BIG * (1 - gamma[8]) - D_MIN)
    
    #         # SULDOESTE
    #         @constraint(model, -z1[r] + z1[u] <= M_BIG * (1 - gamma[6]) - D_MIN)
    #         @constraint(model, -z1[r] + z1[v] <= M_BIG * (1 - gamma[6]) - D_MIN)
    #         @constraint(model, -z1[s] + z1[u] <= M_BIG * (1 - gamma[6]) - D_MIN)
    #         @constraint(model, -z1[s] + z1[v] <= M_BIG * (1 - gamma[6]) - D_MIN)
                 
        
    #         global count_h4 += 33
    #     end
    # end
    # println("Adicionadas $count_h4 restrições de separação para evitar cruzamentos (H4).")
end

function build_bend_cost_constraints!(model, V, E, adj_list, alpha_vars)
    # 4.5
    # TODO REVISAR
    
    bend_cost_vars = VariableRef[]
    
    for v in keys(V)
        # Encontrar arestas conectadas a este nó
        incident_edges = []
        if haskey(adj_list, v)
            for neighbor in adj_list[v]
                # Recupera a chave da aresta (pode ser u,v ou v,u)
                edge_key = haskey(E, (v, neighbor)) ? (v, neighbor) : (neighbor, v)
                push!(incident_edges, (neighbor, edge_key))
            end
        end
    
        # Se for ponta de linha (1 vizinho) ou isolado, não tem curva
        if length(incident_edges) < 2
            continue
        end
    
        # Agrupar por rota: Quais rotas passam por quais arestas?
        # Dict: RouteID -> Lista de Vizinhos conectados por essa rota
        routes_on_node = Dict{Any, Vector{Int}}()
        
        for (neighbor, edge_key) in incident_edges
            # Quais linhas passam nessa aresta?
            if haskey(E, edge_key)
                lines = E[edge_key]
                for line in lines
                    if !haskey(routes_on_node, line)
                        routes_on_node[line] = []
                    end
                    push!(routes_on_node[line], neighbor)
                end
            end
        end
    
        # Calcular penalidade para cada rota que "passa direto" (grau 2 na rota)
        for (line, neighbors) in routes_on_node
            if length(neighbors) == 2
                u = neighbors[1]
                w = neighbors[2]
                
                # Obter direções
                d_in = get_dir_expr(u, v, E, alpha_vars, V)
                d_out = get_dir_expr(v, w, E, alpha_vars, V)
                
                # Variável de custo da curva
                bend = @variable(model, integer=true, lower_bound=0)
                push!(bend_cost_vars, bend)
                
                # Variável auxiliar z para o módulo 8 (pode ser -1, 0 ou 1)
                # Serve para corrigir o salto de 7 para 0 (ex: 7 e 0 tem dist 1)
                z = @variable(model, integer=true, lower_bound=-1, upper_bound=1)
                
                # Diferença angular: delta = d_out - d_in
                # Custo >= |delta - 8z|
                # Isso lineariza o módulo:
                @constraint(model, bend >= (d_out - d_in) - 8 * z)
                @constraint(model, bend >= -((d_out - d_in) - 8 * z))
            end
        end
    end
    
    return bend_cost_vars
end

function build_relative_position_cost(alpha_vars)
    # 4.6
    
    rel_pos_cost_vars = VariableRef[]
    
    for (edge, alpha) in alpha_vars
        # alpha[1] e alpha[3] representam desvio da direção original
        push!(rel_pos_cost_vars, alpha[1])
        push!(rel_pos_cost_vars, alpha[3])
    end
    
    return rel_pos_cost_vars
end

function build_edge_length_cost!(model, E, x, y)
    # 4.7
    
    # # VERSÃO DISTANCIA MANHATTAN ( MAIS RAPIDO )
    # # TROCAR NO OBJETIVO sum(edge_len_cost_vars) por total_len_lin
    # total_length_expr = @expression(model, sum( (x[u] - x[v])^2 + (y[u] - y[v])^2 for ((u,v),_) in E ))
    # total_len_lin = AffExpr(0)
    # for ((u,v), _) in E
    #     # Truque para módulo em minimização: min sum(dx + dy)
    #     # Como x[u], x[v] são variáveis, criamos vars auxiliares dx, dy >= 0
    #     dx = @variable(model, lower_bound=0)
    #     dy = @variable(model, lower_bound=0)
    #     @constraint(model, dx >= x[u] - x[v])
    #     @constraint(model, dx >= x[v] - x[u])
    #     @constraint(model, dy >= y[u] - y[v])
    #     @constraint(model, dy >= y[v] - y[u])
    #     add_to_expression!(total_len_lin, dx + dy)
    # end
    
    # VERSAO DISTANCIA L1--INFINITO ( MAIS LENTA / DO ARTIGO)
    # TROCAR NO OBJETIVO total_len_lin por sum(edge_len_cost_vars)
    edge_len_cost_vars = VariableRef[]
    for ((u,v), _) in E
        # Truque para módulo em minimização: min sum(dx + dy)
        # Como x[u], x[v] são variáveis, criamos vars auxiliares dx, dy >= 0
        edge_length = @variable(model, integer=true, lower_bound=0)
        @constraint(model, edge_length >= x[u] - x[v])
        @constraint(model, edge_length >= x[v] - x[u])
        @constraint(model, edge_length >= y[u] - y[v])
        @constraint(model, edge_length >= y[v] - y[u])
        push!(edge_len_cost_vars, edge_length)
    end
    
    return edge_len_cost_vars
end

end