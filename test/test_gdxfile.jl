# Tests for GDXFile API

# For reference: script to create test file "gams_gdx_test.gdx" using GAMS
#=
gms_script = """
Set i /a, b, c/;
Parameter p(i) / a 1.5, b 2.5, c 3.5 /;
Free Variable x(i);
Positive Variable y(i);
x.l(i) = ord(i) * 10;
x.m(i) = ord(i) * 0.1;
y.l(i) = ord(i) * 5;
y.up(i) = 100;
Equation dummy; dummy.. sum(i, x(i)) =e= 0;
execute_unload "gams_gdx_test.gdx", i, p, x, y;
"""
=#

@testset "GDXFile API" begin
    test_gdx = joinpath(TEST_DATA_DIR, "gams_gdx_test.gdx")
    ispath(test_gdx)

    @testset "Reading GDX file created by GAMS" begin
        gdxfile = read_gdx(test_gdx)

        @test :i in list_sets(gdxfile)
        @test :p in list_parameters(gdxfile)

        p = gdxfile[:p]
        @test "value" in names(p)
        @test p.value == [1.5, 2.5, 3.5]
    end

    @testset "Reading variables" begin
        gdxfile = read_gdx(test_gdx)

        @test :x in list_variables(gdxfile)
        @test :y in list_variables(gdxfile)

        x = gdxfile[:x]
        @test "level" in names(x)
        @test "marginal" in names(x)
        @test "lower" in names(x)
        @test "upper" in names(x)
        @test x.level == [10.0, 20.0, 30.0]
        @test x.marginal ≈ [0.1, 0.2, 0.3]

        y = gdxfile[:y]
        @test y.level == [5.0, 10.0, 15.0]
        @test all(y.lower .== 0.0)
        @test all(y.upper .== 100.0)
    end

    @testset "Write and read round-trip" begin
        supply = DataFrame(
            i = ["seattle", "san-diego"],
            value = [350.0, 600.0]
        )
        demand = DataFrame(
            j = ["new-york", "chicago", "topeka"],
            value = [325.0, 300.0, 275.0]
        )

        outfile = joinpath(tempdir(), "gdx_jl_write_test.gdx")
        write_gdx(outfile, "supply" => supply, "demand" => demand)

        gdxfile = read_gdx(outfile)

        @test :supply in list_parameters(gdxfile)
        @test :demand in list_parameters(gdxfile)
        @test gdxfile[:supply].value == [350.0, 600.0]
        @test gdxfile[:demand].value == [325.0, 300.0, 275.0]

        @test gdxfile.supply == gdxfile[:supply]
        @test gdxfile.demand == gdxfile[:demand]

        rm(outfile, force=true)
    end

    @testset "Multi-dimensional parameters" begin
        cost = DataFrame(
            i = ["seattle", "seattle", "san-diego", "san-diego"],
            j = ["new-york", "chicago", "new-york", "chicago"],
            value = [2.5, 1.7, 2.5, 1.8]
        )

        outfile = joinpath(tempdir(), "gdx_jl_2d_test.gdx")
        write_gdx(outfile, "cost" => cost)

        gdxfile = read_gdx(outfile)
        result = gdxfile[:cost]

        @test size(result, 1) == 4
        @test length(names(result)) == 3
        @test "value" in names(result)

        rm(outfile, force=true)
    end

    @testset "Integer parsing" begin
        df = DataFrame(year = ["2020", "2021", "2022"], value = [1.0, 2.0, 3.0])

        outfile = joinpath(tempdir(), "gdx_jl_int_test.gdx")
        write_gdx(outfile, "data" => df)

        gdxfile = read_gdx(outfile, parse_integers=true)
        @test eltype(gdxfile[:data].dim1) == Int

        gdxfile = read_gdx(outfile, parse_integers=false)
        @test eltype(gdxfile[:data].dim1) == String

        rm(outfile, force=true)
    end

    @testset "GDXFile show and propertynames" begin
        df = DataFrame(i = ["a", "b"], value = [1.0, 2.0])
        outfile = joinpath(tempdir(), "gdx_jl_show_test.gdx")
        write_gdx(outfile, "param" => df)

        gdxfile = read_gdx(outfile)

        io = IOBuffer()
        show(io, gdxfile)
        output = String(take!(io))
        @test occursin("GDXFile:", output)
        @test occursin("param", output)

        props = propertynames(gdxfile)
        @test :param in props

        rm(outfile, force=true)
    end

    @testset "Symbol listing" begin
        df1 = DataFrame(i = ["a"], value = [1.0])
        df2 = DataFrame(j = ["x"], value = [2.0])

        outfile = joinpath(tempdir(), "gdx_jl_list_test.gdx")
        write_gdx(outfile, "param1" => df1, "param2" => df2)

        gdxfile = read_gdx(outfile)

        params = list_parameters(gdxfile)
        @test :param1 in params
        @test :param2 in params
        @test length(params) == 2

        syms = list_symbols(gdxfile)
        @test length(syms) == 2

        rm(outfile, force=true)
    end

    @testset "GDXFile full round-trip (sets, params, variables)" begin
        gdx1 = read_gdx(test_gdx)

        outfile = joinpath(tempdir(), "gdx_jl_roundtrip.gdx")
        write_gdx(outfile, gdx1)
        gdx2 = read_gdx(outfile)

        @test sort(list_symbols(gdx1)) == sort(list_symbols(gdx2))

        # Parameters match
        @test gdx1[:p].value == gdx2[:p].value

        # Variables match
        @test gdx1[:x].level == gdx2[:x].level
        @test gdx1[:x].marginal ≈ gdx2[:x].marginal
        @test gdx1[:y].level == gdx2[:y].level
        @test gdx1[:y].upper == gdx2[:y].upper

        # Sets match (compare first column values)
        @test sort(Vector(gdx1[:i][!, 1])) == sort(Vector(gdx2[:i][!, 1]))

        rm(outfile, force=true)
    end

    @testset "Special values round-trip" begin
        df = DataFrame(i = ["a", "b", "c", "d", "e"], value = [NaN, Inf, -Inf, 42.0, -0.0])
        outfile = joinpath(tempdir(), "gdx_jl_special.gdx")
        write_gdx(outfile, "special" => df)

        gdxfile = read_gdx(outfile)
        result = gdxfile[:special]
        @test isnan(result.value[1])
        @test result.value[2] == Inf
        @test result.value[3] == -Inf
        @test result.value[4] == 42.0
        @test result.value[5] === -0.0

        rm(outfile, force=true)
    end

    @testset "Scalar (0-dim) parameters" begin
        df = DataFrame(value = [42.0])
        outfile = joinpath(tempdir(), "gdx_jl_scalar.gdx")
        write_gdx(outfile, "scalar_param" => df)

        gdxfile = read_gdx(outfile)
        @test :scalar_param in list_parameters(gdxfile)
        @test gdxfile[:scalar_param].value == [42.0]
        @test size(gdxfile[:scalar_param], 2) == 1  # only the value column

        rm(outfile, force=true)
    end

    @testset "Selective reading (only keyword)" begin
        gdx_full = read_gdx(test_gdx)
        gdx_partial = read_gdx(test_gdx, only=[:p, :x])

        @test length(gdx_partial) == 2
        @test :p in list_parameters(gdx_partial)
        @test :x in list_variables(gdx_partial)
        @test !haskey(gdx_partial, :i)
        @test !haskey(gdx_partial, :y)
        @test gdx_partial[:p].value == gdx_full[:p].value

        # String names should also work
        gdx_str = read_gdx(test_gdx, only=["i"])
        @test length(gdx_str) == 1
        @test :i in list_sets(gdx_str)
    end

    @testset "Error handling" begin
        @test_throws GDXException read_gdx("nonexistent_file_12345.gdx")
    end

    @testset "get_symbol" begin
        gdxfile = read_gdx(test_gdx)

        sym_p = get_symbol(gdxfile, :p)
        @test sym_p isa GDXParameter
        @test sym_p.name == "p"
        @test sym_p.records == gdxfile[:p]

        sym_x = get_symbol(gdxfile, :x)
        @test sym_x isa GDXVariable

        sym_i = get_symbol(gdxfile, "i")
        @test sym_i isa GDXSet
    end

    @testset "GDXFile iteration and length" begin
        gdxfile = read_gdx(test_gdx)
        @test length(gdxfile) == length(list_symbols(gdxfile))

        count = 0
        for (k, v) in gdxfile
            count += 1
            @test k isa Symbol
            @test v isa GDXSymbol
        end
        @test count == length(gdxfile)
    end

    @testset "Writing equations" begin
        eq_df = DataFrame(
            i = ["a", "b"],
            level = [1.0, 2.0],
            marginal = [0.5, 0.6],
            lower = [-Inf, -Inf],
            upper = [Inf, Inf],
            scale = [1.0, 1.0]
        )
        eq = GDXEquation("myeq", "test equation", ["i"], 0, eq_df)
        gdxfile = GDXFile("", Dict{Symbol,GDXSymbol}(:myeq => eq))

        outfile = joinpath(tempdir(), "gdx_jl_eq_test.gdx")
        write_gdx(outfile, gdxfile)

        gdx2 = read_gdx(outfile)
        @test :myeq in list_equations(gdx2)
        @test gdx2[:myeq].level == [1.0, 2.0]
        @test gdx2[:myeq].marginal == [0.5, 0.6]

        rm(outfile, force=true)
    end

    @testset "Writing sets standalone" begin
        set_df = DataFrame(dim1 = ["x", "y", "z"])
        s = GDXSet("myset", "test set", ["*"], set_df)
        gdxfile = GDXFile("", Dict{Symbol,GDXSymbol}(:myset => s))

        outfile = joinpath(tempdir(), "gdx_jl_set_test.gdx")
        write_gdx(outfile, gdxfile)

        gdx2 = read_gdx(outfile)
        @test :myset in list_sets(gdx2)
        @test sort(Vector(gdx2[:myset][!, 1])) == ["x", "y", "z"]

        rm(outfile, force=true)
    end

    @testset "Variable/Equation type enums" begin
        gdxfile = read_gdx(test_gdx)

        sym_x = get_symbol(gdxfile, :x)
        @test sym_x.vartype isa VariableType
        @test sym_x.vartype == VarFree  # Free Variable x(i)

        sym_y = get_symbol(gdxfile, :y)
        @test sym_y.vartype == VarPositive

        # Integer constructor still works
        v = GDXVariable("test", "", String[], 3, DataFrame(level=[0.0], marginal=[0.0], lower=[0.0], upper=[0.0], scale=[1.0]))
        @test v.vartype == VarPositive

        e = GDXEquation("test", "", String[], 0, DataFrame(level=[0.0], marginal=[0.0], lower=[0.0], upper=[0.0], scale=[1.0]))
        @test e.equtype == EqE
    end

    @testset "Case-insensitive symbol lookup" begin
        gdxfile = read_gdx(test_gdx)

        @test gdxfile[:p] == gdxfile[:P]
        @test gdxfile["p"] == gdxfile["P"]
        @test haskey(gdxfile, :P)
        @test haskey(gdxfile, :p)

        @test get_symbol(gdxfile, :P) === get_symbol(gdxfile, :p)
        @test get_symbol(gdxfile, "P") === get_symbol(gdxfile, "p")

        # Original case is preserved in the name field
        sym = get_symbol(gdxfile, :p)
        @test sym.name == "p"

        # Selective read is also case-insensitive
        gdx2 = read_gdx(test_gdx, only=[:P, :X])
        @test length(gdx2) == 2
        @test :p in list_parameters(gdx2)
        @test :x in list_variables(gdx2)
    end

    @testset "Symbol ordering is preserved" begin
        gdxfile = read_gdx(test_gdx)
        syms = list_symbols(gdxfile)

        # Iteration order matches list_symbols order
        iter_syms = Symbol[k for (k, _) in gdxfile]
        @test iter_syms == syms

        # Round-trip preserves order
        outfile = joinpath(tempdir(), "gdx_jl_order_test.gdx")
        write_gdx(outfile, gdxfile)
        gdx2 = read_gdx(outfile)
        @test list_symbols(gdx2) == syms

        rm(outfile, force=true)
    end

    @testset "Set element text round-trip" begin
        set_df = DataFrame(
            dim1 = ["seattle", "san-diego", "topeka"],
            element_text = ["rainy city", "sunny city", ""]
        )
        s = GDXSet("cities", "transport cities", ["*"], set_df)
        gdxfile = GDXFile("", Dict{Symbol,GDXSymbol}(:cities => s))

        outfile = joinpath(tempdir(), "gdx_jl_elemtext_test.gdx")
        write_gdx(outfile, gdxfile)

        gdx2 = read_gdx(outfile)
        result = gdx2[:cities]
        @test "element_text" in names(result)
        @test result.element_text[1] == "rainy city"
        @test result.element_text[2] == "sunny city"
        @test result.element_text[3] == ""

        rm(outfile, force=true)
    end

    @testset "Set without element text has no extra column" begin
        set_df = DataFrame(dim1 = ["a", "b", "c"])
        s = GDXSet("simple", "no text", ["*"], set_df)
        gdxfile = GDXFile("", Dict{Symbol,GDXSymbol}(:simple => s))

        outfile = joinpath(tempdir(), "gdx_jl_notext_test.gdx")
        write_gdx(outfile, gdxfile)

        gdx2 = read_gdx(outfile)
        @test !("element_text" in names(gdx2[:simple]))

        rm(outfile, force=true)
    end

    @testset "Alias round-trip" begin
        set_df = DataFrame(dim1 = ["a", "b", "c"])
        s = GDXSet("i", "original set", ["*"], set_df)
        a = GDXAlias("j", "alias for i", "i")
        gdxfile = GDXFile("", Dict{Symbol,GDXSymbol}(:i => s, :j => a))

        outfile = joinpath(tempdir(), "gdx_jl_alias_test.gdx")
        write_gdx(outfile, gdxfile)

        gdx2 = read_gdx(outfile)
        @test :i in list_sets(gdx2)
        @test :j in list_aliases(gdx2)

        alias_sym = get_symbol(gdx2, :j)
        @test alias_sym isa GDXAlias
        @test alias_sym.alias_for == "i"

        # Accessing alias records resolves to the aliased set's records
        @test gdx2[:j] == gdx2[:i]

        rm(outfile, force=true)
    end

    @testset "GDXAlias show" begin
        a = GDXAlias("j", "", "i")
        io = IOBuffer()
        show(io, a)
        @test occursin("j", String(take!(io)))
    end

    @testset "Domain preservation on round-trip (issue #3)" begin
        set_df = DataFrame(i = ["a", "b", "c"])
        s = GDXSet("i", "index set", ["*"], set_df)
        par_df = DataFrame(i = ["a", "b", "c"], value = [10.0, 20.0, 30.0])
        p = GDXParameter("x", "A parameter over i", ["i"], par_df)
        gdxfile = GDXFile("", Dict{Symbol,GDXSymbol}(:i => s, :x => p))

        outfile = joinpath(tempdir(), "gdx_jl_domain_test.gdx")
        write_gdx(outfile, gdxfile)

        gdx2 = read_gdx(outfile)
        x2 = get_symbol(gdx2, :x)
        @test x2.domain == ["i"]
        @test names(gdx2[:x])[1] == "i"

        rm(outfile, force=true)
    end

    @testset "Domain preservation for variables (issue #3)" begin
        set_df = DataFrame(i = ["a", "b", "c"])
        s = GDXSet("i", "index set", ["*"], set_df)
        var_df = DataFrame(
            i = ["a", "b", "c"],
            level = [1.0, 2.0, 3.0],
            marginal = [0.0, 0.0, 0.0],
            lower = [-Inf, -Inf, -Inf],
            upper = [Inf, Inf, Inf],
            scale = [1.0, 1.0, 1.0]
        )
        v = GDXVariable("y", "A variable over i", ["i"], VarFree, var_df)
        gdxfile = GDXFile("", Dict{Symbol,GDXSymbol}(:i => s, :y => v))

        outfile = joinpath(tempdir(), "gdx_jl_domain_var_test.gdx")
        write_gdx(outfile, gdxfile)

        gdx2 = read_gdx(outfile)
        y2 = get_symbol(gdx2, :y)
        @test y2.domain == ["i"]
        @test names(gdx2[:y])[1] == "i"

        rm(outfile, force=true)
    end

    @testset "Domain preservation for equations (issue #3)" begin
        set_df = DataFrame(i = ["a", "b"])
        s = GDXSet("i", "index set", ["*"], set_df)
        eq_df = DataFrame(
            i = ["a", "b"],
            level = [1.0, 2.0],
            marginal = [0.5, 0.6],
            lower = [-Inf, -Inf],
            upper = [Inf, Inf],
            scale = [1.0, 1.0]
        )
        eq = GDXEquation("myeq", "test eq", ["i"], EqE, eq_df)
        gdxfile = GDXFile("", Dict{Symbol,GDXSymbol}(:i => s, :myeq => eq))

        outfile = joinpath(tempdir(), "gdx_jl_domain_eq_test.gdx")
        write_gdx(outfile, gdxfile)

        gdx2 = read_gdx(outfile)
        eq2 = get_symbol(gdx2, :myeq)
        @test eq2.domain == ["i"]
        @test names(gdx2[:myeq])[1] == "i"

        rm(outfile, force=true)
    end

    @testset "Multi-dimensional domain preservation (issue #3)" begin
        si = GDXSet("i", "rows", ["*"], DataFrame(i = ["a", "b"]))
        sj = GDXSet("j", "cols", ["*"], DataFrame(j = ["x", "y"]))
        par_df = DataFrame(
            i = ["a", "a", "b", "b"],
            j = ["x", "y", "x", "y"],
            value = [1.0, 2.0, 3.0, 4.0]
        )
        p = GDXParameter("cost", "transport cost", ["i", "j"], par_df)
        gdxfile = GDXFile("", Dict{Symbol,GDXSymbol}(:i => si, :j => sj, :cost => p))

        outfile = joinpath(tempdir(), "gdx_jl_domain_2d_test.gdx")
        write_gdx(outfile, gdxfile)

        gdx2 = read_gdx(outfile)
        cost2 = get_symbol(gdx2, :cost)
        @test cost2.domain == ["i", "j"]
        @test names(gdx2[:cost])[1:2] == ["i", "j"]

        rm(outfile, force=true)
    end

    @testset "Domain preservation with GAMS-generated file (issue #3)" begin
        gdx1 = read_gdx(test_gdx)

        p1 = get_symbol(gdx1, :p)
        original_domain = p1.domain

        outfile = joinpath(tempdir(), "gdx_jl_gams_domain_rt.gdx")
        write_gdx(outfile, gdx1)

        gdx2 = read_gdx(outfile)
        p2 = get_symbol(gdx2, :p)
        @test p2.domain == original_domain

        x1 = get_symbol(gdx1, :x)
        x2 = get_symbol(gdx2, :x)
        @test x2.domain == x1.domain

        rm(outfile, force=true)
    end
end
