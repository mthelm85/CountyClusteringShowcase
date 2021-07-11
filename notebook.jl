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
	using Pkg
	Pkg.add(["CSV","Clustering","DataFrames","DataFramesMeta","Distances","PlutoUI","StatsBase","URIParser","VegaLite"])
	using CSV
	using Clustering
	using DataFrames
	using DataFramesMeta
	using Distances
	using PlutoUI
	using StatsBase
	using URIParser
	using VegaLite
	
	const saf_path = "https://raw.githubusercontent.com/mthelm85/CountyClusteringShowcase/main/states_abbrevs_fips.csv"
	
	const data_path = "https://raw.githubusercontent.com/mthelm85/CountyClusteringShowcase/main/allhlcn19.csv"
end;

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
const states_abbrevs_fips = @linq DataFrame(CSV.File(download(saf_path))) |>
	transform(fips = @. lpad(string(:fips), 2, "0"))

# ╔═╡ 0d329b95-7829-46ec-ab75-50e044f4c938
md"""
### Utility Functions

Now we need to write some utility functions that are going to do the dirty work for us. Let's first write a function that takes the two-letter state abbreviation and returns a `DataFrame` that includes the relevant state/industry information.
"""

# ╔═╡ 6e2e3db5-52d0-4dd4-b769-a1b28db6f369
function industry_df(state::String)
  @linq DataFrame(CSV.File(download(data_path), normalizenames=true)) |>
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
