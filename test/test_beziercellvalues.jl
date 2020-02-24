@testset "bezier_cellvalues" begin
    dim = 2
    order = (2,2)
    knots = (Float64[0,0,0,1,1,1],Float64[0,0,0,1,1,1])

    C,nbe = IGA.compute_bezier_extraction_operators(order..., knots...)
    
    b1 = BernsteinBasis{dim, order}()
    qr = JuAFEM.QuadratureRule{dim,JuAFEM.RefCube}(2)
    bcv = BezierCellVectorValues(qr, b1, C)

    IGA.set_current_cellid!(bcv, 1)
    JuAFEM.reinit!(bcv, JuAFEM.reference_coordinates(b1))
    
    #If the bezier extraction operator is diagonal(ones), then the bezier basis functions is the same as the bsplines
    @test all(bcv.N .== bcv.cv.N)
end