if !@isdefined(DataParser)
    include("data_parser.jl")
end

using .DataParser
using ArgParse

function parse_commandline()
    s = ArgParseSettings(description="Exporta dados GTFS para um arquivo GraphML com filtros opcionais.")

    @add_arg_table! s begin
        "-c", "--colors"
            help = "Lista de cores de rotas para filtrar (ex: FF0000 0000FF)"
            nargs = '*'
            default = String[]
        "-r", "--routes"
            help = "Lista de nomes curtos de rotas para filtrar (ex: T1 T2 T3)"
            nargs = '*'
            default = String[]
        "-s", "--single-route-per-edge"
            help = "Se presente, marca apenas a primeira rota em cada aresta para uma visualização mais limpa. Se ausente, marca todas as rotas."
            action = :store_true
    end

    return parse_args(s)
end

function main()
    parsed_args = parse_commandline()
    data = load_gtfs_data(target_colors=parsed_args["colors"], target_routes=parsed_args["routes"])
    V, E, L = data[1], data[2], data[3]

    # Cálculo das dimensões do grid
    lat_min, lat_max = minimum(v[1] for v in values(V)), maximum(v[1] for v in values(V))
    lon_min, lon_max = minimum(v[2] for v in values(V)), maximum(v[2] for v in values(V))
    ratio = (lat_max - lat_min) / (lon_max - lon_min)
    GRID_WIDTH = length(V)
    GRID_HEIGHT = round(Int, GRID_WIDTH * abs(ratio))

    println("\n--- DIMENSÕES DO GRID ---")
    println("lat_min: $lat_min, lat_max: $lat_max")
    println("lon_min: $lon_min, lon_max: $lon_max")
    println("ratio: $ratio")
    println("GRID_WIDTH: $GRID_WIDTH")
    println("GRID_HEIGHT: $GRID_HEIGHT")
    println("-------------------------\n")

    export_to_graphml(V, E, L, single_route_per_edge=parsed_args["single-route-per-edge"])
end

# Função auxiliar para converter cor Hexadecimal (GTFS) em RGB
function hex_to_rgb(hex_str::String)
    # Remove o '#' se houver
    hex = replace(hex_str, "#" => "")
    if length(hex) >= 6
        try
            r = parse(Int, hex[1:2], base=16)
            g = parse(Int, hex[3:4], base=16)
            b = parse(Int, hex[5:6], base=16)
            return r, g, b
        catch
            return 0, 0, 0
        end
    end
    return 0, 0, 0
end


function export_to_graphml(vertices, edges_coverage, routes_info; filename="grafo_porto_alegre.graphml", single_route_per_edge=false)
    println("Exportando grafo no formato .graphml para $filename...")
    
    open(filename, "w") do io
        # Cabeçalho padrão XML e GraphML
        write(io, "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n")
        write(io, "<graphml xmlns=\"http://graphml.graphdrawing.org/xmlns\"\n")
        write(io, "    xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"\n")
        write(io, "    xsi:schemaLocation=\"http://graphml.graphdrawing.org/xmlns\n")
        write(io, "     http://graphml.graphdrawing.org/xmlns/1.0/graphml.xsd\">\n")
        
        # Atributos dos nós
        write(io, "  <key id=\"x\" for=\"node\" attr.name=\"x coordinate\" attr.type=\"double\"/>\n")
        write(io, "  <key id=\"y\" for=\"node\" attr.name=\"y coordinate\" attr.type=\"double\"/>\n")
        write(io, "  <key id=\"label\" for=\"node\" attr.name=\"station name\" attr.type=\"string\"/>\n")
        
        # Atributos das arestas
        for (route_id, (hex_color, short_name)) in routes_info
            r, g, b = hex_to_rgb(hex_color)
            safe_name = replace(short_name, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;", "'" => "&apos;")
            
            write(io, "  <key id=\"l_$route_id\" for=\"edge\" attr.name=\"$safe_name\" attr.type=\"boolean\" color.r=\"$r\" color.g=\"$g\" color.b=\"$b\">\n")
            write(io, "    <default>FALSE</default>\n")
            write(io, "  </key>\n")
        end
        
        write(io, "  <graph id=\"G\" edgedefault=\"directed\">\n")
        
        # Vértices
        for (id, (lat, lon, name)) in vertices
            safe_name = replace(name, "&" => "&amp;", "<" => "&lt;", ">" => "&gt;", "\"" => "&quot;", "'" => "&apos;")
            
            # Prefixo 'n' no ID do node
            write(io, "    <node id=\"n$id\">\n")
            write(io, "        <data key=\"x\">$lon</data>\n")
            write(io, "        <data key=\"y\">$lat</data>\n")
            write(io, "        <data key=\"label\">$safe_name</data>\n")
            write(io, "    </node>\n")
        end
        
        # Arestas
        edge_id_counter = 0
        for ((u, v), routes) in edges_coverage
            edge_id_counter += 1
            
            # Prefixo 'e' no ID da aresta
            write(io, "    <edge id=\"e$edge_id_counter\" source=\"n$u\" target=\"n$v\">\n")
            
            if single_route_per_edge
                # Para evitar arestas grossas, marcamos apenas a primeira rota como TRUE
                if !isempty(routes)
                    route_id = first(routes)
                    write(io, "        <data key=\"l_$route_id\">TRUE</data>\n")
                end
            else
                for route_id in routes
                    write(io, "        <data key=\"l_$route_id\">TRUE</data>\n")
                end
            end
            
            write(io, "    </edge>\n")
        end
        
        write(io, "  </graph>\n")
        write(io, "</graphml>\n")
    end
    
    println("Exportação concluída com sucesso! Arquivo salvo como: $filename")
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end