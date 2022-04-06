using PowerFlowUnderUncertainty, PowerModels, Ipopt, JuMP, JLD

"""
30 Bus net: Sparse PCE for stochastic power flow.
10 Uncertainties: Bus 3(l2), 4(l3), 7(l4), 8(l5), 10(l6), 17(l11), 19(l13), 29(l19), 30(l20)  and Bus 13(g6).
Take samples of power values, compute PF, perform regression for all needed variables.
"""

caseFile = "case30.m"
numSamples = 50
maxDeg = 2
nUnc = 10
postProcessing = false
K = 50

println("\n\t\t===== Stochastic Power Flow: 30 Bus case, 10 Uncertainties, Sparse PCE =====\n")

## Read case file, initialize network uncertainties and corresponding values
include("init_ni.jl")
network_data = readCaseFile(caseFile)
sys = parseNetworkData(network_data)
# Define uncertain buses
p = [sys[:Pd][2],
     sys[:Pd][3], 
     sys[:Pd][4], 
     sys[:Pd][5], 
     sys[:Pd][6], 
     sys[:Pd][11], 
     sys[:Pd][13], 
     sys[:Pd][19], 
     sys[:Pd][20], 
     sys[:Pg][6]]
q = [sys[:Qd][2],
     sys[:Qd][3], 
     sys[:Qd][4], 
     sys[:Qd][5], 
     sys[:Qd][6], 
     sys[:Qd][11], 
     sys[:Qd][13], 
     sys[:Qd][19], 
     sys[:Qd][20], 
     sys[:Qg][6]]
unc = initUncertainty_Nu(p, q)

## Dict of simulation results: each row of a parameter describes a bus
pfRes = Dict(:pg => Array{Float64}(undef, sys[:Ng], 0),
    :qg => Array{Float64}(undef, sys[:Ng], 0),
    :e => Array{Float64}(undef, sys[:Nbus], 0),
    :f => Array{Float64}(undef, sys[:Nbus], 0)
)

## Initialize solver
solver = JuMP.optimizer_with_attributes(Ipopt.Optimizer, "print_level" => 2)

## Execute the model for all samples
println("Running $numSamples deterministic PF calculations (model evalutations)...")
@time begin
    for x in eachrow(unc[:samples_bus]) # each row is a sample set
        network_data["load"]["2"]["pd"] = x[1]      # bus 3 / load 2
        network_data["load"]["2"]["qd"] = x[nUnc+1] # second half of matrix are q values
        network_data["load"]["3"]["pd"] = x[2]      
        network_data["load"]["3"]["qd"] = x[nUnc+2] 
        network_data["load"]["4"]["pd"] = x[3]      
        network_data["load"]["4"]["qd"] = x[nUnc+3] 
        network_data["load"]["5"]["pd"] = x[4]      # bus 8 / load 5
        network_data["load"]["5"]["qd"] = x[nUnc+4] 
        network_data["load"]["6"]["pd"] = x[5]      
        network_data["load"]["6"]["qd"] = x[nUnc+5] 
        network_data["load"]["11"]["pd"] = x[6]      
        network_data["load"]["11"]["qd"] = x[nUnc+6] 
        network_data["load"]["13"]["pd"] = x[7]      
        network_data["load"]["13"]["qd"] = x[nUnc+7] 
        network_data["load"]["19"]["pd"] = x[8]      
        network_data["load"]["19"]["qd"] = x[nUnc+8] 
        network_data["load"]["20"]["pd"] = x[9]      
        network_data["load"]["20"]["qd"] = x[nUnc+9] 
        network_data["gen"]["6"]["pg"]  = x[10]      # bus 13 / gen 6, no q values vor generators

        res = runPfModel(network_data, solver) # pass modified network data

        pfRes[:pg] = hcat(pfRes[:pg], res[:pg])
        pfRes[:qg] = hcat(pfRes[:qg], res[:qg])
        pfRes[:e] = hcat(pfRes[:e], res[:e])
        pfRes[:f] = hcat(pfRes[:f], res[:f])
    end
    print("Finished. Time:")
end

# Perform the regression for PCE coefficients on pd, qd, e and f
println("\nCompute non-intrusive PCE coefficients...\n")
pce, mse = computeCoefficientsSparse(unc[:samples_unc], pfRes, unc; K = K)

# Get additional PCE of currents, branch flows and demands
pf_state = getGridStateNonintrusive(pce, sys, unc)
println("PCE coefficients:")
display(pf_state)

# Sample for parameter values, using their PCE representations
pf_samples = generateSamples(unc[:ξ], pf_state, sys, unc)
println("\nPCE model evaluations for $(size(unc[:ξ])[1]) samples ξ:")
display(pf_samples)
println()


### Store data for evaluation ###

# PCE coefficients
f_coeff = "coefficients/SPF_10u_sparse.jld"
save(f_coeff, "pf_state", pf_state)
println("PCE coefficients data saved to $f_coeff.\n")

# Compute and store moments from PCE coefficients
moments = computeMoments(pf_state, unc)
f_moms = "coefficients/SPF_10u_sparse_moments.jld"
save(f_moms, "moments", moments)
println("PCE moments data saved to $f_moms.\n")



### POST PROCESSING ###
if postProcessing
    mycolor = "red"
    plotHistogram_6in9(pf_samples[:pg], "pg", "./plots/10u_sparse"; fignum=1 + 10, color=mycolor)
    plotHistogram_6in9(pf_samples[:qg], "qg", "./plots/10u_sparse"; fignum=2 + 10, color=mycolor)

    plotHistogram_9in9(pf_samples[:e][1:9, :], "e1", "./plots/10u_sparse"; fignum=3 + 10, color=mycolor)
    plotHistogram_9in9(pf_samples[:e][10:18, :], "e2", "./plots/10u_sparse"; fignum=4 + 10, color=mycolor)
    plotHistogram_9in9(pf_samples[:e][19:27, :], "e3", "./plots/10u_sparse"; fignum=5 + 10, color=mycolor)
    plotHistogram_9in9(pf_samples[:e][28:30, :], "e4", "./plots/10u_sparse"; fignum=6 + 10, color=mycolor)

    plotHistogram_9in9(pf_samples[:f][1:9, :], "f1", "./plots/10u_sparse"; fignum=7 + 10, color=mycolor)
    plotHistogram_9in9(pf_samples[:f][10:18, :], "f2", "./plots/10u_sparse"; fignum=8 + 10, color=mycolor)
    plotHistogram_9in9(pf_samples[:f][19:27, :], "f3", "./plots/10u_sparse"; fignum=9 + 10, color=mycolor)
    plotHistogram_9in9(pf_samples[:f][28:30, :], "f4", "./plots/10u_sparse"; fignum=10 + 10, color=mycolor)
    # Plot P & Q of uncertainties TODO
    plotHistogram_2unc(pf_samples[:pd], pf_samples[:qd], ["pd_8", "qd_8", "pg_13", "qg_13"], "./plots/2u_sparse"; fignum=0 + 10, color=mycolor)
end
