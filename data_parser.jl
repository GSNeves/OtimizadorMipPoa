module DataParser

using CSV
using DataFrames

include("util.jl")
using .Util

export load_gtfs_data, vertices, edges_coverage

# ---------------------------------------------------------------------------
# Ponto de entrada principal
# ---------------------------------------------------------------------------

function load_gtfs_data(; target_colors = [], target_routes = [])
    data_dir = @__DIR__
    gtfs_dir = joinpath(data_dir, "arquivo-gtfs/")

    df_stops = CSV.read(joinpath(gtfs_dir, "stops.txt"), DataFrame)
    df_routes = CSV.read(joinpath(gtfs_dir, "routes.txt"), DataFrame)
    df_trips = CSV.read(joinpath(gtfs_dir, "trips.txt"), DataFrame)
    df_stoptimes = CSV.read(joinpath(gtfs_dir, "stop_times.txt"), DataFrame)
    df_shapes = CSV.read(joinpath(gtfs_dir, "shapes.txt"), DataFrame)

    println("Dados carregados. Processando grafo...")

    # --- GRAFO DE PARADAS (STOPS) ---
    # Dicionário: stop_id => (latitude, longitude, nome). Este é o grafo "como era antes".
    vertices_stops = Dict{Int, Tuple{Float64, Float64, String}}()
    for row in eachrow(df_stops)
        vertices_stops[row.stop_id] = (row.stop_lat, row.stop_lon, row.stop_name)
    end

    # --- GRAFO DE SHAPES (BACKBONE) ---
    # Este será o grafo principal sobre o qual as otimizações serão feitas.
    vertices_shapes = Dict{Int, Tuple{Float64, Float64, String}}()
    edges_coverage_shapes = Dict{Tuple{Int, Int}, Set{Any}}()

    # Juntamos trips com stop_times para saber qual rota é de qual parada
    trip_cols = [:trip_id, :route_id, :direction_id, :shape_id]
    trips_small = select(df_trips, trip_cols)
    stoptimes_small = select(df_stoptimes, :trip_id, :stop_id, :stop_sequence)
    data_merged = innerjoin(stoptimes_small, trips_small, on = :trip_id)

    active_routes = Set(data_merged.route_id)

    # --- LINHAS (L) ---
    # Dicionário: route_id => (cor, nome_curto)
    routes_info = Dict{Any, Tuple{String, String}}()
    for row in eachrow(df_routes)
        if !isempty(target_colors) && !(string(row.route_color) in target_colors)
            continue
        end
        if !isempty(target_routes) && !(string(row.route_short_name) in target_routes)
            continue
        end
        if !(row.route_id in active_routes)
            continue
        end

        color = ismissing(row.route_color) ? "000000" : row.route_color
        routes_info[row.route_id] = (color, string(row.route_short_name))
    end

    # stop_sequence indica a ordem das paradas
    sort!(data_merged, [:trip_id, :stop_sequence])

    println("Processando conexões das viagens...")

    sort!(df_shapes, [:shape_id, :shape_pt_sequence])
    grouped_shapes = groupby(df_shapes, :shape_id)
    shapes_map = Dict(g[1, :shape_id] => g for g in grouped_shapes)

    # Mapeia shape_id para as rotas que o utilizam (apenas ida, direction_id == 0)
    target_dir = ["0"]
    shape_to_routes_map = Dict{Any, Set{Any}}()
    unique_trips = unique(select(data_merged, [:route_id, :direction_id, :shape_id]))
    for trip_info in eachrow(unique_trips)
        route = trip_info.route_id
        if !haskey(routes_info, route)
            continue
        end
        if !(string(trip_info.direction_id) in target_dir)
            continue
        end

        shape_id = trip_info.shape_id
        if !haskey(shape_to_routes_map, shape_id)
            shape_to_routes_map[shape_id] = Set{Any}()
        end
        push!(shape_to_routes_map[shape_id], route)
    end

    # Garante que os IDs dos nós dos shapes não colidam com os IDs das paradas
    max_stop_id = isempty(vertices_stops) ? 0 : maximum(keys(vertices_stops))
    next_node_id = max_stop_id + 1
    coord_to_shape_node_id = Dict{Tuple{Float64, Float64}, Int}()

    for (shape_id, routes) in shape_to_routes_map # Este loop constrói o backbone
        if !haskey(shapes_map, shape_id)
            continue
        end

        shape_points = shapes_map[shape_id]
        last_node_id = -1

        for i in 1:nrow(shape_points)
            row = shape_points[i, :]
            pt_coord = (row.shape_pt_lat, row.shape_pt_lon)

            current_node_id = get(coord_to_shape_node_id, pt_coord, -1)
            if current_node_id == -1
                current_node_id = next_node_id
                vertices_shapes[current_node_id] = (pt_coord[1], pt_coord[2], "") # Shape points não têm nome
                coord_to_shape_node_id[pt_coord] = current_node_id
                next_node_id += 1
            end

            if last_node_id != -1 && last_node_id != current_node_id
                edge = (min(last_node_id, current_node_id), max(last_node_id, current_node_id))
                if !haskey(edges_coverage_shapes, edge)
                    edges_coverage_shapes[edge] = Set{Any}()
                end
                union!(edges_coverage_shapes[edge], routes)
            end
            last_node_id = current_node_id
        end
    end

    # --- CONSTRUÇÃO DO GRAFO DE PARADAS ---
    edges_coverage_stops = Dict{Tuple{Int, Int}, Set{Any}}()

    println("Construindo grafo a partir de conexões diretas entre paradas.")
    grouped_trips = groupby(data_merged, :trip_id)
    for trip in grouped_trips
        route = trip[1, :route_id]
        if !haskey(routes_info, route)
            continue
        end
        if !(string(trip.direction_id[1]) in target_dir)
            continue
        end

        stops = trip.stop_id
        for i in 1:(length(stops)-1)
            u, v = stops[i], stops[i+1]
            if u == v
                continue
            end

            edge = (min(u, v), max(u, v))
            if !haskey(edges_coverage_stops, edge)
                edges_coverage_stops[edge] = Set{Any}()
            end
            push!(edges_coverage_stops[edge], route)
        end
    end

    vertices_stops, edges_coverage_stops = remove_long_edges!(vertices_stops, edges_coverage_stops, max_dist=2000.0)
    add_manual_edge!(vertices_stops, edges_coverage_stops, routes_info, "Cristiano Kraemer 5016 ", "Cristiano Kraemer Df 3553 ", ["2811", "281", "2814", "2813"])
    add_manual_edge!(vertices_stops, edges_coverage_stops, routes_info, "Gen Jonathas Borges Fortes Sn ", "Gen Jonathas Borges Fortes Df 577 ", ["25612"])
    add_manual_edge!(vertices_stops, edges_coverage_stops, routes_info, "Intendente Alfredo Azevedo Df 501 ", "Gen Jonathas Borges Fortes Df 577 ", ["25613"])
    add_manual_edge!(vertices_stops, edges_coverage_stops, routes_info, "G Jardim Passo Das Pedras Ii 172 ", "Mil Setecentos Seis 1700 Ef Condominio Topazio", ["4292"])

    stop_active_nodes = Set{Int}()
    for (u, v) in keys(edges_coverage_stops)
        push!(stop_active_nodes, u)
        push!(stop_active_nodes, v)
    end
    filter!(p -> p.first in stop_active_nodes, vertices_stops)

    println("Tamanho de vertices_stops: ", length(vertices_stops))

    # Inicializa o contador de paradas fundidas por aresta e o rastreador
    # dos caminhos de paradas fundidas
    merged_counts = Dict{Tuple{Int, Int}, Int}()
    merged_paths = Dict{Tuple{Int, Int}, Vector{Int}}()

    # --- SIMPLIFICAÇÃO DO BACKBONE DE SHAPES ---
    vertices_shapes, edges_coverage_shapes = snap_vertices_to_edges!(vertices_shapes, edges_coverage_shapes, 15.0)
    vertices_shapes, edges_coverage_shapes = merge_close_vertices!(vertices_shapes, edges_coverage_shapes, false, distance_threshold=15.0)

    # --- SNAP DE PARADAS PARA O GRAFO DE SHAPES ---
    # Projeta as paradas (vertices_stops) para a aresta mais próxima no grafo de traçado (shapes).
    # Isso insere as paradas como novos vértices no traçado, preservando seus nomes.
    snap_stops_to_shapes!(vertices_shapes, edges_coverage_shapes, vertices_stops;
                       snap_threshold=110.0,
                       edges_coverage_stops=edges_coverage_stops)

    # Remove os nós de shape intermediários (grau 2, sem nome) para simplificar o grafo
    vertices_shapes, edges_coverage_shapes = remove_adjacent_shape_nodes!(vertices_shapes, edges_coverage_shapes)
    compare_graphs(vertices_stops, edges_coverage_stops, vertices_shapes, edges_coverage_shapes)

    # --- ABSTRAÇÕES E SIMPLIFICAÇÕES ---
    vertices = vertices_shapes
    edges_coverage = edges_coverage_shapes

    # Guarda uma cópia de todos os vértices (paradas + pontos de shape) antes das simplificações
    all_vertices = copy(vertices)

    # Etapas opcionais/desabilitadas, mantidas como referência:
    # edges_coverage, routes_info = remove_highly_forked_routes!(edges_coverage, routes_info)

    # Fundindo paradas que estão muito próximas (independe do nome da parada)
    vertices, edges_coverage = merge_close_vertices!(vertices, edges_coverage, false, distance_threshold=20.0)
    vertices, edges_coverage = snap_vertices_to_edges!(vertices, edges_coverage, 40.0)

    # Remove paradas que formam uma reta no mapa
    vertices, edges_coverage, merged_counts, merged_paths = remove_adjacent_vertices(vertices, edges_coverage, merged_counts, merged_paths, 150.0)

    # Limpeza final para remover paradas que possam ter ficado isoladas pelas simplificações
    active_nodes = Set{Int}()
    for (u, v) in keys(edges_coverage)
        push!(active_nodes, u)
        push!(active_nodes, v)
    end
    filter!(p -> p.first in active_nodes, vertices)

    print_graph_info(vertices, edges_coverage)

    return vertices, edges_coverage, routes_info, all_vertices, merged_counts, merged_paths
end

# ---------------------------------------------------------------------------
# Diagnóstico do grafo
# ---------------------------------------------------------------------------

function print_graph_info(vertices, edges_coverage)
    nodes_count = length(vertices)
    edges_count = length(edges_coverage)
    println("Grafo construído com sucesso!")
    println("Número de Nós (Paradas): $nodes_count")
    println("Número de Arestas (Trechos): $edges_count")

    println("\n--- ANÁLISE DE COMPLEXIDADE DO GRAFO ---")
    max_degree = 0
    problematic_node = -1
    degree_by_node = Dict{Int, Int}()

    for (u, v) in keys(edges_coverage)
        degree_by_node[u] = get(degree_by_node, u, 0) + 1
        degree_by_node[v] = get(degree_by_node, v, 0) + 1
    end

    count_high_degree = 0
    high_degree_nodes = []
    for (node, degree) in degree_by_node
        if degree > max_degree
            max_degree = degree
            problematic_node = node
        end
        if degree > 4
            count_high_degree += 1
            v_data = get(vertices, node, (0.0, 0.0, "Desconhecido"))
            node_name = v_data[3]
            push!(high_degree_nodes, (node, node_name, degree, v_data[1], v_data[2]))
        end
    end

    println("Grau máximo do grafo: $max_degree (No vértice $problematic_node)")
    println("Número de nós com grau > 4: $count_high_degree")
    if count_high_degree > 0
        println("Nós com grau > 4:")
        for (id, name, degree, lat, lon) in sort(high_degree_nodes, by = x -> x[3], rev = true)
            println("  📍 [$id] $name (Grau: $degree) | Coordenadas: ($lon, $lat)")
        end
    end

    if max_degree > 8
        println("🚨 ALERTA CRÍTICO: Impossível resolver! O modelo octilinear suporta no máximo grau 8.")
    elseif max_degree > 5
        println("⚠️ AVISO: Nós com grau 6 ou 7 são EXTREMAMENTE difíceis para o CPLEX resolver com restrição de Ordem Circular.")
    end
    println("----------------------------------------\n")
end

function compare_graphs(V_stops, E_stops, V_shapes, E_shapes)
    S_stops = stops_per_route(V_stops, E_stops)
    S_shapes = stops_per_route(V_shapes, E_shapes)

    missing_stops = 0
    total_stops = 0

    for (route, stops) in S_stops
        println("Rota: $route")
        shape_stops = S_shapes[route]
        for stop in stops
            if !in(stop, shape_stops)
                missing_stops += 1
            end
            total_stops += 1
        end
    end

    if total_stops > 0
        percentage = (missing_stops / total_stops) * 100
        println("Paradas faltando: $missing_stops de $total_stops ($(round(percentage, digits=2))%)")
    else
        println("Nenhuma parada para comparar.")
    end
end

function stops_per_route(vertices, edges_coverage)
    # Route -> Lista de Paradas
    stops_per_route = Dict{Any, Set{String}}()

    for ((u, v), routes) in edges_coverage
        u_data = get(vertices, u, (0.0, 0.0, "Desconhecido"))
        u_name = u_data[3]

        v_data = get(vertices, v, (0.0, 0.0, "Desconhecido"))
        v_name = v_data[3]

        for route in routes
            # get! é uma forma idiomática de fazer isso:
            # Pega o Set para a rota, ou cria um novo Set vazio se a rota não existir.
            route_stops = get!(stops_per_route, route, Set{String}())
            if u_name != "" && u_name != "Desconhecido"
                push!(route_stops, u_name)
            end
            if v_name != "" && v_name != "Desconhecido"
                push!(route_stops, v_name)
            end
        end
    end

    return stops_per_route
end

# ---------------------------------------------------------------------------
# Simplificação do grafo
# ---------------------------------------------------------------------------


function snap_vertices_to_edges!(vertices, edges_coverage, distance_threshold)
    println("Snapping paradas para as arestas (Distância <= $(distance_threshold)m)...")
    splits_count = 0

    # Identifica paradas que são "Fim de Linha" (Terminais) ou isoladas.
    # Um vértice é terminal se for a extremidade de alguma rota (grau 1 nela).
    route_degrees = Dict{Any, Dict{Int, Int}}()
    graph_degrees = Dict{Int, Int}()

    for ((u, v), routes) in edges_coverage
        graph_degrees[u] = get(graph_degrees, u, 0) + 1
        graph_degrees[v] = get(graph_degrees, v, 0) + 1
        for r in routes
            if !haskey(route_degrees, r)
                route_degrees[r] = Dict{Int, Int}()
            end
            route_degrees[r][u] = get(route_degrees[r], u, 0) + 1
            route_degrees[r][v] = get(route_degrees[r], v, 0) + 1
        end
    end

    terminals_and_isolated = Set{Int}()
    for w in keys(vertices)
        if get(graph_degrees, w, 0) == 0
            push!(terminals_and_isolated, w)
        end
    end
    for degrees in values(route_degrees)
        for (node, deg) in degrees
            if deg == 1
                push!(terminals_and_isolated, node)
            end
        end
    end

    edges_to_remove = Tuple{Int, Int}[]
    edges_to_add = Dict{Tuple{Int, Int}, Set{Any}}()

    for (edge, routes) in edges_coverage
        u, v = edge

        lat_u, lon_u, _ = vertices[u]
        lat_v, lon_v, _ = vertices[v]

        # Bounding box para filtrar vértices muito distantes e economizar cálculos
        deg_lat_margin = distance_threshold / 111000.0
        deg_lon_margin = distance_threshold / (111000.0 * cos(lat_u * π / 180))

        lat_min = min(lat_u, lat_v) - deg_lat_margin
        lat_max = max(lat_u, lat_v) + deg_lat_margin
        lon_min = min(lon_u, lon_v) - deg_lon_margin
        lon_max = max(lon_u, lon_v) + deg_lon_margin

        snapped_nodes = Tuple{Int, Float64}[]

        for (w, (lat_w, lon_w, _)) in vertices
            if w == u || w == v
                continue
            end

            # Não faz snap para paradas que são fim de linha (para qualquer rota) ou isoladas
            if w in terminals_and_isolated
                continue
            end

            # Verifica a bounding box
            if lat_w < lat_min || lat_w > lat_max || lon_w < lon_min || lon_w > lon_max
                continue
            end

            dist, t = point_to_segment_dist(lat_w, lon_w, lat_u, lon_u, lat_v, lon_v)

            # Para evitar loops infinitos ou anomalias nos extremos,
            # garantimos que a projeção caia estritamente no meio do segmento
            if dist <= distance_threshold && t > 0.01 && t < 0.99
                push!(snapped_nodes, (w, t))
            end
        end

        if isempty(snapped_nodes)
            continue
        end

        # Ordena os nós pelo t (projeção ao longo de U -> V) para manter a sequência certa
        sort!(snapped_nodes, by = x -> x[2])
        push!(edges_to_remove, edge)

        curr_node = u
        for (w, _) in snapped_nodes
            new_edge = (min(curr_node, w), max(curr_node, w))
            if !haskey(edges_to_add, new_edge)
                edges_to_add[new_edge] = copy(routes)
            else
                union!(edges_to_add[new_edge], routes)
            end
            curr_node = w
        end

        # Última aresta: W_last -> V
        last_edge = (min(curr_node, v), max(curr_node, v))
        if !haskey(edges_to_add, last_edge)
            edges_to_add[last_edge] = copy(routes)
        else
            union!(edges_to_add[last_edge], routes)
        end

        splits_count += length(snapped_nodes)
    end

    for e in edges_to_remove
        delete!(edges_coverage, e)
    end
    for (e, routes) in edges_to_add
        if !haskey(edges_coverage, e)
            edges_coverage[e] = routes
        else
            union!(edges_coverage[e], routes)
        end
    end

    println("Snap concluído! $splits_count vértices foram adicionados no meio das arestas.")
    return vertices, edges_coverage
end


function remove_adjacent_vertices(vertices, edges_coverage, merged_counts, merged_paths, angle_threshold)
    println("Removendo paradas intermediárias em retas")
    changed = true
    removed_count = 0

    while changed
        changed = false

        # Cria uma lista de adjacência
        adj_list = Dict{Int, Set{Int}}()
        for (u, v) in keys(edges_coverage)
            if !haskey(adj_list, u)
                adj_list[u] = Set{Int}()
            end
            if !haskey(adj_list, v)
                adj_list[v] = Set{Int}()
            end
            push!(adj_list[u], v)
            push!(adj_list[v], u)
        end

        for v in keys(vertices)
            neighbors = get(adj_list, v, Set{Int}())

            # Apenas vértices que são "meio de caminho"
            if length(neighbors) != 2
                continue
            end

            neighbors_arr = collect(neighbors)
            u, w = neighbors_arr[1], neighbors_arr[2]

            # Chaves de aresta usam padrão min e max
            edge_in_key = (min(u, v), max(u, v))
            edge_out_key = (min(v, w), max(v, w))

            edge_in = edges_coverage[edge_in_key]
            edge_out = edges_coverage[edge_out_key]

            # Nota: originalmente havia aqui uma checagem `edge_in == edge_out`
            # (exigir que as duas arestas tivessem exatamente o mesmo conjunto de
            # rotas antes de fundir); ela está desativada de propósito no código
            # atual, então a fusão só depende do ângulo calculado abaixo.

            u_lat, u_lon, _ = vertices[u]
            v_lat, v_lon, _ = vertices[v]
            w_lat, w_lon, _ = vertices[w]

            u_coords = (u_lat, u_lon)
            v_coords = (v_lat, v_lon)
            w_coords = (w_lat, w_lon)

            if u_coords == v_coords || w_coords == v_coords
                continue
            end

            # Reutiliza get_angle_deg do util.jl para achar o ângulo interno
            angle_u = get_angle_deg(v_coords, u_coords)
            angle_w = get_angle_deg(v_coords, w_coords)

            angle_deg = abs(angle_u - angle_w)
            angle_deg = angle_deg > 180.0 ? 360.0 - angle_deg : angle_deg

            # Caso o ângulo formado pelas 3 paradas seja próximo de uma reta
            if !(angle_deg > angle_threshold || angle_deg < 80.0)
                continue
            end

            # Chave de aresta usa padrão min e max
            new_edge_key = (min(u, w), max(u, w))

            # Contabiliza o número de paradas fundidas para a nova aresta
            merged_counts[new_edge_key] = get(merged_counts, new_edge_key, 0) +
                                           get(merged_counts, edge_in_key, 0) +
                                           get(merged_counts, edge_out_key, 0) + 1

            # Constrói o caminho de paradas fundidas para a nova aresta
            path_in = get(merged_paths, edge_in_key, [u, v])
            path_out = get(merged_paths, edge_out_key, [v, w])

            # Orienta os caminhos para u -> v e v -> w
            if !isempty(path_in) && path_in[end] != v
                path_in = reverse(path_in)
            end
            if !isempty(path_out) && path_out[1] != v
                path_out = reverse(path_out)
            end

            # Combina os caminhos: u -> ... -> v -> ... -> w
            merged_paths[new_edge_key] = [path_in[1:end-1]; path_out]

            delete!(merged_counts, edge_in_key)
            delete!(merged_counts, edge_out_key)
            delete!(merged_paths, edge_in_key)
            delete!(merged_paths, edge_out_key)

            if !haskey(edges_coverage, new_edge_key)
                edges_coverage[new_edge_key] = copy(edge_in)
            else
                union!(edges_coverage[new_edge_key], edge_in)
            end

            delete!(edges_coverage, edge_in_key)
            delete!(edges_coverage, edge_out_key)
            delete!(vertices, v)

            removed_count += 1
            changed = true
            break
        end
    end

    println("Simplificação concluída! $removed_count paradas em linha reta foram removidas.")
    return vertices, edges_coverage, merged_counts, merged_paths
end


function merge_close_vertices!(vertices, edges_coverage, compare_names; distance_threshold=50.0)
    println("Iniciando mesclagem de paradas próximas (Distância <= $(distance_threshold)m)...")

    # Pré-calcula o máximo de rotas passando por qualquer aresta incidente a cada vértice
    max_routes_per_vertex = Dict{Int, Int}(k => 0 for k in keys(vertices))
    for ((u, v), routes) in edges_coverage
        n_routes = length(routes)
        if haskey(max_routes_per_vertex, u)
            max_routes_per_vertex[u] = max(max_routes_per_vertex[u], n_routes)
        end
        if haskey(max_routes_per_vertex, v)
            max_routes_per_vertex[v] = max(max_routes_per_vertex[v], n_routes)
        end
    end

    # Estrutura Union-Find: cada parada inicialmente aponta para ela mesma
    uf = Dict{Int, Int}(k => k for k in keys(vertices))

    function find_root(i)
        if uf[i] == i
            return i
        end
        uf[i] = find_root(uf[i])
        return uf[i]
    end

    function union_nodes(i, j)
        root_i = find_root(i)
        root_j = find_root(j)
        if root_i == root_j
            return
        end

        # Pega os nomes dos vértices raiz para a decisão
        name_i = vertices[root_i][3]
        name_j = vertices[root_j][3]

        # Critério de prioridade:
        # 1. Se um tem nome e o outro não, o que tem nome vence.
        # 2. Se ambos têm (ou não têm) nome, usa o critério de contagem de rotas.
        i_wins = if !isempty(name_i) && isempty(name_j)
            true
        elseif isempty(name_i) && !isempty(name_j)
            false
        else
            max_routes_per_vertex[root_i] >= max_routes_per_vertex[root_j]
        end

        if i_wins
            uf[root_j] = root_i
            max_routes_per_vertex[root_i] = max(max_routes_per_vertex[root_i], max_routes_per_vertex[root_j])
        else
            uf[root_i] = root_j
            max_routes_per_vertex[root_j] = max(max_routes_per_vertex[root_i], max_routes_per_vertex[root_j])
        end
    end

    v_ids = collect(keys(vertices))
    n = length(v_ids)

    # Extrai os dados em vetores sequenciais para o loop quadrático rodar "voando"
    prefixes = [first(lowercase(vertices[u][3]), min(6, length(vertices[u][3]))) for u in v_ids]
    lats = [vertices[u][1] for u in v_ids]
    lons = [vertices[u][2] for u in v_ids]

    # Compara todos os pares
    for i in 1:n
        u = v_ids[i]
        lat1, lon1 = lats[i], lons[i]
        pref1 = prefixes[i]

        for j in (i+1):n
            v = v_ids[j]

            # Poda: se já pertencem ao mesmo nó (foram unidas antes), ignora
            if find_root(u) == find_root(v)
                continue
            end

            # Verifica prefixo antes de fazer a conta pesada de latitude/longitude
            if !compare_names || (compare_names && pref1 == prefixes[j])
                dist = haversine_dist(lat1, lon1, lats[j], lons[j])
                if dist <= distance_threshold
                    union_nodes(u, v)
                end
            end
        end
    end

    # Aplica a mesclagem nas arestas
    new_edges_coverage = Dict{Tuple{Int, Int}, Set{Any}}()
    for ((u, v), routes) in edges_coverage
        new_u = find_root(u)
        new_v = find_root(v)

        # Se as duas pontas da aresta foram fundidas na mesma parada, ignoramos
        if new_u == new_v
            continue
        end

        # Garante que a aresta continua ordenada (min, max) para não duplicar no grafo
        new_edge = (min(new_u, new_v), max(new_u, new_v))
        if !haskey(new_edges_coverage, new_edge)
            new_edges_coverage[new_edge] = Set{Any}()
        end
        # Junta as linhas de ônibus que passavam nas arestas velhas para a aresta nova
        union!(new_edges_coverage[new_edge], routes)
    end

    # Deleta do dicionário os vértices que foram fundidos
    merged_count = 0
    for u in v_ids
        if find_root(u) != u
            delete!(vertices, u)
            merged_count += 1
        end
    end

    # Substitui as antigas conexões pelas novas conexões mescladas
    empty!(edges_coverage)
    for (k, v) in new_edges_coverage
        edges_coverage[k] = v
    end

    println("Mesclagem concluída! $merged_count paradas foram fundidas no mesmo nó.")
    return vertices, edges_coverage
end


function snap_stops_to_shapes!(
    vertices_shapes::Dict{Int, Tuple{Float64, Float64, String}},
    edges_coverage_shapes::Dict{Tuple{Int, Int}, Set{Any}},
    vertices_stops::Dict{Int, Tuple{Float64, Float64, String}};
    snap_threshold=50.0,
    edges_coverage_stops::Union{Dict{Tuple{Int, Int}, Set{Any}}, Nothing} = nothing
)
    println("Iniciando snap de paradas para as arestas do traçado (Distância <= $(snap_threshold)m)...")

    # --- Priorização por rota ---
    run_diagnostics = edges_coverage_stops !== nothing
    served_routes_per_stop = Dict{Int, Set{Any}}()
    if run_diagnostics
        for ((u, v), routes) in edges_coverage_stops
            union!(get!(served_routes_per_stop, u, Set{Any}()), routes)
            union!(get!(served_routes_per_stop, v, Set{Any}()), routes)
        end
    else
        println("  (edges_coverage_stops não informado — priorização por rota e diagnóstico desativados)")
    end

    diag_matched = 0                 # snap caiu numa aresta de rota compatível (via prioridade ou porque já era a mais próxima)
    diag_fallback_beyond = 0         # nenhuma aresta compatível dentro do threshold, mas ela existe um pouco além
    diag_fallback_no_match = 0       # nenhuma aresta compatível foi encontrada em lugar nenhum
    diag_no_route_info = 0           # parada sem rota conhecida no grafo de stops (não avaliada / sem prioridade aplicada)
    diag_fallback_examples = Tuple{String, Float64, Union{Float64, Nothing}}[]

    # Mapeia cada aresta para uma lista de paradas que podem ser "snapped" a ela.
    # Estrutura: edge => [(stop_id, stop_data, projection_t), ...]
    snaps_per_edge = Dict{Tuple{Int, Int}, Vector{Any}}()

    # 1. Para cada parada, encontrar a melhor aresta do traçado.
    #    Prioridade: a aresta mais próxima cuja rota bate com alguma rota que a parada atende
    for (stop_id, stop_data) in vertices_stops
        stop_lat, stop_lon, stop_name = stop_data
        if isempty(strip(stop_name)) # Apenas paradas com nome
            continue
        end

        served_routes = get(served_routes_per_stop, stop_id, nothing)
        has_route_info = served_routes !== nothing && !isempty(served_routes)

        # Melhor aresta compatível com a rota da parada, dentro do threshold (candidata prioritária)
        best_edge_matching = nothing
        min_dist_matching = snap_threshold
        best_t_matching = -1.0

        # Melhor aresta entre TODAS, dentro do threshold, independente da rota (fallback)
        best_edge_any = nothing
        min_dist_any = snap_threshold
        best_t_any = -1.0

        for (edge, routes) in edges_coverage_shapes
            u, v = edge
            if !haskey(vertices_shapes, u) || !haskey(vertices_shapes, v)
                continue
            end

            u_lat, u_lon, _ = vertices_shapes[u]
            v_lat, v_lon, _ = vertices_shapes[v]

            dist, t = point_to_segment_dist(stop_lat, stop_lon, u_lat, u_lon, v_lat, v_lon)

            if dist < min_dist_any
                min_dist_any = dist
                best_edge_any = edge
                best_t_any = t
            end

            if has_route_info && dist < min_dist_matching && !isempty(intersect(routes, served_routes))
                min_dist_matching = dist
                best_edge_matching = edge
                best_t_matching = t
            end
        end

        # Decisão final: prioriza a aresta compatível com a rota; cai para a mais próxima como fallback
        used_fallback = false
        if has_route_info && best_edge_matching !== nothing
            best_edge, best_t, min_dist = best_edge_matching, best_t_matching, min_dist_matching
        elseif best_edge_any !== nothing
            best_edge, best_t, min_dist = best_edge_any, best_t_any, min_dist_any
            used_fallback = has_route_info  # só é "fallback de verdade" se tínhamos rota mas nada compatível apareceu
        else
            best_edge, best_t, min_dist = nothing, -1.0, Inf
        end

        if best_edge !== nothing
            if !haskey(snaps_per_edge, best_edge)
                snaps_per_edge[best_edge] = []
            end
            push!(snaps_per_edge[best_edge], (stop_id, stop_data, best_t))

            #TODO REMOVER DIAGNOSTICO PARA VERSAO FINAL
            # --- Registra o diagnóstico para esta parada ---
            if run_diagnostics
                if !has_route_info
                    diag_no_route_info += 1
                elseif !used_fallback
                    diag_matched += 1
                else
                    # Precisou cair no fallback: procura (sem limite de threshold) a aresta compatível
                    # mais próxima, só para reportar o quão longe ela realmente está.
                    nearest_compatible_dist = nothing
                    for (edge, routes) in edges_coverage_shapes
                        u, v = edge
                        if !haskey(vertices_shapes, u) || !haskey(vertices_shapes, v)
                            continue
                        end
                        if isempty(intersect(routes, served_routes))
                            continue
                        end
                        u_lat, u_lon, _ = vertices_shapes[u]
                        v_lat, v_lon, _ = vertices_shapes[v]
                        dist, _ = point_to_segment_dist(stop_lat, stop_lon, u_lat, u_lon, v_lat, v_lon)
                        if nearest_compatible_dist === nothing || dist < nearest_compatible_dist
                            nearest_compatible_dist = dist
                        end
                    end

                    if nearest_compatible_dist === nothing
                        diag_fallback_no_match += 1
                    else
                        diag_fallback_beyond += 1
                    end
                    if length(diag_fallback_examples) < 20
                        push!(diag_fallback_examples, (stop_name, min_dist, nearest_compatible_dist))
                    end
                end
            end
        else
            println("Aviso: Parada $stop_id ('$(stop_name)') não pôde ser associada a nenhuma aresta do traçado. Coordenadas: ($stop_lat, $stop_lon)")
         end
    end

    if run_diagnostics
        total_diag = diag_matched + diag_fallback_beyond + diag_fallback_no_match
        println("\n--- 🔍 DIAGNÓSTICO: o snap priorizou a rota certa? ---")
        println("Paradas avaliadas (com rota conhecida no grafo de stops): $total_diag")
        println("  ✅ Snap em aresta de rota compatível (prioridade aplicada com sucesso): $diag_matched")
        println("  ⚠️ Fallback: nenhuma aresta compatível dentro do threshold, mas existe um pouco além: $diag_fallback_beyond")
        println("  🚨 Fallback: nenhuma aresta compatível foi encontrada em lugar nenhum: $diag_fallback_no_match")
        if diag_no_route_info > 0
            println("  ℹ️ Paradas sem rota conhecida no grafo de stops (sem prioridade aplicada): $diag_no_route_info")
        end

        if !isempty(diag_fallback_examples)
            println("\n  Exemplos de fallback (parada | dist. até a aresta usada | dist. até a aresta compatível mais próxima):")
            for (name, dist_used, dist_compatible) in diag_fallback_examples
                dist_compatible_str = dist_compatible === nothing ? "nenhuma encontrada" : "$(round(dist_compatible, digits=1))m"
                println("    - $name | $(round(dist_used, digits=1))m | $dist_compatible_str")
            end
        end
        println("--- FIM DO DIAGNÓSTICO ---\n")
    end

    if isempty(snaps_per_edge)
        println("Nenhuma parada encontrada para fazer o snap.")
        return vertices_shapes, edges_coverage_shapes
    end

    edges_to_remove = Set(keys(snaps_per_edge))
    edges_to_add = Dict{Tuple{Int, Int}, Set{Any}}()
    max_existing_id = max(maximum(keys(vertices_shapes)), maximum(keys(vertices_stops)))
    next_node_id = max_existing_id + 1
    snapped_stops_count = 0

    for (edge, snapped_stops) in snaps_per_edge
        sort!(snapped_stops, by = x -> x[3])
        u, v = edge
        routes = edges_coverage_shapes[edge]
        last_node_id = u
        u_lat, u_lon, _ = vertices_shapes[u]
        v_lat, v_lon, _ = vertices_shapes[v]

        for (stop_id, stop_data, t) in snapped_stops
            new_lat = u_lat + t * (v_lat - u_lat)
            new_lon = u_lon + t * (v_lon - u_lon)
            new_name = stop_data[3]
            new_node_id = next_node_id
            vertices_shapes[new_node_id] = (new_lat, new_lon, new_name)
            next_node_id += 1
            snapped_stops_count += 1

            new_edge = (min(last_node_id, new_node_id), max(last_node_id, new_node_id))
            get!(edges_to_add, new_edge, Set{Any}()) |> routes_set -> union!(routes_set, routes)
            last_node_id = new_node_id
        end

        final_edge = (min(last_node_id, v), max(last_node_id, v))
        get!(edges_to_add, final_edge, Set{Any}()) |> routes_set -> union!(routes_set, routes)
    end

    for e in edges_to_remove
        delete!(edges_coverage_shapes, e)
    end
    for (e, r) in edges_to_add
        get!(edges_coverage_shapes, e, Set{Any}()) |> routes_set -> union!(routes_set, r)
    end

    println("Snap de paradas concluído. $snapped_stops_count paradas foram inseridas em $(length(edges_to_remove)) arestas do traçado.")
    return vertices_shapes, edges_coverage_shapes
end


function remove_adjacent_shape_nodes!(
    vertices::Dict{Int, Tuple{Float64, Float64, String}},
    edges_coverage::Dict{Tuple{Int, Int}, Set{Any}}
)
    println("Removendo nós de shape intermediários (grau 2)...")
    removed_count = 0
    changed = true

    while changed
        changed = false

        adj_list = Dict{Int, Set{Int}}()
        for (u, v) in keys(edges_coverage)
            get!(adj_list, u, Set{Int}()) |> s -> push!(s, v)
            get!(adj_list, v, Set{Int}()) |> s -> push!(s, u)
        end

        for v_id in collect(keys(vertices))
            if !haskey(vertices, v_id)
                continue
            end

            v_name = vertices[v_id][3]
            neighbors = get(adj_list, v_id, Set{Int}())

            if !(isempty(strip(v_name)) && length(neighbors) == 2)
                continue
            end

            u, w = collect(neighbors)

            edge_uv = (min(u, v_id), max(u, v_id))
            edge_vw = (min(v_id, w), max(v_id, w))
            new_edge = (min(u, w), max(u, w))

            if haskey(edges_coverage, new_edge)
                continue
            end

            routes_uv = get(edges_coverage, edge_uv, Set{Any}())
            routes_vw = get(edges_coverage, edge_vw, Set{Any}())
            new_routes = union(routes_uv, routes_vw)

            delete!(vertices, v_id)
            delete!(edges_coverage, edge_uv)
            delete!(edges_coverage, edge_vw)
            edges_coverage[new_edge] = new_routes

            removed_count += 1
            changed = true
            break
        end
    end

    println("$removed_count nós de shape intermediários foram removidos.")
    return vertices, edges_coverage
end

# ---------------------------------------------------------------------------
# Filtros de arestas/rotas (etapas opcionais)
# ---------------------------------------------------------------------------


function remove_highly_forked_routes!(edges_coverage, routes_info; main_route_width=5, max_fork_count=3)
    route_fork_count = Dict{Any, Int}()

    for (edge, routes) in edges_coverage
        if length(routes) <= 2
            u, v = edge
            if get_max_connection(u, edges_coverage) > main_route_width || get_max_connection(v, edges_coverage) > main_route_width
                for route in routes
                    route_fork_count[route] = get(route_fork_count, route, 0) + 1
                end
            end
        end
    end

    dynamic_banned_routes = Set{Any}()
    for (route, count) in route_fork_count
        if count > max_fork_count
            push!(dynamic_banned_routes, route)
        end
    end

    # Remove as rotas banidas de todas as arestas
    for (edge, routes) in edges_coverage
        setdiff!(routes, dynamic_banned_routes)
    end

    # Limpa as arestas que agora ficaram sem nenhuma rota
    filter!(p -> !isempty(p.second), edges_coverage)

    # Remove as rotas banidas também do routes_info, para que não sejam exportadas
    for r in dynamic_banned_routes
        println("$r")
        delete!(routes_info, r)
    end

    return edges_coverage, routes_info
end

function remove_long_edges!(vertices, edges_coverage; max_dist=1000.0)
    println("Removendo arestas com distância maior que $(max_dist) metros...")

    edges_to_remove = Tuple{Int, Int}[]
    for (edge, routes) in edges_coverage
        u, v = edge
        lat1, lon1, _ = vertices[u]
        lat2, lon2, _ = vertices[v]

        dist = haversine_dist(lat1, lon1, lat2, lon2)
        if dist > max_dist
            push!(edges_to_remove, edge)
        end
    end

    for edge in edges_to_remove
        delete!(edges_coverage, edge)
    end

    println("Limpeza concluída! $(length(edges_to_remove)) arestas longas foram removidas do grafo.")
    return vertices, edges_coverage
end

function add_manual_edge!(vertices, edges_coverage, routes_info, stop_name1::String, stop_name2::String, route_short_names::Vector{String})
    function find_stop_id_by_name(name_to_find)
        for (id, data) in vertices
            if data[3] == name_to_find
                return id
            end
        end
        return nothing
    end

    u_id = find_stop_id_by_name(stop_name1)
    v_id = find_stop_id_by_name(stop_name2)

    if isnothing(u_id)
        println("ERRO: Parada '$stop_name1' não encontrada. Aresta não adicionada.")
        return
    end
    if isnothing(v_id)
        println("ERRO: Parada '$stop_name2' não encontrada. Aresta não adicionada.")
        return
    end
    if u_id == v_id
        println("ERRO: As paradas são as mesmas. Aresta não adicionada.")
        return
    end

    # Cria um mapa reverso de nome curto da rota para id da rota
    route_name_to_id = Dict(short_name => id for (id, (_, short_name)) in routes_info)

    route_ids_to_add = Set{Any}()
    for r_name in route_short_names
        r_id = get(route_name_to_id, r_name, nothing)
        if isnothing(r_id)
            println("AVISO: Rota '$r_name' não encontrada e será ignorada.")
        else
            push!(route_ids_to_add, r_id)
        end
    end

    if isempty(route_ids_to_add)
        println("ERRO: Nenhuma das rotas especificadas foi encontrada. Aresta não adicionada.")
        return
    end

    edge_key = (min(u_id, v_id), max(u_id, v_id))
    if !haskey(edges_coverage, edge_key)
        edges_coverage[edge_key] = Set{Any}()
    end
    union!(edges_coverage[edge_key], route_ids_to_add)

    println("Aresta manual adicionada/atualizada entre '$stop_name1' ($u_id) e '$stop_name2' ($v_id) com as rotas: $route_short_names")
end

end