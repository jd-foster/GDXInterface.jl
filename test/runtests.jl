import Test: @testset, @test
import DataFrames: DataFrame
using GDXInterface

const TEST_DATA_DIR = joinpath(@__DIR__, "test_data")
ispath(TEST_DATA_DIR)

println("\n" * "-"^30 * "\nGDXFile Tests\n" * "-"^30)
include("test_gdxfile.jl")