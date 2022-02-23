# Visual Parameter Selection for Spatial Blind Source Separation

This repository contains code for the prototype _SBSSvis_, a visual analytics app to support parameter selection for Spatial Blind Source Separation [1].

## Usage

Please refer to the paper:

N. Piccolotto, M. Bögl, C. Muehlmann, K. Nordhausen, P. Filzmoser, and S. Miksch: "Visual Parameter Selection for Spatial Blind Source Separation". [https://arxiv.org/abs/2112.08888](https://arxiv.org/abs/2112.08888)

## Installation and running

Prerequisites: Node.js (>= v12), Docker (>= 19.03.13).

1. Clone this repository
2. Install frontend dependencies: `npm install`
3. Build the backend: `docker build server --tag sbss`
4. Run the backend with docker: `docker run -e SBSS_DATASET=gemas -d -p 8008:8000 -v $PWD/server/app:/app tsbss` - after initial preprocessing time (this may very well take several minutes depending on the dataset size) the backend runs on port `8008` on your host, check with `docker logs` if it's working
5. Run the frontend: `npx vue-cli-service serve` - the frontend then runs on port `8080` on your host
6. Go to `http://localhost:8080/#/new`, it shows the prototype with the GEMAS dataset.

See next section how to change the dataset.

## Changing the dataset and other options

Data is loaded from the subfolder `server/app/data`. To use a custom dataset, place a CSV file in that folder. The first two columns must be WGS84 coordinates, i.e., longitude and latitude, and named like that. The rest of the colums should be your variables. Then, when starting the backend, point SBSSvis to your dataset with the `SBSS_DATASET` environment variable. E.g., if your data is in the file `server/app/data/customdata.csv`, use  `-e SBSS_DATASET=customdata` in the docker command in step 4 of the previous section.

By default, as we developed SBSSvis with geochemical data, it assumes that data is compositional and automatically performs an ILR transformation. If you do not have compositional data, use `-e SBSS_IS_COMPOSITE=false`.

Other possible options include the number of regions to precompute for the regionalization suggestions (`-e SBSS_BLOCK_MAX_LEVEL=8`) and the granularity level for kernels (`SBSS_KERNEL_MAX_LEVEL=4`). Increase these as necessary.

Finally, SBSSvis supports overlaying custom features, such as polygons, points, lines and such. Provide them by placing a [GeoJSON](https://geojson.org/) file in `server/app/features`. You can control the appearance of features by setting `properties` of the feature accordingly. Currently `fill`, `fill-opacity`, `stroke`, `stroke-opacity` and `stroke-width` are supported (check `server/app/features/soiltypes.geojson` as an example).


## References

* [1] C. Muehlmann, F. Bachoc, K. Nordhausen: "Blind source separation for non-stationary random fields”, Spatial Statistics, 47, Article 100574, 2022, doi: https://doi.org/10.1016/j.spasta.2021.100574, axiv: [https://arxiv.org/abs/2107.01916](https://arxiv.org/abs/2107.01916)
