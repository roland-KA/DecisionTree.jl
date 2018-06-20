using DecisionTree
using ScikitLearnBase

if VERSION < v"0.7.0-DEV.2005"
    using Base.Test
else
    using Test
end

function run_tests(list)
    for test in list
        println("TEST: $test \n")
        include(test)
        println("=" ^ 50)
    end
end

classification = ["classification/random.jl",
                  "classification/heterogeneous.jl",
                  "classification/digits.jl",
                  "classification/scikitlearn.jl"]

regression =     ["regression/random.jl",
                  "regression/digits.jl",
                  "regression/scikitlearn.jl"]

miscellaneous =  ["miscellaneous/promote.jl",
                  "miscellaneous/parallel.jl"]

for list in [classification, regression, miscellaneous]
    run_tests(list)
end
