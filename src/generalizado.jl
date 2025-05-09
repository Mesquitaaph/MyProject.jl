function jacobiano(n_dim, Xᵉ, ∇Φξ, ξ)
  # Monta a matriz jacobiana
  M = Matrix{Float64}(undef, n_dim, n_dim)
  for i in 1:n_dim
    for j in 1:n_dim
      M[i,j] = dot(Xᵉ[i], ∇Φξ[j][ξ,:])
    end
  end

  # Calcula o determinante Jacobiano
  detJ = det(M)

  return M, detJ
end

function quadratura_gauss(npg::Int64, n_dim::Int64)
  p, w = legendre(npg)

  # Declara as listas de pontos de Gauss e seus respectivos pesos
  P = Vector{Tuple}(undef, npg^n_dim)
  W = similar(P)

  # Os pontos de Gauss são definidos como combinações dos n_dim eixos
  # A ordem das combinações é do eixo de maior número para o menor
  # Exemplo para n_dim = 2: para trocar o ponto no eixo ξ₁ primeiro passa por todos os pontos no eixo ξ₂.
  for i in 1:npg^n_dim
    ponto = ()
    peso = ()
    for d in 1:n_dim
      idx_global = floor((Float64(npg)^(n_dim-d) + i-1) * Float64(npg)^-(n_dim-d))
      idx = Int((idx_global-1) % npg)+1
      ponto = (ponto..., p[idx])
      peso = (peso..., w[idx])
    end
    P[i] = ponto
    W[i] = peso
  end

  return P, W
end

function quadratura_ϕ(base, npg, n_dim)
  P, W = quadratura_gauss(npg, n_dim)
  n_funcs = base.nB

  ϕP = zeros(npg^n_dim, n_funcs^n_dim)
  # Para todos os pontos de Gauss, avalia as ϕ locais
  for ξ in 1:npg^n_dim
    ϕP[ξ, :] .= ϕ_geral(P[ξ]...)[1]
  end

  return ϕP, P, W
end

function quadratura_∇ϕ(base, npg, n_dim)
  P, W = quadratura_gauss(npg, n_dim)
  n_funcs = base.nB

  ∇ϕP = ()
  for d in 1:n_dim
    ∂ϕᵢP = zeros(npg^n_dim, n_funcs^n_dim)

    # Para todos os pontos de Gauss, avalia as ∂ϕᵢ locais (i = d)
    for ξ in 1:npg^n_dim
      ∂ϕᵢP[ξ, :] .= ∇ϕ_geral(P[ξ]...)[d]
    end
    ∇ϕP = (∇ϕP..., ∂ϕᵢP)
  end

  return ∇ϕP, P, W
end

function mudanca_variavel_xξ(Xᵉ, Φξ, n_dim)
  x = ()

  # Mapeia as coordenadas físicas x = (x₁, x₂, xᵢ...) a partir de ξ = (ξ₁, ξ₂, ξᵢ...)
  for d in 1:n_dim
    x = (x..., dot(Xᵉ[d], Φξ))
  end
  return x
end

function elem_coords(malha::Malha, e::Int64)
  (; LG, EQ, n_dim, coords) = malha

  # Índices dos vértices/funções globais do elemento finito Ωᵉ
  nosᵉ_idx = LG[:,e]
    
  # Coordenadas dos vértices do elemento finito Ωᵉ
  Xᵉ = ()
  for d in 1:n_dim
    Xᵉ = (Xᵉ..., coords[d][nosᵉ_idx])
  end
  
  # Numeração de equação dos índices no vetor nosᵉ_idx
  eqs_idx = EQ[nosᵉ_idx]

  return eqs_idx, Xᵉ
end

function montaKᵉ_geral!(Kᵉ, Xᵉ, P, W, Φξ, ∇Φξ, n_dim, dx, run_values::RunValues)
  # Zera as entradas da matriz local Kᵉ
  fill!(Kᵉ, 0.0)

  # Função que retorna o gradiente de Φ, dado um ponto de Gauss e a numeração da função local
  function ∇Φ(ξ, a)
    return [∇Φξ[dim][ξ, a] for dim in 1:n_dim]
  end
  
  (; α, β, γ) = run_values

  npg = length(P)

  # Itera sobre os pontos de Gauss (combinações)
  for ξ in 1:npg
    # Vetor com o valor das funções locais Φ avaliadas no ponto de Gauss ξ = (ξ₁, ξ₂, ξᵢ...)
    ϕᵉ = Φξ[ξ,:]

    # Matriz e determinante do Jacobiano
    M, detJ = jacobiano(n_dim, Xᵉ, ∇Φξ, ξ)
    @assert detJ > 0 "O determinante jacobiano deve ser positivo"
    
    # Calcula a matriz H que aplica a mudança de variável de ∇ϕᵉ_a para ∇Φ_a
    M⁻¹ = inv(M); Hᵀ = M⁻¹*detJ
    H = transpose(Hᵀ)

    # Calcula o peso total do ponto de Gauss ξ = (ξ₁, ξ₂, ξᵢ...)
    WW = prod(W[ξ])
    
    # Calcula a contribuição de quadratura e acumula o valor na matriz Kᵉ
    for a in 1:2^n_dim
      @inbounds for b in 1:2^n_dim
        # Aplica a mudança de variável de ∇ϕᵉ_a para ∇Φ_a
        ∇ϕᵉ_a = 1/detJ * H * ∇Φ(ξ, a)
        ∇ϕᵉ_b = 1/detJ * H * ∇Φ(ξ, b)

        # Calcula a contribuição da parcela com α 
        parcelaDerivada2 = α * dot(∇ϕᵉ_b, ∇ϕᵉ_a) * detJ

        # Calcula a contribuição da parcela com β
        parcelaNormal = β * ϕᵉ[a] * ϕᵉ[b] * detJ

        # Calcula a contribuição da parcela com γ (funcionava em 1D)
        parcelaDerivada1 = 0 #γ * vec_Φ[a] * ∇ϕᵉ_b

        Kᵉ[a,b] += WW * (parcelaDerivada2 + parcelaNormal + parcelaDerivada1)
      end
    end
  end
end

function montaK_geral(run_values::RunValues, malha::Malha)
  (; ne, neq, dx, n_dim, Nx, base) = malha

  npg = 2
  
  # Avalia as ϕ e ∇ϕ nos pontos de Gauss
  ϕξ, P, W = quadratura_ϕ(base, npg, n_dim)
  ∇ϕξ, P, W = quadratura_∇ϕ(base, npg, n_dim)
  
  # Define a banda da matriz K
  band = Nx[1]

  # Inicializa as matrizes locais e globais
  K = BandedMatrix(Zeros(neq, neq), (band, band))
  Kᵉ = zeros(Float64, 2^n_dim, 2^n_dim)
  
  # Itera sobre os elementos Ωᵉ
  for e in 1:ne
    eqs_idx, Xᵉ = elem_coords(malha::Malha, e::Int64)

    # Calcula a matriz local Kᵉ
    montaKᵉ_geral!(Kᵉ, Xᵉ, P, W, ϕξ, ∇ϕξ, n_dim, dx, run_values)

    # Itera sobre as colunas (b) e linhas (a) da matriz local Kᵉ
    @inbounds for b in 1:2^n_dim
      j = eqs_idx[b]
      for a in 1:2^n_dim
        i = eqs_idx[a]
        if i <= neq && j <= neq
          K[i,j] += Kᵉ[a,b]
        end
      end
    end
  end

  return sparse(K)
end

function montaFᵉ_geral!(Fᵉ, f, Xᵉ, P, W, ϕξ, ∇ϕξ, n_dim)
  # Zera as entradas do vetor local Fᵉ
  fill!(Fᵉ, 0.0)

  npg = length(P)

  # Itera sobre os pontos de Gauss (combinações)
  for ξ in 1:npg
    # Vetor com o valor das funções locais Φ avaliadas no ponto de Gauss ξ = (ξ₁, ξ₂, ξᵢ...)
    ϕᵉ = ϕξ[ξ,:]

    x = mudanca_variavel_xξ(Xᵉ, ϕᵉ, n_dim)
    
    # Matriz e determinante do Jacobiano
    M, detJ = jacobiano(n_dim, Xᵉ, ∇ϕξ, ξ)
    @assert detJ > 0 "O determinante jacobiano deve ser positivo"

    # Calcula o peso total do ponto de Gauss ξ = (ξ₁, ξ₂, ξᵢ...)
    WW = prod(W[ξ])

    # Calcula a contribuição de quadratura e acumula o valor no vetor Fᵉ
    for a in 1:2^n_dim
      @inbounds Fᵉ[a] += WW * f(x...) * ϕᵉ[a] * detJ
    end
  end
end

function montaF_geral(run_values::RunValues, malha::Malha)
  (; f) = run_values
  (; ne, neq, n_dim, base) = malha
  
  npg = 5

  # Avalia as ϕ e ∇ϕ nos pontos de Gauss
  ϕξ, P, W = quadratura_ϕ(base, npg, n_dim)
  ∇ϕξ, P, W = quadratura_∇ϕ(base, npg, n_dim)
  
  # Inicializa os vetores locais e globais
  F = zeros(neq+1)
  Fᵉ = zeros(2^n_dim)

  # Itera sobre os elementos Ωᵉ
  for e in 1:ne
    eqs_idx, Xᵉ = elem_coords(malha::Malha, e::Int64)
    
    # Calcula o vetor local Fᵉ
    montaFᵉ_geral!(Fᵉ, f, Xᵉ, P, W, ϕξ, ∇ϕξ, n_dim)
    
    # Adiciona a contribuição do elemento finito ao vetor global F
    for a in 1:2^n_dim
      i = eqs_idx[a]
      F[i] += Fᵉ[a]
    end
  end
  
  return F[1:neq]
end

function solveSys_geral(run_values::RunValues, malha::Malha)
  K = montaK_geral(run_values, malha)

  F = montaF_geral(run_values, malha)

  C = zeros(Float64, malha.neq)

  C .= K\F

  xPTne = zeros(1) # resquicio / lixo
  return C, malha.EQoLG, xPTne
end