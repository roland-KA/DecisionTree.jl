module DecisionTree

import Base: length, show, convert, promote_rule, zero
using DelimitedFiles
using LinearAlgebra
using Random
using Statistics
import AbstractTrees

export Leaf, Node, Root, Ensemble, print_tree, depth, build_stump, build_tree,
       prune_tree, apply_tree, apply_tree_proba, nfoldCV_tree, build_forest,
       apply_forest, apply_forest_proba, nfoldCV_forest, build_adaboost_stumps,
       apply_adaboost_stumps, apply_adaboost_stumps_proba, nfoldCV_stumps,
       load_data, impurity_importance, split_importance, permutation_importance

# ScikitLearn API
export DecisionTreeClassifier, DecisionTreeRegressor, RandomForestClassifier,
       RandomForestRegressor, AdaBoostStumpClassifier,
       # Should we export these functions? They have a conflict with
       # DataFrames/RDataset over fit!, and users can always
       # `using ScikitLearnBase`.
       predict, predict_proba, fit!, get_classes

export InfoNode, InfoLeaf, wrap

###########################
########## Types ##########

struct Leaf{T}
    majority :: T
    values   :: Vector{T}
end

struct Node{S, T}
    featid  :: Int
    featval :: S
    left    :: Union{Leaf{T}, Node{S, T}}
    right   :: Union{Leaf{T}, Node{S, T}}
end

const LeafOrNode{S, T} = Union{Leaf{T}, Node{S, T}}

struct Root{S, T}
    node    :: LeafOrNode{S, T}
    n_feat  :: Int
    featim  :: Vector{Float64}   # impurity importance
end

struct Ensemble{S, T}
    trees   :: Vector{LeafOrNode{S, T}}
    n_feat  :: Int
    featim  :: Vector{Float64}
end


is_leaf(l::Leaf) = true
is_leaf(n::Node) = false

zero(::Type{String}) = ""
convert(::Type{Node{S, T}}, lf::Leaf{T}) where {S, T} = Node(0, zero(S), lf, Leaf(zero(T), [zero(T)]))
convert(::Type{Root{S, T}}, node::LeafOrNode{S, T}) where {S, T} = Root{S, T}(node, 0, Float64[])
convert(::Type{LeafOrNode{S, T}}, tree::Root{S, T}) where {S, T} = tree.node
promote_rule(::Type{Node{S, T}}, ::Type{Leaf{T}}) where {S, T} = Node{S, T}
promote_rule(::Type{Leaf{T}}, ::Type{Node{S, T}}) where {S, T} = Node{S, T}
promote_rule(::Type{Root{S, T}}, ::Type{Leaf{T}}) where {S, T} = Root{S, T}
promote_rule(::Type{Leaf{T}}, ::Type{Root{S, T}}) where {S, T} = Root{S, T}
promote_rule(::Type{Root{S, T}}, ::Type{Node{S, T}}) where {S, T} = Root{S, T}
promote_rule(::Type{Node{S, T}}, ::Type{Root{S, T}}) where {S, T} = Root{S, T}

# make a Random Number Generator object
mk_rng(rng::Random.AbstractRNG) = rng
mk_rng(seed::T) where T <: Integer = Random.MersenneTwister(seed)

##############################
########## Includes ##########

include("measures.jl")
include("load_data.jl")
include("util.jl")
include("classification/main.jl")
include("regression/main.jl")
include("scikitlearnAPI.jl")
include("abstract_trees.jl")


#############################
########## Methods ##########

length(leaf::Leaf) = 1
length(tree::Node) = length(tree.left) + length(tree.right)
length(tree::Root) = length(tree.node)
length(ensemble::Ensemble) = length(ensemble.trees)

depth(leaf::Leaf) = 0
depth(tree::Node) = 1 + max(depth(tree.left), depth(tree.right))
depth(tree::Root) = depth(tree.node)

function print_tree(io::IO, leaf::Leaf, depth=-1, indent=0; feature_names=nothing)
    n_matches = count(leaf.values .== leaf.majority)
    ratio = string(n_matches, "/", length(leaf.values))
    println(io, "$(leaf.majority) : $(ratio)")
end
function print_tree(leaf::Leaf, depth=-1, indent=0; feature_names=nothing)
    return print_tree(stdout, leaf, depth, indent; feature_names=feature_names)
end


function print_tree(io::IO, tree::Root, depth=-1, indent=0; sigdigits=2, feature_names=nothing)
    return print_tree(io, tree.node, depth, indent; sigdigits=sigdigits, feature_names=feature_names)
end
function print_tree(tree::Root, depth=-1, indent=0; sigdigits=2, feature_names=nothing)
    return print_tree(stdout, tree, depth, indent; sigdigits=sigdigits, feature_names=feature_names)
end

"""
    print_tree([io::IO,] tree::Node, depth=-1, indent=0; sigdigits=4, feature_names=nothing)

Print a textual visualization of the specified `tree`. For example, if
for some input pattern the value of "Feature 3" is "-30" and the value
of "Feature 2" is "100", then, according to the sample output below,
the majority class prediction is 7. Moreover, one can see that of the
10555 training samples that terminate at the same leaf as this input
data, 2493 of these predict the majority class, leading to a
probabilistic prediction for class 7 of `2493/10555`. Ratios for
non-majority classes are not shown.

# Example output:
```
Feature 3 < -28.15 ?
├─ Feature 2 < -161.0 ?
   ├─ 5 : 842/3650
   └─ 7 : 2493/10555
└─ Feature 7 < 108.1 ?
   ├─ 2 : 2434/15287
   └─ 8 : 1227/3508
```

To facilitate visualisation of trees using third party packages, a `DecisionTree.Leaf` object,
`DecisionTree.Node` object or  `DecisionTree.Root` object can be wrapped to obtain a tree structure implementing the 
AbstractTrees.jl interface. See  [`wrap`](@ref)` for details. 
"""
function print_tree(io::IO, tree::Node, depth=-1, indent=0; sigdigits=2, feature_names=nothing)
    if depth == indent
        println(io)
        return
    end
    featval = round(tree.featval; sigdigits=sigdigits)
    if feature_names === nothing
        println(io, "Feature $(tree.featid) < $featval ?")
    else
        println(io, "Feature $(tree.featid): \"$(feature_names[tree.featid])\" < $featval ?")
    end
    print(io, "    " ^ indent * "├─ ")
    print_tree(io, tree.left, depth, indent + 1; feature_names=feature_names)
    print(io, "    " ^ indent * "└─ ")
    print_tree(io, tree.right, depth, indent + 1; feature_names=feature_names)
end
function print_tree(tree::Node, depth=-1, indent=0; sigdigits=2, feature_names=nothing)
    return print_tree(stdout, tree, depth, indent; sigdigits=sigdigits, feature_names=feature_names)
end

function show(io::IO, leaf::Leaf)
    println(io, "Decision Leaf")
    println(io, "Majority: $(leaf.majority)")
    print(io,   "Samples:  $(length(leaf.values))")
end

function show(io::IO, tree::Node)
    println(io, "Decision Tree")
    println(io, "Leaves: $(length(tree))")
    print(io,   "Depth:  $(depth(tree))")
end

function show(io::IO, tree::Root)
    println(io, "Decision Tree")
    println(io, "Leaves: $(length(tree))")
    print(io,   "Depth:  $(depth(tree))")
end

function show(io::IO, ensemble::Ensemble)
    println(io, "Ensemble of Decision Trees")
    println(io, "Trees:      $(length(ensemble))")
    println(io, "Avg Leaves: $(mean([length(tree) for tree in ensemble.trees]))")
    print(io,   "Avg Depth:  $(mean([depth(tree) for tree in ensemble.trees]))")
end

end # module
