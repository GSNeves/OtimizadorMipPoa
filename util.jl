module Util

export get_sector, get_angle_rad, get_angle_deg, get_dir_expr,
       haversine_dist, point_to_segment_dist, point_to_segment_dist_cartesian, get_max_connection,
       do_segments_intersect, expand_merged_paths, report_vertices_on_edges

# ---------------------------------------------------------------------------
# Ângulos e setores
# ---------------------------------------------------------------------------


function get_angle_rad(origin_coords, target_coords)
    dy = target_coords[1] - origin_coords[1]
    dx = target_coords[2] - origin_coords[2]
    return atan(dy, dx)
end

function get_angle_deg(u_coords, v_coords)
    angle = get_angle_rad(u_coords, v_coords)
    deg = rad2deg(angle)
    if deg < 0
        deg += 360
    end
    return deg
end

function get_sector(u_coords, v_coords)
    angle = get_angle_deg(u_coords, v_coords)
    return round(Int, angle / 45) % 8
end

function get_dir_expr(u, v, edges_collection, alphas_collection, nodes)
    # Verifica se a aresta original é (u, v) ou (v, u)
    edge_key = haskey(edges_collection, (u, v)) ? (u, v) : (v, u)

    # Recalcula o setor original e os dois setores vizinhos
    u_orig, v_orig = edge_key
    orig_sec = get_sector(nodes[u_orig], nodes[v_orig])
    sectors = [(orig_sec - 1 + 8) % 8, orig_sec, (orig_sec + 1) % 8]

    curr_alphas = alphas_collection[edge_key]

    if edge_key == (u, v)
        # Direção normal (u -> v)
        return sum(sectors[i] * curr_alphas[i] for i in 1:3)
    else
        # Direção reversa (v -> u): cada setor é rotacionado 180°
        rev_sectors = [(s + 4) % 8 for s in sectors]
        return sum(rev_sectors[i] * curr_alphas[i] for i in 1:3)
    end
end

# ---------------------------------------------------------------------------
# Distâncias geográficas
# ---------------------------------------------------------------------------

const EARTH_RADIUS_M = 6371e3 # Raio da Terra em metros


function haversine_dist(lat1, lon1, lat2, lon2)
    phi1 = lat1 * π / 180
    phi2 = lat2 * π / 180
    delta_phi = (lat2 - lat1) * π / 180
    delta_lambda = (lon2 - lon1) * π / 180

    a = sin(delta_phi / 2)^2 + cos(phi1) * cos(phi2) * sin(delta_lambda / 2)^2
    c = 2 * atan(sqrt(a), sqrt(1 - a))
    return EARTH_RADIUS_M * c
end

function report_vertices_on_edges(
    V::Dict{Int, Tuple{Float64, Float64, String}},
    E,
    x_val::Dict{Int, Float64},
    y_val::Dict{Int, Float64};
    threshold::Float64 = 1.0
)
    println("\n--- 🔍 PÓS-PROCESSAMENTO: verificando vértices posicionados sobre arestas não-adjacentes ---")

    violations = NamedTuple[]
    v_keys = collect(keys(V))
    edge_keys = collect(keys(E))

    for edge in edge_keys
        u, v = edge
        u_x, u_y = x_val[u], y_val[u]
        v_x, v_y = x_val[v], y_val[v]
        u_name = V[u][3]
        v_name = V[v][3]

        for k in v_keys
            if k == u || k == v
                continue
            end
            # Vizinhos diretos de u ou v não contam: a aresta deles é modelada
            # separadamente e é normal/esperado que fiquem próximos ali.
            if haskey(E, (k, u)) || haskey(E, (u, k)) || haskey(E, (k, v)) || haskey(E, (v, k))
                continue
            end

            dist_k_edge, t_k = point_to_segment_dist_cartesian(x_val[k], y_val[k], u_x, u_y, v_x, v_y)

            if dist_k_edge < threshold
                k_name = V[k][3]
                push!(violations, (
                    stop_id = k,
                    stop_name = k_name,
                    x = x_val[k],
                    y = y_val[k],
                    edge_u = u,
                    edge_u_name = u_name,
                    edge_v = v,
                    edge_v_name = v_name,
                    distance = dist_k_edge,
                    t = t_k,
                ))
            end
        end
    end

    if isempty(violations)
        println("Nenhum vértice encontrado em cima de uma aresta não-adjacente. ✅")
    else
        println("⚠️ $(length(violations)) vértice(s) encontrado(s) em cima de aresta(s) não-adjacente(s):\n")
        for viol in violations
            println("  📍 Parada: '$(viol.stop_name)' (id: $(viol.stop_id)) | Coordenadas (x, y): ($(round(viol.x, digits=2)), $(round(viol.y, digits=2)))")
            println("     Em cima da aresta: '$(viol.edge_u_name)' (id: $(viol.edge_u)) <-> '$(viol.edge_v_name)' (id: $(viol.edge_v))")
            println("     Distância até o segmento: $(round(viol.distance, digits=3))\n")
        end
    end
    println("--- FIM DO DIAGNÓSTICO ---\n")

    return violations
end

function point_to_segment_dist(lat_w, lon_w, lat_u, lon_u, lat_v, lon_v)
    lat_rad = lat_u * π / 180

    # Transforma as coordenadas para um plano cartesiano com origem em U
    x_v = (lon_v - lon_u) * π / 180 * cos(lat_rad) * EARTH_RADIUS_M
    y_v = (lat_v - lat_u) * π / 180 * EARTH_RADIUS_M

    x_w = (lon_w - lon_u) * π / 180 * cos(lat_rad) * EARTH_RADIUS_M
    y_w = (lat_w - lat_u) * π / 180 * EARTH_RADIUS_M

    l2 = x_v^2 + y_v^2

    if l2 == 0.0
        dist = sqrt(x_w^2 + y_w^2)
        return dist, 0.0
    end

    t = (x_w * x_v + y_w * y_v) / l2
    t_clamped = max(0.0, min(1.0, t))

    proj_x = t_clamped * x_v
    proj_y = t_clamped * y_v

    dist = sqrt((x_w - proj_x)^2 + (y_w - proj_y)^2)
    return dist, t
end

function point_to_segment_dist_cartesian(x_w, y_w, x_u, y_u, x_v, y_v)
    dx_v = x_v - x_u
    dy_v = y_v - y_u

    dx_w = x_w - x_u
    dy_w = y_w - y_u

    l2 = dx_v^2 + dy_v^2

    if l2 == 0.0
        dist = sqrt(dx_w^2 + dy_w^2)
        return dist, 0.0
    end

    t = (dx_w * dx_v + dy_w * dy_v) / l2
    t_clamped = max(0.0, min(1.0, t))

    proj_x = t_clamped * dx_v
    proj_y = t_clamped * dy_v

    dist = sqrt((dx_w - proj_x)^2 + (dy_w - proj_y)^2)
    return dist, t
end

# ---------------------------------------------------------------------------
# Consultas no grafo
# ---------------------------------------------------------------------------

function get_max_connection(v, edges_coverage)
    max_routes = 0
    for (edge, routes) in edges_coverage
        if edge[1] == v || edge[2] == v
            max_routes = max(max_routes, length(routes))
        end
    end
    return max_routes
end

# ---------------------------------------------------------------------------
# Interseção de segmentos
# ---------------------------------------------------------------------------

function orientation(p, q, r)
    # Acessa latitude com [1] e longitude com [2]
    val = (q[1] - p[1]) * (r[2] - q[2]) -
          (q[2] - p[2]) * (r[1] - q[1])

    if isapprox(val, 0.0, atol=1e-9)
        return 0 # Colinear
    end

    return (val > 0) ? 1 : 2 # Horário ou anti-horário
end

function on_segment(p, q, r)
    return (q[2] <= max(p[2], r[2]) && q[2] >= min(p[2], r[2]) &&
            q[1] <= max(p[1], r[1]) && q[1] >= min(p[1], r[1]))
end

function do_segments_intersect(p1, q1, p2, q2)
    # Encontra as quatro orientações necessárias para os casos gerais e especiais
    o1 = orientation(p1, q1, p2)
    o2 = orientation(p1, q1, q2)
    o3 = orientation(p2, q2, p1)
    o4 = orientation(p2, q2, q1)

    # Caso geral: os segmentos se cruzam se as orientações forem diferentes
    if (o1 != o2 && o3 != o4)
        return true
    end

    # Casos especiais (quando os pontos são colineares)
    if (o1 == 0 && on_segment(p1, p2, q1))
        return true
    end
    if (o2 == 0 && on_segment(p1, q2, q1))
        return true
    end
    if (o3 == 0 && on_segment(p2, p1, q2))
        return true
    end
    if (o4 == 0 && on_segment(p2, q1, q2))
        return true
    end

    return false # Não se cruzam
end

# ---------------------------------------------------------------------------
# Expansão de caminhos fundidos
# ---------------------------------------------------------------------------
function expand_merged_paths(V, V_all, E, L, x_val, y_val, merged_paths)
    # Cria um novo dicionário de vértices que conterá os vértices originais e os intermediários
    V_expanded = Dict{Int, Tuple{Float64, Float64, String}}()

    # Adiciona os vértices que permaneceram no grafo otimizado
    for v_id in keys(x_val)
        if haskey(V, v_id)
            V_expanded[v_id] = (x_val[v_id], y_val[v_id], V[v_id][3])
        end
    end

    E_expanded = Dict{Tuple{Int, Int}, Set{Any}}()
    L_expanded = L # A informação das rotas não muda

    for (edge, routes) in E
        # Verifica se a aresta foi resultado de uma fusão
        path = get(merged_paths, edge, [])

        if isempty(path)
            # Se não foi, é uma aresta normal, apenas a adiciona
            E_expanded[edge] = routes
            continue
        end

        # Se foi, expande a aresta em múltiplos segmentos
        num_segments = length(path) - 1
        if num_segments < 1
            continue
        end

        start_node_id = path[1]
        end_node_id = path[end]

        # Posições otimizadas dos nós de início e fim
        start_pos = (x_val[start_node_id], y_val[start_node_id])
        end_pos = (x_val[end_node_id], y_val[end_node_id])

        # Adiciona os nós intermediários ao V_expanded e calcula suas posições
        for i in 2:num_segments
            intermediate_node_id = path[i]
            fraction = (i - 1) / num_segments

            inter_x = start_pos[1] + fraction * (end_pos[1] - start_pos[1])
            inter_y = start_pos[2] + fraction * (end_pos[2] - start_pos[2])

            V_expanded[intermediate_node_id] = (inter_x, inter_y, V_all[intermediate_node_id][3])
        end

        # Cria as novas arestas segmentadas
        for i in 1:num_segments
            new_small_edge = (min(path[i], path[i+1]), max(path[i], path[i+1]))
            E_expanded[new_small_edge] = routes
        end
    end

    return V_expanded, E_expanded, L_expanded
end

end