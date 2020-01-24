
export bezier_transfrom!, compute_bezier_extraction_operators

function compute_bezier_points(Ce::Matrix{T}, control_points::Vector{Vec{sdim,T}}) where {T,sdim}

	n_new_points = size(Ce,2)
	bezierpoints = zeros(Vec{sdim,T}, n_new_points)
	for i in 1:n_new_points
		for (ic, p) in enumerate(control_points)
			bezierpoints[i] += Ce[ic,i]*p
		end
	end
	return bezierpoints

end

function bezier_transfrom!(bezier::Vector{TENSOR}, Ce::AbstractMatrix, control_points::Vector{TENSOR}) where {T,sdim,TENSOR}

	n_new_points = size(Ce,2)
	#bezier = zeros(TENSOR, n_new_points)
	for i in 1:n_new_points
		for (ic, p) in enumerate(control_points)
			bezier[i] += Ce[i, ic]*p
		end
	end
	#return bezierpoints

end

function bezier_transfrom!(bezier::TENSOR, Ce::AbstractVector, control_points::Vector{TENSOR}) where {T,sdim,TENSOR}

	for (ic, p) in enumerate(control_points)
		bezier += Ce[ic]*p
	end

end

compute_bezier_extraction_operators(o::NTuple{pdim,Int}, U::NTuple{pdim,Vector{T}}) where {pdim,T} = 
	compute_bezier_extraction_operators(o...,U...)

function compute_bezier_extraction_operators(p::Int, q::Int, knot1::Vector{T}, knot2::Vector{T}) where T

	Ce1, nbe1 = compute_bezier_extraction_operators(p, knot1)
	Ce2, nbe2 = compute_bezier_extraction_operators(q, knot2)
	C = Vector{Matrix{T}}()
	for j in 1:nbe2
		for i in 1:nbe1
			_C = kron(Ce2[j],Ce1[i])
			push!(C,_C)
		end
	end
	return C, nbe1*nbe2
end

function compute_bezier_extraction_operators(p::Int, knot::Vector{T}) where T
	a = p+1
	b = a+1
	nb = 1
	m = length(knot)
	C = [Matrix(Diagonal(ones(T,p+1)))]

	while b < m
		push!(C, Matrix(Diagonal(ones(T,p+1))))
		i = b
		while b<m && knot[b+1]==knot[b]
			 b+=1;
		end;
		mult = b-i+1

		if mult < p + 1
			
			α = zeros(T,3)
			for j in p:-1:(mult+1)
				α[j-mult] = (knot[b]-knot[a])/(knot[a+j]-knot[a])
			end
			r = p-mult

			for j in 1:r
				save = r-j+1
				s = mult+j

				for k in (p+1):-1:(s+1)
					C[nb][:,k] = α[k-s]*C[nb][:,k] + (1.0-α[k-s])*C[nb][:,k-1]
				end
				if b<m
					C[nb+1][save:(j+save),save] = C[nb][(p-j+1):(p+1), p+1]
				end
			end
			nb += 1
			if b<m
				a=b
				b+=1
			end
		end
	end

	#The last C-matrix is not used
	#pop!(C)
	C = C[1:nb]
	return C, nb
end