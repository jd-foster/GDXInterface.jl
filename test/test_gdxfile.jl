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
    # Create test file using GAMS
    test_gdx = joinpath(TEST_DATA_DIR, "gams_gdx_test.gdx")
    ispath(test_gdx)
    
    @testset "Reading GDX file created by GAMS" begin
        gdxfile = read_gdx(test_gdx)
        
        @test :i in list_sets(gdxfile)
        @test :p in list_parameters(gdxfile)
        
        # Check parameter values
        p = gdxfile[:p]
        @test "value" in names(p)
        @test p.value == [1.5, 2.5, 3.5]
    end
    
    @testset "Reading variables" begin
        gdxfile = read_gdx(test_gdx)
        
        @test :x in list_variables(gdxfile)
        @test :y in list_variables(gdxfile)
        
        # Check variable x (free variable)
        x = gdxfile[:x]
        @test "level" in names(x)
        @test "marginal" in names(x)
        @test "lower" in names(x)
        @test "upper" in names(x)
        @test x.level == [10.0, 20.0, 30.0]
        @test x.marginal ≈ [0.1, 0.2, 0.3]
        
        # Check variable y (positive variable with upper bound)
        y = gdxfile[:y]
        @test y.level == [5.0, 10.0, 15.0]
        @test all(y.lower .== 0.0)  # positive variable has lower bound 0
        @test all(y.upper .== 100.0)
        
    end
    
    @testset "Write and read round-trip" begin
        # Create test data
        supply = DataFrame(
            i = ["seattle", "san-diego"],
            value = [350.0, 600.0]
        )
        
        demand = DataFrame(
            j = ["new-york", "chicago", "topeka"],
            value = [325.0, 300.0, 275.0]
        )
        
        # Write to GDX
        outfile = joinpath(tempdir(), "gdx_jl_write_test.gdx")
        write_gdx(outfile, "supply" => supply, "demand" => demand)
        
        # Read back
        gdxfile = read_gdx(outfile)
        
        @test :supply in list_parameters(gdxfile)
        @test :demand in list_parameters(gdxfile)
        @test gdxfile[:supply].value == [350.0, 600.0]
        @test gdxfile[:demand].value == [325.0, 300.0, 275.0]
        
        # Test property access
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
        # Domain names aren't preserved when writing without explicit domains
        # so they come back as dim1, dim2, etc.
        @test length(names(result)) == 3  # 2 dimensions + value
        @test "value" in names(result)
        
        rm(outfile, force=true)
    end
    
    @testset "Integer parsing" begin
        df = DataFrame(year = ["2020", "2021", "2022"], value = [1.0, 2.0, 3.0])
        
        outfile = joinpath(tempdir(), "gdx_jl_int_test.gdx")
        write_gdx(outfile, "data" => df)
        
        gdxfile = read_gdx(outfile, parse_integers=true)
        # Domain names become dim1 when round-tripped through GDX
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
        
        # Test show
        io = IOBuffer()
        show(io, gdxfile)
        output = String(take!(io))
        @test occursin("GDXFile:", output)
        @test occursin("param", output)
        
        # Test propertynames
        props = propertynames(gdxfile)
        @test :path in props
        @test :symbols in props
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
end
