include(joinpath(@__DIR__, "../../", "counting.jl"))
include(joinpath(@__DIR__, "../../", "recording.jl"))
include(joinpath(@__DIR__, "../../", "adaptive_bilevel_algorithms.jl"))
include(joinpath(@__DIR__, "../../", "linops.jl"))
include(joinpath(@__DIR__, "../../", "libsvm.jl"))


using Random
using LinearAlgebra
using Statistics

using Plots
using LaTeXStrings
using DelimitedFiles

using ProximalOperators: NormL1, SqrNormL2

pgfplotsx()

function run_logreg_l2_data(
    filename,
    ::Type{T} = Float64;
    tol = 1e-5,
    maxit = 1000,
) where {T}
    @info "Start L2 Logistic Regression ($filename)"

    X, y = load_libsvm_dataset(filename, T, labels = [0.0, 1.0])

    m, n = size(X)
    n = n + 1

    f1 = Zero()
    f2 = LogisticLoss(X, y)
    g1 = SqrNormL2()
    g2 = Zero()

    f1_BiGSAM = SqrNormL2()


    obj = obj1(f1, g1)
    # preparation for Big SAM
    muf1 = 1 # strong convexity modulus of f1_BGSAM
    Lf1 = 1 # smoothness modulus of f1_BGSAM
    Lf2 = norm(X)^2 / (4 * n)

    @info "Getting accurate solution"

    sol_star, numit, record_fixed = adaptive_bilevel_LS(
        zeros(n),
        f1 = f1,
        f2 = Counting(f2),
        g1 = g1,
        g2 = g2,
        rule = OurRuleLS(gamma = 1.0),
        tol = tol,
        maxit = maxit * 20,
        record_fn = record_pg,
    )
    optimum = obj(sol_star)
    @info "high accuracy sol: $(optimum)"


    @info "Running solvers"

    @info "solver with bilevel problem with LS"

    sol, numit, record_Alg1LS = adaptive_bilevel_LS(
        zeros(n),
        f1 = f1,
        f2 = Counting(f2),
        g1 = g1,
        g2 = g2,
        rule = OurRuleLS(gamma = 1.0),
        tol = tol,
        maxit = maxit,
        record_fn = record_pg,
    )
    @info "Bilevel Alg with LS"
    @info "    iterations: $(numit)"
    @info "     objective: $(obj(sol))"

    @info "solver with bilevel problem with static stepsize"

    sol, numit, record_staBiM = adaptive_bilevel_static(
        zeros(n),
        f1 = f1,
        f2 = Counting(f2),
        g1 = g1,
        g2 = g2,
        rule = OurRule(sigma = 1.0, Lf = [0.0, Lf2]),
        tol = tol,
        maxit = maxit,
        record_fn = record_pg,
    )
    @info "Bilevel Alg with LS"
    @info "    iterations: $(numit)"
    @info "     objective: $(obj(sol))"

    @info "solver with bilevel problem with BiGSAM"

    sol, numit, record_BiGSAM = BiGSAM(
        zeros(n),
        f1 = f1_BiGSAM,
        f2 = Counting(f2),
        g = g2,
        gamma = 1 / Lf2,
        tau = 2 / (Lf1 + muf1),
        tol = tol,
        maxit = maxit,
        record_fn = record_pg,
    )
    @info "BiGSAM"
    @info "    iterations: $(numit)"
    @info "     objective: $(obj(sol))"

    @info "solver with bilevel problem with Solodov"

    record_Solodov = Vector{}(undef, 3)
    for (i, c) in [(1, 1), (2, 10), (3, 100)]
        sol, numit, record_Solodov[i] = backtracking_Solodov(
            zeros(n),
            f1 = f1_BiGSAM,
            f2 = Counting(f2),
            g = g2,
            gamma0 = c / Lf2, ###### to test
            tol = tol,
            maxit = maxit,
            record_fn = record_pg,
        )
        @info "projprad"
        @info "    iterations: $(numit)"
        @info "     objective: $(obj(sol))"
    end

    @info "Collecting plot data"
    to_plot = Dict(
        "AdaBilevel-LS" => concat_dicts(record_Alg1LS |> subsample(100)),
        "staBiM" => concat_dicts(record_staBiM |> subsample(100)),
        "BiGSAM" => concat_dicts(record_BiGSAM |> subsample(100)),
        "Solodov1" => concat_dicts(record_Solodov[1] |> subsample(100)),
        "Solodov2" => concat_dicts(record_Solodov[2] |> subsample(100)),
        "Solodov3" => concat_dicts(record_Solodov[3] |> subsample(100)),
    )


    @info "Plotting"

    plot(
        title = "Quadratic upper level",
        xlabel = L"\nabla f_1\ \mbox{evaluations}",
        ylabel = L"\|v\|, v \in \partial \varphi_2(x^k)",
    )
    for k in keys(to_plot)
        plot!(
            to_plot[k][:grad_evals_total],
            max.(1e-14, to_plot[k][:norm_gradf2]),
            yaxis = :log,
            label = k,
        )
    end
    savefig(joinpath(@__DIR__, "Logistic_Regressionres.pdf"))

    plot(
        title = "Quadratic upper level",
        xlabel = L"\nabla f_2\ \mbox{evaluations}",
        ylabel = L"|f_1(x^k) - \varphi_{\star}|",
    )
    for k in keys(to_plot)
        plot!(
            to_plot[k][:grad_evals_total],
            abs.(to_plot[k][:objective1] .- optimum),
            yaxis = :log,
            label = k,
        )
    end
    savefig(joinpath(@__DIR__, "Logistic_Regressioncost.pdf"))

    plot(
        title = "Quadratic upper level",
        xlabel = L"\nabla f_2\ \mbox{evaluations}",
        ylabel = L"\gamma",
    )
    for k in keys(to_plot)
        plot!(
            to_plot[k][:grad_evals_total],
            max.(1e-14, to_plot[k][:gamma]),
            # yaxis = :log,
            label = k,
        )
    end
    savefig(joinpath(@__DIR__, "Logistic_Regressiongamma.pdf"))


    # r = pf
    @info "Exporting plot data"

    save_labels = Dict(
        "AdaBilevel-LS" => "AdaBilevel-LS",
        "staBiM" => "staBiM",
        "BiGSAM" => "BiGSAM",
        "Solodov1" => "Solodov1",
        "Solodov2" => "Solodov2",
        "Solodov3" => "Solodov3",
    )
    for k in keys(to_plot)
        d = length(to_plot[k][:grad_evals_total])
        rr = Int(ceil(d / 80)) # keeping at most 50 data points
        output =
            [to_plot[k][:grad_evals_total] (abs.(to_plot[k][:objective1] .- optimum)) ./
                                           max(abs(optimum), 1.0)]
        red_output = output[1:rr:end, :]
        filename = "$(save_labels[k])-$m-$n.txt"
        filepath = joinpath(@__DIR__, "plotdata", "uppercost", filename)
        mkpath(dirname(filepath))
        open(filepath, "w") do io
            writedlm(io, red_output)
        end
    end


    for k in keys(to_plot)
        d = length(to_plot[k][:grad_evals_total])
        rr = Int(ceil(d / 80)) # keeping at most 50 data points
        output = [to_plot[k][:grad_evals_total] max.(1e-14, to_plot[k][:norm_gradf2])]
        red_output = output[1:rr:end, :]
        filename = "$(save_labels[k])-$m-$n.txt"
        filepath = joinpath(@__DIR__, "plotdata", "loweropt", filename)
        mkpath(dirname(filepath))
        open(filepath, "w") do io
            writedlm(io, red_output)
        end
    end

end


function main(; maxit = 3000)
    run_logreg_l2_data(joinpath(@__DIR__, "..", "datasets", "mushrooms"), maxit = maxit)
    run_logreg_l2_data(joinpath(@__DIR__, "..", "datasets", "a5a"), maxit = maxit)
    run_logreg_l2_data(joinpath(@__DIR__, "..", "datasets", "phishing"), maxit = maxit)
end

if abspath(PROGRAM_FILE) == @__FILE__
    main()
end


sigm(z) = 1 / (1 + exp(-z))

struct LogisticLoss{TX,Ty}
    X::TX
    y::Ty
end

function (f::LogisticLoss)(w)
    probs = sigm.(f.X * w[1:end-1] .+ w[end])
    return -mean(f.y .* log.(probs) + (1 .- f.y) .* log.(1 .- probs))
end

function gradient(f::LogisticLoss, w)
    probs = sigm.(f.X * w[1:end-1] .+ w[end])
    N = size(f.y, 1)
    g = f.X' * (probs - f.y) ./ N
    push!(g, mean(probs - f.y))  # for bias: X_new = [X, 1] 
    return g, f(w)
end

function gradient(f::SqrNormL2, w)
    return w, 0.5 * norm(w)^2
end




struct obj1{Tf,Tg}
    f1::Tf                 # differentiable term  
    g1::Tg                 # nonsmooth term 
end


function (S::obj1)(x)
    y = try
        nocount(S.f1)(x) + nocount(S.g1)(x)
    catch e
        S.f1(x)
    end
    return y
end
