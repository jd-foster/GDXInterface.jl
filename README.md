# GDXInterface.jl

High-level Julia interface for reading and writing
[GDX files](https://gams-dev.github.io/gdx/index.html)
(GAMS Data Exchange).

Uses the [`gdx_jll`](https://github.com/JuliaBinaryWrappers/gdx_jll.jl.git) package to
provide the GDX C library independently of GAMS.

**No GAMS installation required.**

For more information on the GDX file format, see the blog post
['GDX source code published on GitHub'](https://www.gams.com/blog/2023/12/gdx-source-code-published-on-github/).

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/jd-foster/GDXInterface.jl.git")
```

Or in the Pkg REPL:

```
pkg> add https://github.com/jd-foster/GDXInterface.jl.git
```

Run tests with:

```
pkg> test GDXInterface
```

These instructions will be updated if/when the package is registered.

## Quick Start

### Reading GDX files

```julia
using GDXInterface

gdx = read_gdx("transport.gdx")

# List symbols by type
list_sets(gdx)
list_parameters(gdx)
list_variables(gdx)
list_equations(gdx)

# Access data as DataFrames
demand = gdx[:demand]       # bracket syntax
demand = gdx.demand         # property syntax (with tab completion)

# Access the full symbol object (includes name, description, domain)
sym = get_symbol(gdx, :demand)
sym.name         # "demand"
sym.description  # explanatory text from GAMS
sym.domain       # ["j"]
sym.records      # the DataFrame
```

### Writing GDX files

```julia
using GDXInterface, DataFrames

# Write DataFrames as parameters
supply = DataFrame(i = ["seattle", "san-diego"], value = [350.0, 600.0])
demand = DataFrame(j = ["new-york", "chicago", "topeka"], value = [325.0, 300.0, 275.0])
write_gdx("output.gdx", "supply" => supply, "demand" => demand)

# Round-trip: read a GDX file and write it back (preserves all symbol types)
gdx = read_gdx("model.gdx")
write_gdx("copy.gdx", gdx)
```

### Selective reading

For large GDX files, load only the symbols you need:

```julia
gdx = read_gdx("big_model.gdx", only=[:x, :demand])
```

## API Reference

### Types

| Type | Description |
|------|-------------|
| `GDXFile` | Container for all symbols in a GDX file |
| `GDXSet` | GAMS set (elements + explanatory text) |
| `GDXParameter` | GAMS parameter (domain elements + values) |
| `GDXVariable` | GAMS variable (level, marginal, lower, upper, scale) |
| `GDXEquation` | GAMS equation (level, marginal, lower, upper, scale) |

### Reading

```julia
read_gdx(filepath; parse_integers=true, only=nothing) -> GDXFile
```

- `parse_integers`: convert set elements like `"2020"` to `Int`
- `only`: vector of symbol names to load (e.g. `[:x, :demand]`)

### Writing

```julia
# Write DataFrames as parameters (convenience)
write_gdx(filepath, "name" => DataFrame, ...)

# Write a full GDXFile (sets, parameters, variables, equations)
write_gdx(filepath, gdxfile::GDXFile)
```

### Querying a GDXFile

```julia
gdx[:name]               # records DataFrame (bracket access)
gdx.name                 # records DataFrame (property access)
get_symbol(gdx, :name)   # full GDXSymbol object

list_sets(gdx)            # list set names
list_parameters(gdx)      # list parameter names
list_variables(gdx)       # list variable names
list_equations(gdx)       # list equation names
list_symbols(gdx)         # list all symbol names

haskey(gdx, :name)        # check if symbol exists
length(gdx)              # number of symbols
for (k, v) in gdx ...    # iterate over symbols
```

## Special Values

GAMS special values are mapped to Julia equivalents when reading:

| GAMS | Julia | Notes |
|------|-------|-------|
| `UNDEF` | `NaN` | Undefined value |
| `NA` | `NaN` | Not available |
| `+INF` | `Inf` | Positive infinity |
| `-INF` | `-Inf` | Negative infinity |
| `EPS` | `-0.0` | "Explicitly zero" in sparse data |

When writing, `NaN` maps to GAMS `NA`, `Inf`/`-Inf` map to `+INF`/`-INF`,
and `-0.0` maps back to GAMS `EPS`. This preserves EPS semantics through
round-trips. Regular `0.0` stays as a normal zero.

## Acknowledgments

Derived from GDX file access functionality originally developed for
[GAMS.jl](https://github.com/GAMS-dev/gams.jl).
