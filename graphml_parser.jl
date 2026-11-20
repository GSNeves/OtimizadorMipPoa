module DataParserGraphML

using EzXML
using Printf

export load_graphml_data

"""
    load_graphml_data(filepath::String)

Lê um arquivo .graphml e retorna as estruturas (V, E, L) compatíveis com o otimizador MIP.
Esta versão não realiza nenhuma compressão ou simplificação dos dados originais.
"""
function load_graphml_data(filepath::String)
    println("Lendo arquivo GraphML: $filepath ...")
    
    # Tenta carregar o documento
    doc = readxml(filepath)
    root_node = root(doc)
    
    # Namespace padrão do GraphML para as buscas XPath
    ns = Dict("g" => "http://graphml.graphdrawing.org/xmlns")
    
    # --- 1. MAPEAMENTO DE CHAVES (KEYS) ---
    # Identifica o que cada ID de dado representa (coordenadas, nomes, rotas)
    node_attr_map = Dict{String, String}() # attr.name -> id
    route_key_info = Dict{String, Tuple{String, String}}() # id -> (short_name, color_hex)
    
    for key in findall("//g:key", root_node, ns)
        # Substituindo o uso do get() pelo formato seguro do EzXML usando haskey()
        target = haskey(key, "for") ? key["for"] : ""
        id = haskey(key, "id") ? key["id"] : ""
        attr_name = haskey(key, "attr.name") ? key["attr.name"] : ""
        
        if target == "node"
            node_attr_map[attr_name] = id
        elseif target == "edge"
            # Identifica chaves de rota: no GraphML de POA, elas possuem atributos de cor
            if haskey(key, "color.r") && haskey(key, "color.g") && haskey(key, "color.b")
                r = parse(Int, key["color.r"])
                g = parse(Int, key["color.g"])
                b = parse(Int, key["color.b"])
                color_hex = @sprintf("%02X%02X%02X", r, g, b)
                route_key_info[id] = (attr_name, color_hex)
            end
        end
    end
    
    # IDs específicos para nós (aqui usamos o get normal porque node_attr_map é um Dict do Julia)
    x_id = get(node_attr_map, "x coordinate", "x")
    y_id = get(node_attr_map, "y coordinate", "y")
    label_id = get(node_attr_map, "station name", "label")
    
    # --- 2. PROCESSAMENTO DE VÉRTICES (V) ---
    vertices = Dict{Int, Tuple{Float64, Float64, String}}()
    node_str_to_int = Dict{String, Int}() # Mapeia "n0" para um Int
    
    for node in findall("//g:node", root_node, ns)
        str_id = haskey(node, "id") ? node["id"] : ""
        if isempty(str_id) continue end
        
        # Converte "n804" para 804 se possível, ou usa um hash único
        int_id = try
            parse(Int, replace(str_id, r"[^\d]" => ""))
        catch
            hash(str_id) % Int
        end
        node_str_to_int[str_id] = int_id
        
        x_val, y_val, name = 0.0, 0.0, "Estação $int_id"
        
        for data in findall("g:data", node, ns)
            d_key = haskey(data, "key") ? data["key"] : ""
            if d_key == x_id
                x_val = parse(Float64, nodecontent(data))
            elseif d_key == y_id
                y_val = parse(Float64, nodecontent(data))
            elseif d_key == label_id
                name = nodecontent(data)
            end
        end
        
        # Armazena: id => (latitude/Y, longitude/X, nome)
        vertices[int_id] = (y_val, x_val, name)
    end
    
    # --- 3. PROCESSAMENTO DE ARESTAS (E) E LINHAS (L) ---
    edges_coverage = Dict{Tuple{Int, Int}, Set{Any}}()
    routes_info = Dict{Any, Tuple{String, String}}()
    
    # Popula L (Informações das rotas): id -> (cor, nome)
    for (rid, info) in route_key_info
        routes_info[rid] = (info[2], info[1])
    end
    
    for edge in findall("//g:edge", root_node, ns)
        src_str = haskey(edge, "source") ? edge["source"] : ""
        tgt_str = haskey(edge, "target") ? edge["target"] : ""
        
        # Ignora se os nós não estiverem registrados
        if isempty(src_str) || isempty(tgt_str) || !haskey(node_str_to_int, src_str) || !haskey(node_str_to_int, tgt_str)
            continue
        end
        
        u = node_str_to_int[src_str]
        v = node_str_to_int[tgt_str]
        
        # Mantém ordem min-max para consistência
        edge_key = (min(u, v), max(u, v))
        
        if !haskey(edges_coverage, edge_key)
            edges_coverage[edge_key] = Set{Any}()
        end
        
        # Verifica quais rotas passam por esta aresta
        for data in findall("g:data", edge, ns)
            d_key = haskey(data, "key") ? data["key"] : ""
            # Se a chave for uma rota válida e o texto do XML for "TRUE"
            if haskey(route_key_info, d_key) && uppercase(strip(nodecontent(data))) == "TRUE"
                push!(edges_coverage[edge_key], d_key)
            end
        end
    end
    
    println("Grafo construído com sucesso!")
    println("Nós: $(length(vertices)) | Arestas: $(length(edges_coverage)) | Rotas: $(length(routes_info))")
    
    return vertices, edges_coverage, routes_info
end

end