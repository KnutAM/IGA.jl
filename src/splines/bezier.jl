export BernsteinBasis, value

"""
BernsteinBasis subtype of JuAFEM:s interpolation struct
"""  
struct BernsteinBasis{dim,order} <: JuAFEM.Interpolation{dim,JuAFEM.RefCube,order} end

function JuAFEM.value(b::BernsteinBasis{1,order}, i, xi) where {order}
    @assert(0 < i < order+2)
    return _bernstein_basis_recursive(order, i, xi)
end

function JuAFEM.value(b::BernsteinBasis{2,order}, i, xi) where {order}
    n = order+1
    ix,iy = Tuple(CartesianIndices((n,n))[i])
    x = _bernstein_basis_recursive(order, ix, xi[1])
    y = _bernstein_basis_recursive(order, iy, xi[2])
    return x*y
end

JuAFEM.faces(::BernsteinBasis{2,order}) where order = ((1,2),)
JuAFEM.faces(::BernsteinBasis{2,2}) = ((1,2,3),(3,6,9),(9,8,7),(7,5,1))

JuAFEM.getnbasefunctions(b::BernsteinBasis{dim,order}) where {dim,order} = (order+1)^dim
JuAFEM.nvertexdofs(::BernsteinBasis{dim,order}) where {dim,order} = 1
JuAFEM.nedgedofs(::BernsteinBasis{dim,order}) where {dim,order} = 0
JuAFEM.nfacedofs(::BernsteinBasis{dim,order}) where {dim,order} = 0
JuAFEM.ncelldofs(::BernsteinBasis{dim,order}) where {dim,order} = 0

function _bernstein_basis_recursive(p::Int, i::Int, xi::T) where T
	if i==1 && p==0
		return 1
	elseif i < 1 || i > p+1
		return 0
	else
        return 0.5*(1 - xi)*_bernstein_basis_recursive(p-1,i,xi) + 0.5*(1 + xi)*_bernstein_basis_recursive(p-1,i-1,xi)
    end
end

"""
In isogeometric analysis, one can use the bezier basefunction together with a bezier-extraction operator to 
evaluate the bspline basis functions. However, they will be different for each element, so subtype `CellValues`
in order to be able to update the bezier extraction operator for each element
"""

struct BezierCellVectorValues{dim,T<:Real,M} <: JuAFEM.CellValues{dim,T,JuAFEM.RefCube}
    cv::JuAFEM.CellVectorValues{dim,T,JuAFEM.RefCube,M}
    current_cellid::Ref{Int}
    extraction_operators::Vector{Matrix{T}}
end

JuAFEM.getnbasefunctions(bcv::BezierCellVectorValues) = size(bcv.cv.N, 1)
JuAFEM.getngeobasefunctions(bcv::BezierCellVectorValues) = size(bcv.cv.M, 1)
JuAFEM.getnquadpoints(bcv::BezierCellVectorValues) = length(bcv.cv.qr_weights)
JuAFEM.getdetJdV(bcv::BezierCellVectorValues, i::Int) = bcv.cv.detJdV[i]
JuAFEM.shape_value(bcv::BezierCellVectorValues, qp::Int, i::Int) = bcv.cv.N[i, qp]

set_current_cellid!(bcv::BezierCellVectorValues, ie::Int) = bcv.current_cellid[]=ie

function JuAFEM.reinit!(bcv::BezierCellVectorValues, x::AbstractVector{Vec{dim,T}}) where {dim,T}
    JuAFEM.reinit!(bcv.cv, x) #call the normal reinit function first

    Cb = bcv.extraction_operators
    ie = bcv.current_cellid[]
    cv = bcv.cv
    #calculate the derivatives of the nurbs/bspline basis using the bezier-extraction operator
    
    dBdx = copy(cv.dNdx) # The derivatives of the bezier element
    B    = copy(cv.N)
    for iq in 1:length(cv.qr_weights)
        for ib in 1:JuAFEM.getnbasefunctions(cv)
            d = ((ib-1)%dim) +1
            a = convert(Int, ceil(ib/dim))

            dNdx = bezier_transfrom(Cb[ie][a,:], dBdx[d:dim:end,iq])
            cv.dNdx[ib, iq] = dNdx

            N = bezier_transfrom(Cb[ie][a,:], B[d:dim:end,iq])
            cv.N[ib, iq] = N
        end
    end
end

"""
Bsplines sutyping JuAFEM interpolation
"""
struct BSplineInterpolation{dim,T} <: JuAFEM.Interpolation{dim,JuAFEM.RefCube,1} 
    INN::Matrix{Int}
    IEN::Matrix{Int}
    knot_vectors::NTuple{dim,Vector{T}}
    orders::NTuple{dim,Int}
    current_element::Ref{Int}
end

function BSplineInterpolation(INN::AbstractMatrix, IEN::AbstractMatrix, knot_vectors::NTuple{dim,Vector{T}}, orders::NTuple{dim,T}) where{dim,T}
    return BSplineInterpolation{dim,T}(IEN, INN, knot_vectors, orders, Ref(1))
end
JuAFEM.getnbasefunctions(b::BSplineInterpolation) = prod(b.orders.+1)

set_current_element!(b::BSplineInterpolation, iel::Int) = (b.current_element[] = iel)

function JuAFEM.value(b::BSplineInterpolation{2,T}, i, xi) where {T}
    global_basefunk = b.IEN[i,b.current_element[]]

    _ni,_nj = b.INN[b.IEN[1,b.current_element[]],:] #The first basefunction defines the element span
    ni,nj = b.INN[global_basefunk,:] # Defines the basis functions nurbs coord

    gp = xi
    #xi will be in interwall [-1,1] most likely
    ξ = 0.5*((b.knot_vectors[1][_ni+1] - b.knot_vectors[1][_ni])*gp[1] + (b.knot_vectors[1][_ni+1] + b.knot_vectors[1][_ni]))
    #dξdξ̃ = 0.5*(local_knot[ni+1] - local_knot[ni])
    η = 0.5*((b.knot_vectors[2][_nj+1] - b.knot_vectors[2][_nj])*gp[2] + (b.knot_vectors[2][_nj+1] + b.knot_vectors[2][_nj]))

    #dηdη̂ = 0.5*(local_knot[nj+1] - local_knot[nj])
    x = _bspline_basis_value_alg1(b.orders[1], b.knot_vectors[1], ni, ξ)
    y = _bspline_basis_value_alg1(b.orders[2], b.knot_vectors[2], nj, η)

    return x*y
end