# High-level GDX file API for GDXInterface.jl

# requires `import DataFrames`

# =============================================================================
# Enums
# =============================================================================

@enum VariableType begin
    VarUnknown = 0
    VarBinary = 1
    VarInteger = 2
    VarPositive = 3
    VarNegative = 4
    VarFree = 5
    VarSOS1 = 6
    VarSOS2 = 7
    VarSemiCont = 8
    VarSemiInt = 9
end

@enum EquationType begin
    EqE = 0   # =e=
    EqG = 1   # =g=
    EqL = 2   # =l=
    EqN = 3   # =n=
    EqX = 4   # =x=
    EqC = 5   # =c=
    EqB = 6   # =b=
end

# =============================================================================
# Symbol types
# =============================================================================

abstract type GDXSymbol end

"""
    GDXSet

A GAMS set with its elements and optional explanatory text.
Records may include an `element_text` column.
"""
struct GDXSet <: GDXSymbol
    name::String
    description::String
    domain::Vector{String}
    records::DataFrames.DataFrame
end

"""
    GDXParameter

A GAMS parameter with domain and values.
"""
struct GDXParameter <: GDXSymbol
    name::String
    description::String
    domain::Vector{String}
    records::DataFrames.DataFrame
end

"""
    GDXVariable

A GAMS variable with level, marginal, lower, upper, and scale values.
"""
struct GDXVariable <: GDXSymbol
    name::String
    description::String
    domain::Vector{String}
    vartype::VariableType
    records::DataFrames.DataFrame
end

GDXVariable(name::String, desc::String, domain::Vector{String}, vartype::Integer, records::DataFrames.DataFrame) =
    GDXVariable(name, desc, domain, VariableType(vartype), records)

"""
    GDXEquation

A GAMS equation with level, marginal, lower, upper, and scale values.
"""
struct GDXEquation <: GDXSymbol
    name::String
    description::String
    domain::Vector{String}
    equtype::EquationType
    records::DataFrames.DataFrame
end

GDXEquation(name::String, desc::String, domain::Vector{String}, equtype::Integer, records::DataFrames.DataFrame) =
    GDXEquation(name, desc, domain, EquationType(equtype), records)

"""
    GDXAlias

A GAMS alias referencing another set by name.
"""
struct GDXAlias <: GDXSymbol
    name::String
    description::String
    alias_for::String
end

Base.show(io::IO, a::GDXAlias) = print(io, "GDXAlias: $(a.name) -> $(a.alias_for)")

# =============================================================================
# Case-insensitive key helpers
# =============================================================================

_symkey(s::Symbol) = Symbol(lowercase(String(s)))
_symkey(s::AbstractString) = Symbol(lowercase(s))

# =============================================================================
# GDXFile container
# =============================================================================

"""
    GDXFile

Container for GDX file contents. Provides dictionary-like access to symbols.
Symbol lookup is case-insensitive (matching GAMS behavior), but original case
is preserved in the symbol's `name` field.

# Example
```julia
gdx = read_gdx("model.gdx")
gdx[:demand]              # Access records as DataFrame
get_symbol(gdx, :demand)  # Access full GDXSymbol object
list_parameters(gdx)      # List all parameters
```
"""
struct GDXFile
    path::String
    _symbols::Dict{Symbol, GDXSymbol}
    _order::Vector{Symbol}
end

function GDXFile(path::String, symbols::Dict{Symbol, <:GDXSymbol})
    gdx = GDXFile(path, Dict{Symbol, GDXSymbol}(), Symbol[])
    for (k, v) in symbols
        _insert!(gdx, k, v)
    end
    return gdx
end

function _insert!(gdx::GDXFile, key::Symbol, sym::GDXSymbol)
    lk = _symkey(key)
    if !haskey(gdx._symbols, lk)
        push!(gdx._order, lk)
    end
    gdx._symbols[lk] = sym
end

function Base.show(io::IO, gdx::GDXFile)
    println(io, "GDXFile: ", gdx.path)
    sets = list_sets(gdx)
    aliases = list_aliases(gdx)
    params = list_parameters(gdx)
    vars = list_variables(gdx)
    eqns = list_equations(gdx)
    isempty(sets) || println(io, "  Sets ($(length(sets))): ", join(sets, ", "))
    isempty(aliases) || println(io, "  Aliases ($(length(aliases))): ", join(aliases, ", "))
    isempty(params) || println(io, "  Parameters ($(length(params))): ", join(params, ", "))
    isempty(vars) || println(io, "  Variables ($(length(vars))): ", join(vars, ", "))
    isempty(eqns) || println(io, "  Equations ($(length(eqns))): ", join(eqns, ", "))
end

# Symbol listing (returns original-case names)
list_sets(gdx::GDXFile) = Symbol[Symbol(gdx._symbols[k].name) for k in gdx._order if gdx._symbols[k] isa GDXSet]
list_aliases(gdx::GDXFile) = Symbol[Symbol(gdx._symbols[k].name) for k in gdx._order if gdx._symbols[k] isa GDXAlias]
list_parameters(gdx::GDXFile) = Symbol[Symbol(gdx._symbols[k].name) for k in gdx._order if gdx._symbols[k] isa GDXParameter]
list_variables(gdx::GDXFile) = Symbol[Symbol(gdx._symbols[k].name) for k in gdx._order if gdx._symbols[k] isa GDXVariable]
list_equations(gdx::GDXFile) = Symbol[Symbol(gdx._symbols[k].name) for k in gdx._order if gdx._symbols[k] isa GDXEquation]
list_symbols(gdx::GDXFile) = Symbol[Symbol(gdx._symbols[k].name) for k in gdx._order]

"""
    get_symbol(gdx::GDXFile, sym) -> GDXSymbol

Return the full GDXSymbol object (with name, description, domain, etc.),
not just the records DataFrame. Lookup is case-insensitive.
"""
get_symbol(gdx::GDXFile, sym::Symbol) = gdx._symbols[_symkey(sym)]
get_symbol(gdx::GDXFile, sym::String) = gdx._symbols[_symkey(sym)]

# Resolve alias chains to get the underlying records DataFrame
function _get_records(gdx::GDXFile, sym::GDXSymbol, seen::Set{Symbol}=Set{Symbol}())
    sym isa GDXAlias || return sym.records
    key = _symkey(sym.alias_for)
    key in seen && error("Cyclic alias chain detected involving '$(sym.name)'")
    push!(seen, key)
    return _get_records(gdx, gdx._symbols[key], seen)
end

# Dictionary-like access (returns records DataFrame, resolving aliases)
Base.getindex(gdx::GDXFile, sym::Symbol) = _get_records(gdx, gdx._symbols[_symkey(sym)])
Base.getindex(gdx::GDXFile, sym::String) = gdx[Symbol(sym)]
Base.haskey(gdx::GDXFile, sym::Symbol) = haskey(gdx._symbols, _symkey(sym))
Base.keys(gdx::GDXFile) = Symbol[Symbol(gdx._symbols[k].name) for k in gdx._order]
Base.length(gdx::GDXFile) = length(gdx._order)

function Base.iterate(gdx::GDXFile)
    isempty(gdx._order) && return nothing
    k = gdx._order[1]
    v = gdx._symbols[k]
    return (Symbol(v.name), v), 2
end

function Base.iterate(gdx::GDXFile, state::Int)
    state > length(gdx._order) && return nothing
    k = gdx._order[state]
    v = gdx._symbols[k]
    return (Symbol(v.name), v), state + 1
end

# Property access for tab completion
function Base.propertynames(gdx::GDXFile, private::Bool=false)
    (fieldnames(GDXFile)..., (Symbol(gdx._symbols[k].name) for k in gdx._order)...)
end

function Base.getproperty(gdx::GDXFile, sym::Symbol)
    sym in fieldnames(GDXFile) && return getfield(gdx, sym)
    key = _symkey(sym)
    haskey(gdx._symbols, key) || error("Symbol :$sym not found in GDX file")
    return _get_records(gdx, gdx._symbols[key])
end

# =============================================================================
# Reading GDX files
# =============================================================================

"""
    read_gdx(filepath::String; parse_integers=true, only=nothing) -> GDXFile

Read a GDX file and return a GDXFile container with all symbols.

# Arguments
- `filepath`: Path to the GDX file
- `parse_integers`: If true, attempt to parse set elements that look like integers as Int
- `only`: Optional collection of symbol names (Strings or Symbols) to read.
  When provided, only the specified symbols are loaded from the file.

# Example
```julia
gdx = read_gdx("transport.gdx")
demand = gdx[:demand]  # Get parameter as DataFrame

# Read only specific symbols from a large file
gdx = read_gdx("big_model.gdx", only=[:x, :demand])
```
"""
function read_gdx(filepath::String; parse_integers::Bool=true, only=nothing)
    gdx = GDXHandle()
    gdx_create(gdx)
    only_filter = only === nothing ? nothing : Set{Symbol}(_symkey.(only))

    try
        gdx_open_read(gdx, filepath)
        gdxfile = GDXFile(filepath, Dict{Symbol, GDXSymbol}(), Symbol[])

        n_syms, n_uels = gdx_system_info(gdx)

        for sym_nr in 1:n_syms
            sym_name, sym_dim, sym_type = gdx_symbol_info(gdx, sym_nr)
            sym_key = _symkey(sym_name)

            if only_filter !== nothing && !(sym_key in only_filter)
                continue
            end

            sym_count, sym_user_info, sym_description = gdx_symbol_info_x(gdx, sym_nr)

            if sym_type == GMS_DT_SET
                _insert!(gdxfile, sym_key, _read_set(gdx, sym_nr, sym_name, sym_dim, sym_description))
            elseif sym_type == GMS_DT_PAR
                _insert!(gdxfile, sym_key, _read_parameter(gdx, sym_nr, sym_name, sym_dim, sym_description, parse_integers))
            elseif sym_type == GMS_DT_VAR
                _insert!(gdxfile, sym_key, _read_variable(gdx, sym_nr, sym_name, sym_dim, sym_description, sym_user_info, parse_integers))
            elseif sym_type == GMS_DT_EQU
                _insert!(gdxfile, sym_key, _read_equation(gdx, sym_nr, sym_name, sym_dim, sym_description, sym_user_info, parse_integers))
            elseif sym_type == GMS_DT_ALIAS
                aliased_name = sym_user_info > 0 ? gdx_symbol_info(gdx, sym_user_info)[1] : "*"
                _insert!(gdxfile, sym_key, GDXAlias(sym_name, sym_description, aliased_name))
            end
        end

        gdx_close(gdx)
        return gdxfile
    finally
        gdx_free(gdx)
    end
end

function _read_set(gdx::GDXHandle, sym_nr::Int, name::String, dim::Int, description::String)
    domains = dim > 0 ? gdx_symbol_get_domain_x(gdx, sym_nr, dim) : String[]

    n_recs = gdx_data_read_str_start(gdx, sym_nr)

    keys = Vector{String}(undef, max(dim, 1))
    vals = Vector{Float64}(undef, GMS_VAL_MAX)
    columns = [Vector{String}(undef, n_recs) for _ in 1:dim]
    text_nrs = Vector{Int}(undef, n_recs)

    for i in 1:n_recs
        gdx_data_read_str(gdx, keys, vals)
        for d in 1:dim
            columns[d][i] = keys[d]
        end
        text_nrs[i] = Int(vals[GAMS_VALUE_LEVEL])
    end
    gdx_data_read_done(gdx)

    df = DataFrames.DataFrame()
    for (d, domain) in enumerate(domains)
        col_name = domain == "*" ? "dim$d" : domain
        df[!, col_name] = columns[d]
    end

    has_text = any(>(0), text_nrs)
    if has_text
        element_text = Vector{String}(undef, n_recs)
        for i in 1:n_recs
            if text_nrs[i] > 0
                found, text = gdx_get_elem_text(gdx, text_nrs[i])
                element_text[i] = found ? text : ""
            else
                element_text[i] = ""
            end
        end
        df[!, :element_text] = element_text
    end

    return GDXSet(name, description, domains, df)
end

function _read_parameter(gdx::GDXHandle, sym_nr::Int, name::String, dim::Int, description::String, parse_integers::Bool)
    domains = dim > 0 ? gdx_symbol_get_domain_x(gdx, sym_nr, dim) : String[]

    n_recs = gdx_data_read_str_start(gdx, sym_nr)

    keys = Vector{String}(undef, max(dim, 1))
    vals = Vector{Float64}(undef, GMS_VAL_MAX)
    columns = [Vector{String}(undef, n_recs) for _ in 1:dim]
    values = Vector{Float64}(undef, n_recs)

    for i in 1:n_recs
        gdx_data_read_str(gdx, keys, vals)
        for d in 1:dim
            columns[d][i] = keys[d]
        end
        values[i] = parse_gdx_value(vals[GAMS_VALUE_LEVEL])
    end
    gdx_data_read_done(gdx)

    df = DataFrames.DataFrame()
    for (d, domain) in enumerate(domains)
        col_name = domain == "*" ? "dim$d" : domain
        col_data = columns[d]
        if parse_integers
            col_data = _try_parse_integers(col_data)
        end
        df[!, col_name] = col_data
    end
    df[!, :value] = values

    DataFrames.metadata!(df, "name", name, style=:default)
    DataFrames.metadata!(df, "description", description, style=:default)

    return GDXParameter(name, description, domains, df)
end

function _read_variable(gdx::GDXHandle, sym_nr::Int, name::String, dim::Int, description::String, user_info::Int, parse_integers::Bool)
    domains = dim > 0 ? gdx_symbol_get_domain_x(gdx, sym_nr, dim) : String[]

    n_recs = gdx_data_read_str_start(gdx, sym_nr)

    keys = Vector{String}(undef, max(dim, 1))
    vals = Vector{Float64}(undef, GMS_VAL_MAX)
    columns = [Vector{String}(undef, n_recs) for _ in 1:dim]
    level = Vector{Float64}(undef, n_recs)
    marginal = Vector{Float64}(undef, n_recs)
    lower = Vector{Float64}(undef, n_recs)
    upper = Vector{Float64}(undef, n_recs)
    scale = Vector{Float64}(undef, n_recs)

    for i in 1:n_recs
        gdx_data_read_str(gdx, keys, vals)
        for d in 1:dim
            columns[d][i] = keys[d]
        end
        level[i] = parse_gdx_value(vals[GAMS_VALUE_LEVEL])
        marginal[i] = parse_gdx_value(vals[GAMS_VALUE_MARGINAL])
        lower[i] = parse_gdx_value(vals[GAMS_VALUE_LOWER])
        upper[i] = parse_gdx_value(vals[GAMS_VALUE_UPPER])
        scale[i] = parse_gdx_value(vals[GAMS_VALUE_SCALE])
    end
    gdx_data_read_done(gdx)

    df = DataFrames.DataFrame()
    for (d, domain) in enumerate(domains)
        col_name = domain == "*" ? "dim$d" : domain
        col_data = columns[d]
        if parse_integers
            col_data = _try_parse_integers(col_data)
        end
        df[!, col_name] = col_data
    end
    df[!, :level] = level
    df[!, :marginal] = marginal
    df[!, :lower] = lower
    df[!, :upper] = upper
    df[!, :scale] = scale

    DataFrames.metadata!(df, "name", name, style=:default)
    DataFrames.metadata!(df, "description", description, style=:default)

    return GDXVariable(name, description, domains, VariableType(user_info), df)
end

function _read_equation(gdx::GDXHandle, sym_nr::Int, name::String, dim::Int, description::String, user_info::Int, parse_integers::Bool)
    domains = dim > 0 ? gdx_symbol_get_domain_x(gdx, sym_nr, dim) : String[]

    n_recs = gdx_data_read_str_start(gdx, sym_nr)

    keys = Vector{String}(undef, max(dim, 1))
    vals = Vector{Float64}(undef, GMS_VAL_MAX)
    columns = [Vector{String}(undef, n_recs) for _ in 1:dim]
    level = Vector{Float64}(undef, n_recs)
    marginal = Vector{Float64}(undef, n_recs)
    lower = Vector{Float64}(undef, n_recs)
    upper = Vector{Float64}(undef, n_recs)
    scale = Vector{Float64}(undef, n_recs)

    for i in 1:n_recs
        gdx_data_read_str(gdx, keys, vals)
        for d in 1:dim
            columns[d][i] = keys[d]
        end
        level[i] = parse_gdx_value(vals[GAMS_VALUE_LEVEL])
        marginal[i] = parse_gdx_value(vals[GAMS_VALUE_MARGINAL])
        lower[i] = parse_gdx_value(vals[GAMS_VALUE_LOWER])
        upper[i] = parse_gdx_value(vals[GAMS_VALUE_UPPER])
        scale[i] = parse_gdx_value(vals[GAMS_VALUE_SCALE])
    end
    gdx_data_read_done(gdx)

    df = DataFrames.DataFrame()
    for (d, domain) in enumerate(domains)
        col_name = domain == "*" ? "dim$d" : domain
        col_data = columns[d]
        if parse_integers
            col_data = _try_parse_integers(col_data)
        end
        df[!, col_name] = col_data
    end
    df[!, :level] = level
    df[!, :marginal] = marginal
    df[!, :lower] = lower
    df[!, :upper] = upper
    df[!, :scale] = scale

    DataFrames.metadata!(df, "name", name, style=:default)
    DataFrames.metadata!(df, "description", description, style=:default)

    return GDXEquation(name, description, domains, EquationType(user_info), df)
end

# =============================================================================
# Writing GDX files
# =============================================================================

"""
    write_gdx(filepath::String, gdxfile::GDXFile; producer="GDXInterface.jl")

Write a GDXFile container (with sets, parameters, variables, equations, and aliases)
to a GDX file.

# Example
```julia
gdx = read_gdx("input.gdx")
write_gdx("output.gdx", gdx)
```
"""
function write_gdx(filepath::String, gdxfile::GDXFile; producer::String="GDXInterface.jl")
    gdx = GDXHandle()
    gdx_create(gdx)

    try
        gdx_open_write(gdx, filepath, producer)

        for k in gdxfile._order
            sym = gdxfile._symbols[k]
            sym isa GDXAlias && continue
            _write_symbol(gdx, sym)
        end

        for k in gdxfile._order
            sym = gdxfile._symbols[k]
            sym isa GDXAlias || continue
            gdx_add_alias(gdx, sym.alias_for, sym.name)
        end

        gdx_close(gdx)
    finally
        gdx_free(gdx)
    end
    return filepath
end

"""
    write_gdx(filepath::String, symbols::Pair{String, DataFrame}...; producer="GDXInterface.jl")

Write DataFrames to a GDX file as parameters. Each pair maps a symbol name to its DataFrame.
The DataFrame must have a `:value` column; all other columns are treated as domain dimensions.

# Example
```julia
df = DataFrame(i=["a", "b", "c"], value=[1.0, 2.0, 3.0])
write_gdx("output.gdx", "demand" => df)
```
"""
function write_gdx(filepath::String, symbols::Pair{String, DataFrames.DataFrame}...; producer::String="GDXInterface.jl")
    gdx = GDXHandle()
    gdx_create(gdx)

    try
        gdx_open_write(gdx, filepath, producer)

        for (name, df) in symbols
            desc = get(DataFrames.metadata(df), "description", "")
            _write_parameter_df(gdx, name, df, desc)
        end

        gdx_close(gdx)
    finally
        gdx_free(gdx)
    end
    return filepath
end

function _set_domain_x(gdx::GDXHandle, name::String, domain::Vector{String}, dim::Int)
    length(domain) == dim && dim > 0 || return
    found, sym_nr = gdx_find_symbol(gdx, name)
    found && gdx_symbol_set_domain_x(gdx, sym_nr, domain)
end

# Type dispatch for writing symbols
_write_symbol(gdx::GDXHandle, sym::GDXSet) = _write_set(gdx, sym)
_write_symbol(gdx::GDXHandle, sym::GDXParameter) = _write_parameter(gdx, sym)
_write_symbol(gdx::GDXHandle, sym::GDXVariable) = _write_variable(gdx, sym)
_write_symbol(gdx::GDXHandle, sym::GDXEquation) = _write_equation(gdx, sym)

function _write_set(gdx::GDXHandle, sym::GDXSet)
    df = sym.records
    has_text = "element_text" in names(df)
    cols = [n for n in names(df) if n != "element_text"]
    dim = length(cols)

    gdx_data_write_str_start(gdx, sym.name, sym.description, dim, GMS_DT_SET)

    keys = Vector{String}(undef, dim)
    vals = zeros(Float64, GMS_VAL_MAX)

    for row in eachrow(df)
        for (i, col) in enumerate(cols)
            keys[i] = string(row[col])
        end
        if has_text
            text = string(row[:element_text])
            if !isempty(text)
                vals[GAMS_VALUE_LEVEL] = Float64(gdx_add_set_text(gdx, text))
            else
                vals[GAMS_VALUE_LEVEL] = 0.0
            end
        end
        gdx_data_write_str(gdx, keys, vals)
    end

    gdx_data_write_done(gdx)
    _set_domain_x(gdx, sym.name, sym.domain, dim)
end

function _write_parameter(gdx::GDXHandle, sym::GDXParameter)
    _write_parameter_df(gdx, sym.name, sym.records, sym.description, sym.domain)
end

function _write_parameter_df(gdx::GDXHandle, name::String, df::DataFrames.DataFrame, description::String="", domain::Vector{String}=String[])
    dim_cols = [n for n in names(df) if n != "value"]
    dim = length(dim_cols)

    gdx_data_write_str_start(gdx, name, description, dim, GMS_DT_PAR)

    keys = Vector{String}(undef, dim)
    vals = zeros(Float64, GMS_VAL_MAX)

    for row in eachrow(df)
        for (i, col) in enumerate(dim_cols)
            keys[i] = string(row[col])
        end
        vals[GAMS_VALUE_LEVEL] = _to_gdx_value(row[:value])
        gdx_data_write_str(gdx, keys, vals)
    end

    gdx_data_write_done(gdx)
    _set_domain_x(gdx, name, domain, dim)
end

const _VAR_EQU_COLS = Set(["level", "marginal", "lower", "upper", "scale"])

function _write_variable(gdx::GDXHandle, sym::GDXVariable)
    df = sym.records
    dim_cols = [n for n in names(df) if !(n in _VAR_EQU_COLS)]
    dim = length(dim_cols)

    gdx_data_write_str_start(gdx, sym.name, sym.description, dim, GMS_DT_VAR, Int(sym.vartype))

    keys = Vector{String}(undef, dim)
    vals = zeros(Float64, GMS_VAL_MAX)

    for row in eachrow(df)
        for (i, col) in enumerate(dim_cols)
            keys[i] = string(row[col])
        end
        vals[GAMS_VALUE_LEVEL] = _to_gdx_value(row[:level])
        vals[GAMS_VALUE_MARGINAL] = _to_gdx_value(row[:marginal])
        vals[GAMS_VALUE_LOWER] = _to_gdx_value(row[:lower])
        vals[GAMS_VALUE_UPPER] = _to_gdx_value(row[:upper])
        vals[GAMS_VALUE_SCALE] = _to_gdx_value(row[:scale])
        gdx_data_write_str(gdx, keys, vals)
    end

    gdx_data_write_done(gdx)
    _set_domain_x(gdx, sym.name, sym.domain, dim)
end

function _write_equation(gdx::GDXHandle, sym::GDXEquation)
    df = sym.records
    dim_cols = [n for n in names(df) if !(n in _VAR_EQU_COLS)]
    dim = length(dim_cols)

    gdx_data_write_str_start(gdx, sym.name, sym.description, dim, GMS_DT_EQU, Int(sym.equtype))

    keys = Vector{String}(undef, dim)
    vals = zeros(Float64, GMS_VAL_MAX)

    for row in eachrow(df)
        for (i, col) in enumerate(dim_cols)
            keys[i] = string(row[col])
        end
        vals[GAMS_VALUE_LEVEL] = _to_gdx_value(row[:level])
        vals[GAMS_VALUE_MARGINAL] = _to_gdx_value(row[:marginal])
        vals[GAMS_VALUE_LOWER] = _to_gdx_value(row[:lower])
        vals[GAMS_VALUE_UPPER] = _to_gdx_value(row[:upper])
        vals[GAMS_VALUE_SCALE] = _to_gdx_value(row[:scale])
        gdx_data_write_str(gdx, keys, vals)
    end

    gdx_data_write_done(gdx)
    _set_domain_x(gdx, sym.name, sym.domain, dim)
end

# =============================================================================
# Utilities
# =============================================================================

function _try_parse_integers(strings::Vector{String})
    all_ints = all(s -> !isnothing(tryparse(Int, s)), strings)
    all_ints && return parse.(Int, strings)
    return strings
end

function _to_gdx_value(val::Float64)
    isnan(val) && return GAMS_SV_NA
    val == Inf && return GAMS_SV_PINF
    val == -Inf && return GAMS_SV_MINF
    iszero(val) && signbit(val) && return GAMS_SV_EPS
    return val
end

_to_gdx_value(val::Real) = _to_gdx_value(Float64(val))
