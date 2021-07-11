### A Pluto.jl notebook ###
# v0.15.1

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : missing
        el
    end
end

# ╔═╡ f7d30710-e252-11eb-24a3-dde35f12c8aa
begin
	using CSV
	using Clustering
	using DataFrames
	using DataFramesMeta
	using Distances
	using PlutoUI
	using StatsBase
	using URIParser
	using VegaLite
end

# ╔═╡ 9fa11575-b562-4a70-ac46-d0a965893ef5
md"""
# Clustering Counties Within a State, Based on Industry Characteristics

*Matt Helm*

The need to cluster geographic units (counties in this case) arises in many situations. Businesses often need to determine similarities between geographies for marketing purposes. Governments may need to group certain geographies together in order to determine how best to provide an essential service. In this article, we'll look at a simple way to group counties within a state based on a single data source: the Bureau of Labor Statistics' Quarterly Census of Employment & Wages (QCEW). Some of the industry characteristics included in the QCEW are:

* Average annual number of establishments
* Average annual employment
* Average weekly wage

We'll use these characteristics across all industries to group counties using several different clustering algorithms.

*Note: QCEW files can be downloaded from [this url](https://www.bls.gov/cew/downloadable-data-files.htm).*
"""

# ╔═╡ b7ab763b-11d2-4684-be75-3e097c112198
md"""
## Setup

### Load Dependencies
"""

# ╔═╡ 6673bc8f-c319-4ef6-b335-ed877d29c3a6
md"""
### Files

In addition to the Julia package dependencies above, we also have a QCEW file that we'll need for all of this to work, as well as a file that contains state names, abbreviations, and FIPS codes:

* allhlcn19.csv
* states\_abbrevs\_fips.csv
"""

# ╔═╡ 35a893f0-d875-4107-bc2b-3c65b309269b
md"""
### 

In this article, I'm going to show how to set everything up so that we can do this analysis for all 50 U.S. states. In order to make this work, we're going to need a crosswalk that maps state names to their abbreviations and FIPS codes. Let's load the file above into a `DataFrame`.
"""

# ╔═╡ c3b1cb70-2b55-48fa-85d3-82dd6c89f3ac
const states_abbrevs_fips = @linq DataFrame(CSV.File("states_abbrevs_fips.csv")) |>
	transform(fips = @. lpad(string(:fips), 2, "0"))

# ╔═╡ 0d329b95-7829-46ec-ab75-50e044f4c938
md"""
### Utility Functions

Now we need to write some utility functions that are going to do the dirty work for us. Let's first write a function that takes the two-letter state abbreviation and returns a `DataFrame` that includes the relevant state/industry information.
"""

# ╔═╡ 6e2e3db5-52d0-4dd4-b769-a1b28db6f369
function industry_df(state::String)
  @linq DataFrame(CSV.File("allhlcn19.csv", normalizenames=true)) |>
    where(
		(:Area_Type .== "County") .&
		(:Industry .== "10 Total, all industries") .&
		(:Ownership .== "Private") .&
		(:St .== string(states_abbrevs_fips[findfirst(
			x -> x == state, states_abbrevs_fips.abbrev), 3]))) |>
 	transform(Cnty = @. lpad(string(:Cnty), 3, "0"))
end;

# ╔═╡ cb774300-2d9a-4b9b-b600-c1aa95a38dde
md"""
Next, let's write another function that will take the `DataFrame` returned by the function above, extract the data elements that we are interested in, normalize them, and then return everything as a `Matrix`. Each column of the matrix will represent a feature vector including the four industry features identified in the bullets above for a given county in the chosen state.
"""

# ╔═╡ 01b97a26-9682-4c79-b086-7ef5dcd47ced
function normalize_matrix(df::DataFrame)
   matrix = Matrix(hcat(
        df.Annual_Average_Establishment_Count,
        df.Annual_Average_Employment,
        df.Annual_Average_Weekly_Wage
    )')
    return StatsBase.transform(
		fit(ZScoreTransform, matrix, dims=2), convert.(Float64, matrix)
	) 
end;

# ╔═╡ 9f948356-cddf-4c2d-90a6-8fdd644f0b80
md"""
The next step is to write a function that takes our normalized matrix and returns a pairwise distance matrix for each county in the state.
"""

# ╔═╡ 4a58af8e-2af9-4a40-8f87-648258f282e4
function distance_matrix(state::String, distance_metric::PreMetric)
    df = industry_df(state)
    matrix = normalize_matrix(df)
    dm = (df.Area, Distances.pairwise(distance_metric, matrix, dims=2))
    distance_df = DataFrame(dm[2])
    rename!(distance_df, Symbol.(dm[1]))
    insertcols!(distance_df, 1, :County => dm[1])
    return distance_df
end;

# ╔═╡ 8488fa3b-e62b-49de-8624-8ee99dd46eb7
md"""
Lastly, we need a function that will take care of the boilerplate code needed for plotting our results as it's quite long.
"""

# ╔═╡ 8f93142a-4da6-4877-a87e-48cf0666abab
function generate_plot(link, object_name, groups)
   return :(
        @vlplot(width=600, height=400) + 
        @vlplot(
            mark={ 
                :geoshape,
                stroke=:black
            },
            data={
                url=URI($link),
                format={
                    type=:topojson,
                    feature=$object_name
                }
            },
            transform=[
                {
                    lookup="properties.GEOID",
                    from={
                        data=$groups,
                        key=:fips,
                        fields=["group"]
                    }
                }
            ],
            color={
                "group:n",
                legend={title="Group"}
            },
            projection={
                typ=:naturalEarth1
            }
        ) +
        @vlplot(
            mark={
              :text,
              size=8
            },            
            data={
                url=URI($link),
                format={
                    type=:topojson,
                    feature=$object_name
                }
            },
          transform=[
            {
            calculate="geoCentroid(null, datum)",
            as="centroid"
            },
            {
            calculate="datum.centroid[0]",
            as="centroidx"
            },
            {
            calculate="datum.centroid[1]",
            as="centroidy"
            }
            ],
            text={field="properties.NAME", type=:nominal},
            longitude="centroidx:q",
            latitude="centroidy:q",
        )
    )
end;

# ╔═╡ 8f9bff07-758d-4d0a-957a-f1b12e5ab545
md"""
## Algorithms 

In this notebook, we'll explore two different clustering algorithms: [Fuzzy C Means](https://en.wikipedia.org/wiki/Fuzzy_clustering#Fuzzy_C-means_clustering) and [K-Medoids](https://en.wikipedia.org/wiki/K-medoids). Rather than getting into the specifics of each of these, interested readers should follow the links to learn more about how they work.

### Fuzzy C Means
"""

# ╔═╡ c391e7bb-6d1b-4dad-9600-44ef647990df
md"""
Fuzziness Factor:
$(@bind m Slider(1.1:0.1:10.0, show_value=true, default=2.0))

Number of Groups:
$(@bind C Slider(2:20, show_value=true, default=4))
"""

# ╔═╡ 2e6eab42-dcbb-4231-bb87-39eb2c87d647
begin
	function create_groups_fuzzy_cmeans(
			df::DataFrame,
			matrix::Matrix
	)
		weights = fuzzy_cmeans(matrix, C, m).weights
		df = DataFrame(
			fips = df.St .* df.Cnty,
			group = [findfirst(
					x -> x == maximum(weights[i,:]), weights[i,:]
			) for i = 1:size(weights,1)]
		)
		return df
	end;

	function show_state_groups_fuzzyc(state::String)
		link = "https://raw.githubusercontent.com/mthelm85/topojson/master/countries/us-states/$state-$(states_abbrevs_fips[states_abbrevs_fips.abbrev .== state, 3][1])-$(states_abbrevs_fips[states_abbrevs_fips.abbrev .== state, 1][1])-counties.json"
		object_name = replace("cb_2015_$(states_abbrevs_fips[states_abbrevs_fips.abbrev .== state, 1][1])_county_20m", "-" => "_")
		df = industry_df(state)
		matrix = normalize_matrix(df)
		groups = create_groups_fuzzy_cmeans(df, matrix)
		eval(generate_plot(link, object_name, groups))
	end
end

# ╔═╡ f33a8e08-a437-4f97-810a-89b31fa58963
show_state_groups_fuzzyc("WA")

# ╔═╡ 465fb1f2-786b-4b50-9ea1-fdb5d4f7e698
md"""
### K-Medoids
"""

# ╔═╡ 7469f998-2211-4221-9f1f-383ed9ac3865
md"""
k:
$(@bind k Slider(2:12, show_value=true, default=4))
"""

# ╔═╡ 5a15b200-20ad-4204-9711-7515d1a641d9
begin
	function create_groups_kmedoids(df::DataFrame, matrix::Matrix)
		assignments = kmedoids(
			Distances.pairwise(Euclidean(), matrix, dims=2), k
			).assignments
		df = DataFrame(
			fips = df.St .* df.Cnty,
			group = assignments
		)
		return df
	end
	
	function show_state_groups_kmeds(state::String, k::Int=4)
		link = "https://raw.githubusercontent.com/mthelm85/topojson/master/countries/us-states/$state-$(states_abbrevs_fips[states_abbrevs_fips.abbrev .== state, 3][1])-$(states_abbrevs_fips[states_abbrevs_fips.abbrev .== state, 1][1])-counties.json"
		object_name = replace("cb_2015_$(states_abbrevs_fips[states_abbrevs_fips.abbrev .== state, :state][1])_county_20m", "-" => "_")
		df = industry_df(state)
		matrix = normalize_matrix(df)
		groups = create_groups_kmedoids(df, matrix)
		eval(generate_plot(link, object_name, groups))
	end
end

# ╔═╡ e8440246-2b08-44c8-83e4-7d4553846912
show_state_groups_kmeds("FL")

# ╔═╡ 00000000-0000-0000-0000-000000000001
PLUTO_PROJECT_TOML_CONTENTS = """
[deps]
CSV = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
Clustering = "aaaa29a8-35af-508c-8bc3-b662a17a0fe5"
DataFrames = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
DataFramesMeta = "1313f7d8-7da2-5740-9ea0-a2ca25f37964"
Distances = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
PlutoUI = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
StatsBase = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
URIParser = "30578b45-9adc-5946-b283-645ec420af67"
VegaLite = "112f6efa-9a02-5b7d-90c0-432ed331239a"

[compat]
CSV = "~0.8.5"
Clustering = "~0.14.2"
DataFrames = "~1.2.0"
DataFramesMeta = "~0.8.0"
Distances = "~0.10.3"
PlutoUI = "~0.7.9"
StatsBase = "~0.33.8"
URIParser = "~0.4.1"
VegaLite = "~2.6.0"
"""

# ╔═╡ 00000000-0000-0000-0000-000000000002
PLUTO_MANIFEST_TOML_CONTENTS = """
# This file is machine-generated - editing it directly is not advised

[[ArgTools]]
uuid = "0dad84c5-d112-42e6-8d28-ef12dabb789f"

[[Artifacts]]
uuid = "56f22d72-fd6d-98f1-02f0-08ddc0907c33"

[[Base64]]
uuid = "2a0f44e3-6c83-55bd-87e4-b1978d98bd5f"

[[CSV]]
deps = ["Dates", "Mmap", "Parsers", "PooledArrays", "SentinelArrays", "Tables", "Unicode"]
git-tree-sha1 = "b83aa3f513be680454437a0eee21001607e5d983"
uuid = "336ed68f-0bac-5ca0-87d4-7b16caf5d00b"
version = "0.8.5"

[[Chain]]
git-tree-sha1 = "c72673739e02d65990e5e068264df5afaa0b3273"
uuid = "8be319e6-bccf-4806-a6f7-6fae938471bc"
version = "0.4.7"

[[Clustering]]
deps = ["Distances", "LinearAlgebra", "NearestNeighbors", "Printf", "SparseArrays", "Statistics", "StatsBase"]
git-tree-sha1 = "75479b7df4167267d75294d14b58244695beb2ac"
uuid = "aaaa29a8-35af-508c-8bc3-b662a17a0fe5"
version = "0.14.2"

[[Compat]]
deps = ["Base64", "Dates", "DelimitedFiles", "Distributed", "InteractiveUtils", "LibGit2", "Libdl", "LinearAlgebra", "Markdown", "Mmap", "Pkg", "Printf", "REPL", "Random", "SHA", "Serialization", "SharedArrays", "Sockets", "SparseArrays", "Statistics", "Test", "UUIDs", "Unicode"]
git-tree-sha1 = "dc7dedc2c2aa9faf59a55c622760a25cbefbe941"
uuid = "34da2185-b29b-5c13-b0c7-acf172513d20"
version = "3.31.0"

[[ConstructionBase]]
deps = ["LinearAlgebra"]
git-tree-sha1 = "f74e9d5388b8620b4cee35d4c5a618dd4dc547f4"
uuid = "187b0558-2788-49d3-abe0-74a17ed4e7c9"
version = "1.3.0"

[[Crayons]]
git-tree-sha1 = "3f71217b538d7aaee0b69ab47d9b7724ca8afa0d"
uuid = "a8cc5b0e-0ffa-5ad4-8c14-923d3ee1735f"
version = "4.0.4"

[[DataAPI]]
git-tree-sha1 = "ee400abb2298bd13bfc3df1c412ed228061a2385"
uuid = "9a962f9c-6df0-11e9-0e5d-c546b8b5ee8a"
version = "1.7.0"

[[DataFrames]]
deps = ["Compat", "DataAPI", "Future", "InvertedIndices", "IteratorInterfaceExtensions", "LinearAlgebra", "Markdown", "Missings", "PooledArrays", "PrettyTables", "Printf", "REPL", "Reexport", "SortingAlgorithms", "Statistics", "TableTraits", "Tables", "Unicode"]
git-tree-sha1 = "1dadfca11c0e08e03ab15b63aaeda55266754bad"
uuid = "a93c6f00-e57d-5684-b7b6-d8193f3e46c0"
version = "1.2.0"

[[DataFramesMeta]]
deps = ["Chain", "DataFrames", "MacroTools", "Reexport"]
git-tree-sha1 = "55be907a531471de062f321147006c04b8c1e75f"
uuid = "1313f7d8-7da2-5740-9ea0-a2ca25f37964"
version = "0.8.0"

[[DataStructures]]
deps = ["Compat", "InteractiveUtils", "OrderedCollections"]
git-tree-sha1 = "4437b64df1e0adccc3e5d1adbc3ac741095e4677"
uuid = "864edb3b-99cc-5e75-8d2d-829cb0a9cfe8"
version = "0.18.9"

[[DataValueInterfaces]]
git-tree-sha1 = "bfc1187b79289637fa0ef6d4436ebdfe6905cbd6"
uuid = "e2d170a0-9d28-54be-80f0-106bbe20a464"
version = "1.0.0"

[[DataValues]]
deps = ["DataValueInterfaces", "Dates"]
git-tree-sha1 = "d88a19299eba280a6d062e135a43f00323ae70bf"
uuid = "e7dc6d0d-1eca-5fa6-8ad6-5aecde8b7ea5"
version = "0.4.13"

[[Dates]]
deps = ["Printf"]
uuid = "ade2ca70-3891-5945-98fb-dc099432e06a"

[[DelimitedFiles]]
deps = ["Mmap"]
uuid = "8bb1440f-4735-579b-a4ab-409b98df4dab"

[[Distances]]
deps = ["LinearAlgebra", "Statistics", "StatsAPI"]
git-tree-sha1 = "abe4ad222b26af3337262b8afb28fab8d215e9f8"
uuid = "b4f34e82-e78d-54a5-968a-f98e89d6e8f7"
version = "0.10.3"

[[Distributed]]
deps = ["Random", "Serialization", "Sockets"]
uuid = "8ba89e20-285c-5b6f-9357-94700520ee1b"

[[Downloads]]
deps = ["ArgTools", "LibCURL", "NetworkOptions"]
uuid = "f43a241f-c20a-4ad4-852c-f6b1247861c6"

[[FileIO]]
deps = ["Pkg", "Requires", "UUIDs"]
git-tree-sha1 = "256d8e6188f3f1ebfa1a5d17e072a0efafa8c5bf"
uuid = "5789e2e9-d7fb-5bc7-8068-2c6fae9b9549"
version = "1.10.1"

[[FilePaths]]
deps = ["FilePathsBase", "MacroTools", "Reexport", "Requires"]
git-tree-sha1 = "919d9412dbf53a2e6fe74af62a73ceed0bce0629"
uuid = "8fc22ac5-c921-52a6-82fd-178b2807b824"
version = "0.8.3"

[[FilePathsBase]]
deps = ["Dates", "Mmap", "Printf", "Test", "UUIDs"]
git-tree-sha1 = "0f5e8d0cb91a6386ba47bd1527b240bd5725fbae"
uuid = "48062228-2e41-5def-b9a4-89aafe57970f"
version = "0.9.10"

[[Formatting]]
deps = ["Printf"]
git-tree-sha1 = "8339d61043228fdd3eb658d86c926cb282ae72a8"
uuid = "59287772-0a20-5a39-b81b-1366585eb4c0"
version = "0.4.2"

[[Future]]
deps = ["Random"]
uuid = "9fa8497b-333b-5362-9e8d-4d0656e87820"

[[HTTP]]
deps = ["Base64", "Dates", "IniFile", "MbedTLS", "Sockets"]
git-tree-sha1 = "c7ec02c4c6a039a98a15f955462cd7aea5df4508"
uuid = "cd3eb016-35fb-5094-929b-558a96fad6f3"
version = "0.8.19"

[[IniFile]]
deps = ["Test"]
git-tree-sha1 = "098e4d2c533924c921f9f9847274f2ad89e018b8"
uuid = "83e8ac13-25f8-5344-8a64-a9f2b223428f"
version = "0.5.0"

[[InteractiveUtils]]
deps = ["Markdown"]
uuid = "b77e0a4c-d291-57a0-90e8-8db25a27a240"

[[InvertedIndices]]
deps = ["Test"]
git-tree-sha1 = "15732c475062348b0165684ffe28e85ea8396afc"
uuid = "41ab1584-1d38-5bbf-9106-f11c6c58b48f"
version = "1.0.0"

[[IteratorInterfaceExtensions]]
git-tree-sha1 = "a3f24677c21f5bbe9d2a714f95dcd58337fb2856"
uuid = "82899510-4779-5014-852e-03e436cf321d"
version = "1.0.0"

[[JSON]]
deps = ["Dates", "Mmap", "Parsers", "Unicode"]
git-tree-sha1 = "81690084b6198a2e1da36fcfda16eeca9f9f24e4"
uuid = "682c06a0-de6a-54ab-a142-c8b1cf79cde6"
version = "0.21.1"

[[JSONSchema]]
deps = ["HTTP", "JSON", "ZipFile"]
git-tree-sha1 = "b84ab8139afde82c7c65ba2b792fe12e01dd7307"
uuid = "7d188eb4-7ad8-530c-ae41-71a32a6d4692"
version = "0.3.3"

[[LibCURL]]
deps = ["LibCURL_jll", "MozillaCACerts_jll"]
uuid = "b27032c2-a3e7-50c8-80cd-2d36dbcbfd21"

[[LibCURL_jll]]
deps = ["Artifacts", "LibSSH2_jll", "Libdl", "MbedTLS_jll", "Zlib_jll", "nghttp2_jll"]
uuid = "deac9b47-8bc7-5906-a0fe-35ac56dc84c0"

[[LibGit2]]
deps = ["Base64", "NetworkOptions", "Printf", "SHA"]
uuid = "76f85450-5226-5b5a-8eaa-529ad045b433"

[[LibSSH2_jll]]
deps = ["Artifacts", "Libdl", "MbedTLS_jll"]
uuid = "29816b5a-b9ab-546f-933c-edad1886dfa8"

[[Libdl]]
uuid = "8f399da3-3557-5675-b5ff-fb832c97cbdb"

[[LinearAlgebra]]
deps = ["Libdl"]
uuid = "37e2e46d-f89d-539d-b4ee-838fcccc9c8e"

[[Logging]]
uuid = "56ddb016-857b-54e1-b83d-db4d58db5568"

[[MacroTools]]
deps = ["Markdown", "Random"]
git-tree-sha1 = "6a8a2a625ab0dea913aba95c11370589e0239ff0"
uuid = "1914dd2f-81c6-5fcd-8719-6d5c9610ff09"
version = "0.5.6"

[[Markdown]]
deps = ["Base64"]
uuid = "d6f4376e-aef5-505a-96c1-9c027394607a"

[[MbedTLS]]
deps = ["Dates", "MbedTLS_jll", "Random", "Sockets"]
git-tree-sha1 = "1c38e51c3d08ef2278062ebceade0e46cefc96fe"
uuid = "739be429-bea8-5141-9913-cc70e7f3736d"
version = "1.0.3"

[[MbedTLS_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "c8ffd9c3-330d-5841-b78e-0817d7145fa1"

[[Missings]]
deps = ["DataAPI"]
git-tree-sha1 = "f8c673ccc215eb50fcadb285f522420e29e69e1c"
uuid = "e1d29d7a-bbdc-5cf2-9ac0-f12de2c33e28"
version = "0.4.5"

[[Mmap]]
uuid = "a63ad114-7e13-5084-954f-fe012c677804"

[[MozillaCACerts_jll]]
uuid = "14a3606d-f60d-562e-9121-12d972cd8159"

[[NearestNeighbors]]
deps = ["Distances", "StaticArrays"]
git-tree-sha1 = "16baacfdc8758bc374882566c9187e785e85c2f0"
uuid = "b8a86587-4115-5ab1-83bc-aa920d37bbce"
version = "0.4.9"

[[NetworkOptions]]
uuid = "ca575930-c2e3-43a9-ace4-1e988b2c1908"

[[NodeJS]]
deps = ["Pkg"]
git-tree-sha1 = "905224bbdd4b555c69bb964514cfa387616f0d3a"
uuid = "2bd173c7-0d6d-553b-b6af-13a54713934c"
version = "1.3.0"

[[OrderedCollections]]
git-tree-sha1 = "85f8e6578bf1f9ee0d11e7bb1b1456435479d47c"
uuid = "bac558e1-5e72-5ebc-8fee-abe8a469f55d"
version = "1.4.1"

[[Parsers]]
deps = ["Dates"]
git-tree-sha1 = "c8abc88faa3f7a3950832ac5d6e690881590d6dc"
uuid = "69de0a69-1ddd-5017-9359-2bf0b02dc9f0"
version = "1.1.0"

[[Pkg]]
deps = ["Artifacts", "Dates", "Downloads", "LibGit2", "Libdl", "Logging", "Markdown", "Printf", "REPL", "Random", "SHA", "Serialization", "TOML", "Tar", "UUIDs", "p7zip_jll"]
uuid = "44cfe95a-1eb2-52ea-b672-e2afdf69b78f"

[[PlutoUI]]
deps = ["Base64", "Dates", "InteractiveUtils", "JSON", "Logging", "Markdown", "Random", "Reexport", "Suppressor"]
git-tree-sha1 = "44e225d5837e2a2345e69a1d1e01ac2443ff9fcb"
uuid = "7f904dfe-b85e-4ff6-b463-dae2292396a8"
version = "0.7.9"

[[PooledArrays]]
deps = ["DataAPI", "Future"]
git-tree-sha1 = "cde4ce9d6f33219465b55162811d8de8139c0414"
uuid = "2dfb63ee-cc39-5dd5-95bd-886bf059d720"
version = "1.2.1"

[[PrettyTables]]
deps = ["Crayons", "Formatting", "Markdown", "Reexport", "Tables"]
git-tree-sha1 = "0d1245a357cc61c8cd61934c07447aa569ff22e6"
uuid = "08abe8d2-0d0c-5749-adfa-8a2ac140af0d"
version = "1.1.0"

[[Printf]]
deps = ["Unicode"]
uuid = "de0858da-6303-5e67-8744-51eddeeeb8d7"

[[REPL]]
deps = ["InteractiveUtils", "Markdown", "Sockets", "Unicode"]
uuid = "3fa0cd96-eef1-5676-8a61-b3b8758bbffb"

[[Random]]
deps = ["Serialization"]
uuid = "9a3f8284-a2c9-5f02-9a11-845980a1fd5c"

[[Reexport]]
git-tree-sha1 = "5f6c21241f0f655da3952fd60aa18477cf96c220"
uuid = "189a3867-3050-52da-a836-e630ba90ab69"
version = "1.1.0"

[[Requires]]
deps = ["UUIDs"]
git-tree-sha1 = "4036a3bd08ac7e968e27c203d45f5fff15020621"
uuid = "ae029012-a4dd-5104-9daa-d747884805df"
version = "1.1.3"

[[SHA]]
uuid = "ea8e919c-243c-51af-8825-aaa63cd721ce"

[[SentinelArrays]]
deps = ["Dates", "Random"]
git-tree-sha1 = "ffae887d0f0222a19c406a11c3831776d1383e3d"
uuid = "91c51154-3ec4-41a3-a24f-3f23e20d615c"
version = "1.3.3"

[[Serialization]]
uuid = "9e88b42a-f829-5b0c-bbe9-9e923198166b"

[[Setfield]]
deps = ["ConstructionBase", "Future", "MacroTools", "Requires"]
git-tree-sha1 = "d5640fc570fb1b6c54512f0bd3853866bd298b3e"
uuid = "efcf1570-3423-57d1-acb7-fd33fddbac46"
version = "0.7.0"

[[SharedArrays]]
deps = ["Distributed", "Mmap", "Random", "Serialization"]
uuid = "1a1011a3-84de-559e-8e89-a11a2f7dc383"

[[Sockets]]
uuid = "6462fe0b-24de-5631-8697-dd941f90decc"

[[SortingAlgorithms]]
deps = ["DataStructures"]
git-tree-sha1 = "b3363d7460f7d098ca0912c69b082f75625d7508"
uuid = "a2af1166-a08f-5f64-846c-94a0d3cef48c"
version = "1.0.1"

[[SparseArrays]]
deps = ["LinearAlgebra", "Random"]
uuid = "2f01184e-e22b-5df5-ae63-d93ebab69eaf"

[[StaticArrays]]
deps = ["LinearAlgebra", "Random", "Statistics"]
git-tree-sha1 = "a43a7b58a6e7dc933b2fa2e0ca653ccf8bb8fd0e"
uuid = "90137ffa-7385-5640-81b9-e52037218182"
version = "1.2.6"

[[Statistics]]
deps = ["LinearAlgebra", "SparseArrays"]
uuid = "10745b16-79ce-11e8-11f9-7d13ad32a3b2"

[[StatsAPI]]
git-tree-sha1 = "1958272568dc176a1d881acb797beb909c785510"
uuid = "82ae8749-77ed-4fe6-ae5f-f523153014b0"
version = "1.0.0"

[[StatsBase]]
deps = ["DataAPI", "DataStructures", "LinearAlgebra", "Missings", "Printf", "Random", "SortingAlgorithms", "SparseArrays", "Statistics", "StatsAPI"]
git-tree-sha1 = "2f6792d523d7448bbe2fec99eca9218f06cc746d"
uuid = "2913bbd2-ae8a-5f71-8c99-4fb6c76f3a91"
version = "0.33.8"

[[Suppressor]]
git-tree-sha1 = "a819d77f31f83e5792a76081eee1ea6342ab8787"
uuid = "fd094767-a336-5f1f-9728-57cf17d0bbfb"
version = "0.2.0"

[[TOML]]
deps = ["Dates"]
uuid = "fa267f1f-6049-4f14-aa54-33bafae1ed76"

[[TableTraits]]
deps = ["IteratorInterfaceExtensions"]
git-tree-sha1 = "c06b2f539df1c6efa794486abfb6ed2022561a39"
uuid = "3783bdb8-4a98-5b6b-af9a-565f29a5fe9c"
version = "1.0.1"

[[TableTraitsUtils]]
deps = ["DataValues", "IteratorInterfaceExtensions", "Missings", "TableTraits"]
git-tree-sha1 = "8fc12ae66deac83e44454e61b02c37b326493233"
uuid = "382cd787-c1b6-5bf2-a167-d5b971a19bda"
version = "1.0.1"

[[Tables]]
deps = ["DataAPI", "DataValueInterfaces", "IteratorInterfaceExtensions", "LinearAlgebra", "TableTraits", "Test"]
git-tree-sha1 = "8ed4a3ea724dac32670b062be3ef1c1de6773ae8"
uuid = "bd369af6-aec1-5ad0-b16a-f7cc5008161c"
version = "1.4.4"

[[Tar]]
deps = ["ArgTools", "SHA"]
uuid = "a4e569a6-e804-4fa4-b0f3-eef7a1d5b13e"

[[Test]]
deps = ["InteractiveUtils", "Logging", "Random", "Serialization"]
uuid = "8dfed614-e22c-5e08-85e1-65c5234f0b40"

[[URIParser]]
deps = ["Unicode"]
git-tree-sha1 = "53a9f49546b8d2dd2e688d216421d050c9a31d0d"
uuid = "30578b45-9adc-5946-b283-645ec420af67"
version = "0.4.1"

[[UUIDs]]
deps = ["Random", "SHA"]
uuid = "cf7118a7-6976-5b1a-9a39-7adc72f591a4"

[[Unicode]]
uuid = "4ec0a83e-493e-50e2-b9ac-8f72acf5a8f5"

[[Vega]]
deps = ["DataStructures", "DataValues", "Dates", "FileIO", "FilePaths", "IteratorInterfaceExtensions", "JSON", "JSONSchema", "MacroTools", "NodeJS", "Pkg", "REPL", "Random", "Setfield", "TableTraits", "TableTraitsUtils", "URIParser"]
git-tree-sha1 = "43f83d3119a868874d18da6bca0f4b5b6aae53f7"
uuid = "239c3e63-733f-47ad-beb7-a12fde22c578"
version = "2.3.0"

[[VegaLite]]
deps = ["Base64", "DataStructures", "DataValues", "Dates", "FileIO", "FilePaths", "IteratorInterfaceExtensions", "JSON", "MacroTools", "NodeJS", "Pkg", "REPL", "Random", "TableTraits", "TableTraitsUtils", "URIParser", "Vega"]
git-tree-sha1 = "3e23f28af36da21bfb4acef08b144f92ad205660"
uuid = "112f6efa-9a02-5b7d-90c0-432ed331239a"
version = "2.6.0"

[[ZipFile]]
deps = ["Libdl", "Printf", "Zlib_jll"]
git-tree-sha1 = "c3a5637e27e914a7a445b8d0ad063d701931e9f7"
uuid = "a5390f91-8eb1-5f08-bee0-b1d1ffed6cea"
version = "0.9.3"

[[Zlib_jll]]
deps = ["Libdl"]
uuid = "83775a58-1f1d-513f-b197-d71354ab007a"

[[nghttp2_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "8e850ede-7688-5339-a07c-302acd2aaf8d"

[[p7zip_jll]]
deps = ["Artifacts", "Libdl"]
uuid = "3f19e933-33d8-53b3-aaab-bd5110c3b7a0"
"""

# ╔═╡ Cell order:
# ╟─9fa11575-b562-4a70-ac46-d0a965893ef5
# ╟─b7ab763b-11d2-4684-be75-3e097c112198
# ╠═f7d30710-e252-11eb-24a3-dde35f12c8aa
# ╟─6673bc8f-c319-4ef6-b335-ed877d29c3a6
# ╟─35a893f0-d875-4107-bc2b-3c65b309269b
# ╠═c3b1cb70-2b55-48fa-85d3-82dd6c89f3ac
# ╟─0d329b95-7829-46ec-ab75-50e044f4c938
# ╠═6e2e3db5-52d0-4dd4-b769-a1b28db6f369
# ╟─cb774300-2d9a-4b9b-b600-c1aa95a38dde
# ╠═01b97a26-9682-4c79-b086-7ef5dcd47ced
# ╟─9f948356-cddf-4c2d-90a6-8fdd644f0b80
# ╠═4a58af8e-2af9-4a40-8f87-648258f282e4
# ╟─8488fa3b-e62b-49de-8624-8ee99dd46eb7
# ╠═8f93142a-4da6-4877-a87e-48cf0666abab
# ╟─8f9bff07-758d-4d0a-957a-f1b12e5ab545
# ╟─c391e7bb-6d1b-4dad-9600-44ef647990df
# ╠═2e6eab42-dcbb-4231-bb87-39eb2c87d647
# ╠═f33a8e08-a437-4f97-810a-89b31fa58963
# ╟─465fb1f2-786b-4b50-9ea1-fdb5d4f7e698
# ╟─7469f998-2211-4221-9f1f-383ed9ac3865
# ╠═5a15b200-20ad-4204-9711-7515d1a641d9
# ╠═e8440246-2b08-44c8-83e4-7d4553846912
# ╟─00000000-0000-0000-0000-000000000001
# ╟─00000000-0000-0000-0000-000000000002
