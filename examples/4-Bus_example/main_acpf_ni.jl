using PowerFlowUnderUncertainty, LinearAlgebra, JuMP, Ipopt, DelimitedFiles, JLD
include("powersystem.jl")
include("init_ni.jl")
initSingleUncertainty()

### Non-intrusive PCE for stochastic power flow ###
## Take samples of power values, compute PF, perform regression for all needed variables.
numSamples = 20
maxDegree = deg

println("Setting up PF model.")
pf = Model(with_optimizer(Ipopt.Optimizer))
set_optimizer_attribute(pf, "print_level", 2) # set verbosity of Ipopt output. Default is 5.
addCoreDeterministic!(pf, sys)
addPVBusDeterministic!(pf)

## Model: Wrapper function for NI-algo.
# Input:  x - sampled value for active power of PQ bus.
# Return: dict of PF outputs.
function model(x)
    p, q = x, x * 0.85
    sys[:P][1] = p
    sys[:Q][1] = q
    resetPowerFlowConstraint!(pf, sys)
    optimize!(pf) # model function

    return Dict(:pg => value.(pf[:pg]),
        :qg => value.(pf[:qg]),
        :e => value.(pf[:e]),
        :f => value.(pf[:f]))
end

## Perform full non-intrusive computations
busRes = Dict(:pg => Array{Float64}(undef, 2, 0),
    :qg => Array{Float64}(undef, 2, 0),
    :e => Array{Float64}(undef, 4, 0),
    :f => Array{Float64}(undef, 4, 0))
X = sampleFromGaussianMixture(numSamples, μ, σ, w)

# Y = model.(X)
println("Running $numSamples deterministic PF calculations (model evalutations)...")
for x in X
    res = model(x)
    busRes[:pg] = hcat(busRes[:pg], res[:pg])
    busRes[:qg] = hcat(busRes[:qg], res[:qg])
    busRes[:e] = hcat(busRes[:e], res[:e])
    busRes[:f] = hcat(busRes[:f], res[:f])
end

# Perform the actual regression for PCE coefficients on pd, qd, e and f
println("Compute non-intrusive PCE coefficients...\n")
pce = computeCoefficientsNI(X, busRes, unc)

# Get PCE of currents, branch flows and demands
pf_state = getGridStateNonintrusive(pce, pf, sys, unc)
println("PCE coefficients:")
display(pf_state)

# Sample for parameter values, using their PCE representations
pf_samples = generateSamples(ξ, pf_state, sys, unc)
println("\nPCE model evaluations for samples ξ:")
display(pf_samples)
println()


### Store PCE coefficients ###
f_coeff = "coefficients/SPF_NI.jld"
save(f_coeff, "pf_state", pf_state)
println("PCE coefficients data saved to $f_coeff.\n")


### Plotting ###
mycolor = "red"
plotHistogram_bus(pf_samples[:pd], "pd", "./plots/non-intrusive"; fignum = 1 + 10, color = mycolor)
plotHistogram_bus(pf_samples[:qd], "qd", "./plots/non-intrusive"; fignum = 2 + 10, color = mycolor)
plotHistogram_bus(pf_samples[:pg], "pg", "./plots/non-intrusive"; fignum = 3 + 10, color = mycolor)
plotHistogram_bus(pf_samples[:qg], "qg", "./plots/non-intrusive"; fignum = 4 + 10, color = mycolor)
plotHistogram_nodal(pf_samples[:e], "e", "./plots/non-intrusive"; figbum = 5 + 10, color = mycolor)
plotHistogram_nodal(pf_samples[:f], "f", "./plots/non-intrusive"; figbum = 6 + 10, color = mycolor)


### POST PROCESSING ###
width, height, color = "3.9cm", "2.75cm", "black!40"
files_to_save = Dict(:v => Dict("name" => "voltage_magnitude",
        "color" => color,
        "width" => "2.95cm",
        "height" => height),
    :θ => Dict("name" => "voltage_angle",
        "color" => color,
        "width" => "2.95cm",
        "height" => height),
    :pg => Dict("name" => "active_power",
        "color" => color,
        "width" => width,
        "height" => height),
    :qg => Dict("name" => "reactive_power",
        "color" => color,
        "width" => width,
        "height" => height),
    :pd => Dict("name" => "active_power_demand",
        "color" => color,
        "width" => "4.7cm",
        "height" => height),
    :qd => Dict("name" => "reactive_power_demand",
        "color" => color,
        "width" => "4.7cm",
        "height" => height),
    :i => Dict("name" => "current_magnitude",
        "color" => color,
        "width" => width,
        "height" => height))
#  :pl_t => Dict("name"=>"active_power_to",
# 			"color"=>color,
# 			"width"=>width,
# 			"height"=>height),
#  :ql_t => Dict("name"=>"reactive_power_to",
# 			"color"=>color,
# 			"width"=>width,
# 			"height"=>height)

# Store bus and branch data as csv and tikz files
println()
createCSV(files_to_save, pf_samples)
println("CSV data saved to /csv.")
createTikz(files_to_save, pf_samples, "../csv/")
println("Tikz files saved to /tikz.")