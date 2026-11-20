using JuMP, CPLEX, ArgParse

# 1. Importa o seu arquivo de processamento
include("data_parser.jl")
include("graphml_parser.jl")
include("util.jl")
include("mip_constraints.jl")
include("plotter.jl")
include("gtfs_to_xml.jl")
using .DataParser
using .DataParserGraphML
using .Util
using .MIPConstraints
using .Plotter

# Função para processar argumentos da linha de comando com ArgParse
function parse_commandline()
    s = ArgParseSettings(description="Executa o otimizador de mapa esquemático com filtros opcionais.")

    @add_arg_table! s begin
        "-c", "--colors"
            help = "Lista de cores de rotas para filtrar (ex: FF0000 0000FF)"
            nargs = '*'  # 0 ou mais argumentos
            default = String[]
        "-r", "--routes"
            help = "Lista de nomes curtos de rotas para filtrar (ex: T1 T2 T3)"
            nargs = '*'  # 0 ou mais argumentos
            default = String[]
    end

    return parse_args(s)
end

# Pega dados
parsed_args = parse_commandline()
target_colors_arg = parsed_args["colors"]
target_routes_arg = parsed_args["routes"]
V, E, L, V_all, merged_counts, merged_paths = load_gtfs_data(target_colors=target_colors_arg, target_routes=target_routes_arg)
#V, E, L = load_graphml_data("sydney.graphml");

println("Dados recebidos! Iniciando modelo com $(length(V)) paradas.")

model = Model(CPLEX.Optimizer)
set_attribute(model, "CPX_PARAM_EPINT", 1e-8)
set_time_limit_sec(model, 12000.0)
set_attribute(model, "CPX_PARAM_EPGAP", 0.6)
#set_attribute(model, "CPX_PARAM_INTSOLLIM", 1)
#Numero de threads para computador do PCAD phoenix
set_attribute(model, MOI.NumberOfThreads(), 44)
set_attribute(model, "CPX_PARAM_TRELIM", 110000.0)

# Estabelece tamanho do grid
lat_min, lat_max = minimum(v[1] for v in values(V)), maximum(v[1] for v in values(V))
lon_min, lon_max = minimum(v[2] for v in values(V)), maximum(v[2] for v in values(V))
ratio = (lat_max - lat_min) / (lon_max - lon_min)
GRID_WIDTH = length(V)
GRID_HEIGHT = round(Int, GRID_WIDTH * abs(ratio))

# Variáveis baseadas nos vértices importados
@variable(model, 0 <= x[k in keys(V)] <= GRID_WIDTH)
@variable(model, 0 <= y[k in keys(V)] <= GRID_HEIGHT)

# Section 4.1
@expression(model, z1[i in keys(V)], (x[i] + y[i]) / 2.0)
@expression(model, z2[i in keys(V)], (x[i] - y[i]) / 2.0)

L_MIN = 1.0     # Comprimento mínimo da aresta (l_epsilon no artigo)
M_BIG = 10.0 + max(GRID_WIDTH, GRID_HEIGHT) # Big-M

alpha_vars, dir_vars = build_direction_constraints!(model, V, E, x, y, z1, z2, L_MIN, M_BIG, merged_counts)
adj_list = build_circular_order_constraints!(model, V, E, dir_vars)
bend_cost_vars = build_bend_cost_constraints!(model, V, E, adj_list, alpha_vars)
rel_pos_cost_vars = build_relative_position_cost(alpha_vars)
edge_len_cost_vars = build_edge_length_cost!(model, E, x, y)


# Peso das penalidades
W_BEND = 2.0   
W_LENGTH = 1.0   
W_REL = 3.0
#W_SLACK = 10.0

# Objetivo
@objective(model, Min, 
    W_BEND * sum(bend_cost_vars) + 
    W_LENGTH * sum(edge_len_cost_vars) + 
    W_REL * sum(rel_pos_cost_vars)
)

optimize!(model)

# ==============================================================================
# ITERAÇÕES PARA MANTER RELAÇÃO ANGULAR DE NÓS NÃO ADJACENTES
# ==============================================================================

status = termination_status(model)

if has_values(model)
    MAX_ITER = 100000
    for iter in 1:MAX_ITER
        println("\nIteração $iter de verificação de ângulos entre vértices não adjacentes...")
        
        x_val = Dict(k => Float64(value(x[k])) for k in keys(V))
        y_val = Dict(k => Float64(value(y[k])) for k in keys(V))
        
        # Exporta o resultado da iteração atual para GraphML
        optimized_V_iter = Dict{Int, Tuple{Float64, Float64, String}}()
        for (v_node, (_, _, name)) in V
            optimized_V_iter[v_node] = (y_val[v_node], x_val[v_node], name)
        end
        export_to_graphml(optimized_V_iter, E, L; filename="mapa_otimizado_poa_iter$(iter).graphml", single_route_per_edge=true)

        added_constraints = 0
        v_keys = collect(keys(V))
        n_v = length(v_keys)
        
        for i in 1:n_v
            # Feedback visual de progresso para evitar a impressão de que o programa travou
            if i % 100 == 0
                println("Iteração $iter: Processando restrições angulares de vértices (Progresso: $i de $n_v)...")
            end

            for j in (i+1):n_v
                u = v_keys[i]
                v = v_keys[j]
                
                # Se existe aresta, pula (edges_coverage tem chave como min, max)
                if haskey(E, (u, v)) || haskey(E, (v, u))
                    continue
                end
                
                add_constraint_flag = false
                # Condição 1: Vértices sobrepostos
                dist_uv = max(abs(x_val[u] - x_val[v]), abs(y_val[u] - y_val[v]))
                if dist_uv < L_MIN
                    add_constraint_flag = true
                else
                    # Condição 2: Ângulo relativo entre vértices mudou drasticamente
                    orig_angle = get_angle_deg(V[u], V[v])
                    new_angle = get_angle_deg((y_val[u], x_val[u]), (y_val[v], x_val[v]))
                    
                    diff_angle = abs(new_angle - orig_angle)
                    diff_angle = diff_angle > 180.0 ? 360.0 - diff_angle : diff_angle
                    
                    if diff_angle > 135.0
                        add_constraint_flag = true
                    end
                end

                if add_constraint_flag
                    # Se a condição for atendida, adiciona uma restrição para forçar o afastamento
                    # dos vértices na direção original em que eles estavam.
                    # Isso ajuda a preservar a topologia global do mapa.
                    orig_sector = get_sector(V[u], V[v])
                    if orig_sector == 0 # Leste
                        @constraint(model, x[v] >= x[u] + L_MIN)
                    elseif orig_sector == 1 # Nordeste
                        @constraint(model, z1[v] >= z1[u] + L_MIN)
                    elseif orig_sector == 2 # Norte
                        @constraint(model, y[v] >= y[u] + L_MIN)
                    elseif orig_sector == 3 # Noroeste
                        @constraint(model, z2[u] >= z2[v] + L_MIN)
                    elseif orig_sector == 4 # Oeste
                        @constraint(model, x[u] >= x[v] + L_MIN)
                    elseif orig_sector == 5 # Sudoeste
                        @constraint(model, z1[u] >= z1[v] + L_MIN)
                    elseif orig_sector == 6 # Sul
                        @constraint(model, y[u] >= y[v] + L_MIN)
                    elseif orig_sector == 7 # Sudeste
                        @constraint(model, z2[v] >= z2[u] + L_MIN)
                    end
                    
                    added_constraints += 1
                end
            end
        end
        
        if added_constraints > 0
            println("Foram adicionadas $added_constraints restrições de ângulo. Reotimizando...")
            
            for k in keys(V)
                set_start_value(x[k], x_val[k])
                set_start_value(y[k], y_val[k])
            end

            optimize!(model)
            status = termination_status(model)
            if !has_values(model)
                println("Modelo se tornou inviável ou limite atingido nas iterações adicionais.")
                break
            end
        else
            println("Nenhuma violação encontrada. Mapas angulares estabilizados.")
            break
        end
    end
end

# ==============================================================================
# VISUALIZAÇÃO (PLOTS.JL)
# ==============================================================================
    
status = termination_status(model)
println("Status da Otimização: $status")

if has_values(model)
    println("Gerando visualização final com paradas intermediárias...")

    x_val = Dict(k => Float64(value(x[k])) for k in keys(V))
    y_val = Dict(k => Float64(value(y[k])) for k in keys(V))

    # Diagnóstico de pós-processamento: vértices que ficaram posicionados em cima de
    # arestas das quais não são extremidade nem vizinho, no mapa final já otimizado.
    report_vertices_on_edges(V, E, x_val, y_val; threshold=L_MIN)

    # Expande o grafo para incluir as paradas que foram fundidas
    V_expanded, E_expanded, L_expanded = expand_merged_paths(V, V_all, E, L, x_val, y_val, merged_paths)

    # Prepara o dicionário de vértices para exportação no formato (y, x, nome)
    optimized_V_export = Dict{Int, Tuple{Float64, Float64, String}}()
    for (v_id, (v_x, v_y, v_name)) in V_expanded
        # A ferramenta de visualização espera as coordenadas como (latitude, longitude), que no nosso grid são (y, x)
        optimized_V_export[v_id] = (v_y, v_x, v_name)
    end

    # Exporta o grafo final expandido para um arquivo GraphML
    export_to_graphml(optimized_V_export, E_expanded, L_expanded; filename="mapa_final_expandido_single.graphml", single_route_per_edge=true)
    export_to_graphml(optimized_V_export, E_expanded, L_expanded; filename="mapa_final_expandido_multiple.graphml", single_route_per_edge=false)
    println("Mapa final salvo em 'mapa_final_expandido_single.graphml' e 'mapa_final_expandido_multiple.graphml'")

    # A chamada original para visualização foi comentada, pois a nova exportação já cumpre o papel para o mapa final.
    # generate_visualization(V, E, L, x, y, export_to_graphml)

elseif status == TIME_LIMIT
    println("\nLimite de tempo atingido sem encontrar uma solução viável.")
    
elseif status == INFEASIBLE
    println("\nModelo Inviável! Acionando o Refinador de Conflitos (IIS)...")
    compute_conflict!(model)
    
    println("\nAs seguintes restrições estão em conflito e causando a inviabilidade:")
    conflitos_encontrados = 0
    
    # Itera sobre todos os tipos de restrições do modelo para achar os culpados
    for (F, S) in list_of_constraint_types(model)
        for con in all_constraints(model, F, S)
            if MOI.get(model, MOI.ConstraintConflictStatus(), con) == MOI.IN_CONFLICT
                println(con)
                global conflitos_encontrados += 1
            end
        end
    end
    
    # Se der erro nas variáveis (limites inferiores/superiores)
    for var in all_variables(model)
        if has_lower_bound(var) && MOI.get(model, MOI.ConstraintConflictStatus(), LowerBoundRef(var)) == MOI.IN_CONFLICT
            println("Conflito no limite inferior da variável: ", var)
            global conflitos_encontrados += 1
        end
        
        if has_upper_bound(var) && MOI.get(model, MOI.ConstraintConflictStatus(), UpperBoundRef(var)) == MOI.IN_CONFLICT
            println("Conflito no limite superior da variável: ", var)
            global conflitos_encontrados += 1
        end
        
        if is_fixed(var) && MOI.get(model, MOI.ConstraintConflictStatus(), FixRef(var)) == MOI.IN_CONFLICT
            println("Conflito no valor fixo da variável: ", var)
            global conflitos_encontrados += 1
        end
    end
    
    println("\nTotal de restrições conflitantes: $conflitos_encontrados")
    println("Analise as equações acima para ver qual regra está quebrando o mapa.")
end
