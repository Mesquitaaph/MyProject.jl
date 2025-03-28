function montaLG(ne, base)
  LG = zeros(Int64, ne, base.nB)

  LG1 = [(base.nB-1)*i - (base.nB-2) for i in 1:ne]
  
  for e in 1:ne
      for a in 1:base.nB
          @inbounds LG[e,a] = LG1[e] + (a-1)
      end
  end

  return LG'
end

function montaEQ(ne, neq, base)
  EQ = zeros(Int64, (base.nB-1)*ne+1, 1)

  EQ[1] = neq+1; EQ[end] = neq+1
  
  for i in 2:(base.nB-1)*ne
      @inbounds EQ[i] = i-1
  end

  return EQ
end

function PHI_original(P, n_dim=1)
  if n_dim == 1
    return 2.0^-n_dim * [
      1-P[1],
      1+P[1]
    ]
  elseif n_dim == 2
    return 2.0^-n_dim * [
      (1-P[1]) * (1-P[2]),
      (1+P[1]) * (1-P[2]),
      (1-P[1]) * (1+P[2]),
      (1+P[1]) * (1+P[2]),
    ]
  else
    return Nothing
  end
end

function dPHI(P, n_dim=1)
  if n_dim == 1
    return 2.0^-n_dim * [
      -1,
      1
    ]
  elseif n_dim == 2
    return 2.0^-n_dim * [
      (1-P[1]) * (1-P[2]),
      (1+P[1]) * (1-P[2]),
      (1-P[1]) * (1+P[2]),
      (1+P[1]) * (1+P[2]),
    ]
  else
    return error("Dimensão não implementada")
  end
end

function avaliar_quadratura(base_func::Function, npg::Int64, n_funcs::Int64, n_dim::Int64)
  P, W = legendre(npg)

  phiP = zeros(npg, n_funcs)
  for a in 1:n_funcs
      for ksi in 1:npg
          phiP[ksi, a] = base_func(P[ksi], n_dim)[a]
      end
  end
  return phiP, P, W
end

function xksi(ksi, e, X)
  h = X[e+1] - X[e]
  return h/2*(ksi+1) + X[e]
end

function montaK(base, ne, neq, dx, alpha, beta, gamma, EQoLG::Matrix{Int64}, X)
  npg = base.p+1
  
  phiP, P, W = avaliar_quadratura(PHI_original, npg, 2, 1)
  dphiP, P, W = avaliar_quadratura(dPHI, npg, 2, 1)

  Ke = zeros(Float64, 2, 2)

  for a in 1:2
      for b in 1:2
          for ksi in 1:npg
              @inbounds parcelaNormal = beta*dx/2 * W[ksi] * phiP[ksi, a] * phiP[ksi, b];
              @inbounds parcelaDerivada1 = gamma * W[ksi] * phiP[ksi, a] * dphiP[ksi, b];
              @inbounds parcelaDerivada2 = 2*alpha/dx * W[ksi] * dphiP[ksi, a] * dphiP[ksi, b];

              @inbounds Ke[a,b] += parcelaDerivada2 + parcelaNormal + parcelaDerivada1
          end
      end
  end

  K = BandedMatrix(Zeros(neq, neq), (base.nB-1, base.nB-1))
  for e in 1:ne
      for b in 1:2
          @inbounds j = EQoLG[b, e]
          for a in 1:2
              @inbounds i = EQoLG[a, e]
              if i <= neq && j <= neq
                  @inbounds K[i,j] += Ke[a,b]
              end
          end
      end
  end

  return sparse(K)
end

function montaF(base, ne, neq, X, f::Function, EQoLG)
  npg = 5

  phiP, P, W = avaliar_quadratura(PHI_original, npg, 2, 1)
  dx = 1/ne
  
  F = zeros(neq+1)
  xPTne = zeros(npg, ne)
  for e in 1:ne
      for ksi in 1:npg
          @inbounds fxptne = f(xksi(P[ksi], e, X))
          @inbounds xPTne[ksi, e] = fxptne
          for a in 1:2
              @inbounds partial = dx/2 * W[ksi] * phiP[ksi, a]
              @inbounds i = EQoLG[a, e]
              @inbounds F[i] += partial * fxptne
          end
      end
  end

  return F[1:neq], xPTne
end

function solveSys(run_values::RunValues, base, ne)
  (; alpha, beta, gamma, a, b, f) = run_values
  dx = 1/ne;
  neq = base.neq;

  X = a:dx:b
  
  EQ = montaEQ(ne, neq, base); LG = montaLG(ne, base)
  EQoLG = EQ[LG]

  EQ = nothing; LG = nothing;
  
  K = montaK(base, ne, neq, dx, alpha, beta, gamma, EQoLG, X)

  F, xPTne = montaF(base, ne, neq, X, f, EQoLG)

  # display("Matriz K RAPHAEL:")
  # display(K)
  # display("Vetor F RAPHAEL:")
  # display(F)

  C = zeros(Float64, neq)

  C .= K\F
  # display("Solução aproximada U RAPHAEL:")
  # display(C)

  F = nothing; K = nothing;

  return C, EQoLG, xPTne
end