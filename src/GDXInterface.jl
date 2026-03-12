module GDXInterface

import DataFrames
import gdx_jll
const LIBGDX = gdx_jll.libgdx

include("gdx_c_api.jl")
include("GDXFile.jl")

# GDX file access exports
export GDXFile, GDXSymbol, GDXSet, GDXParameter, GDXVariable, GDXEquation
export read_gdx, write_gdx
export list_sets, list_parameters, list_variables, list_equations, list_symbols

end # module GDXInterface
