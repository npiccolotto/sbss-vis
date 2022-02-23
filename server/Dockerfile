
# Start with geospatial R image
FROM rocker/geospatial
LABEL maintainer="Nikolaus Piccolotto <nikolaus.piccolotto@tuwien.ac.at>"

# Add own dependencies - most should be there already
RUN R -e "install.packages('units')"
RUN R -e "install.packages('sf')"
RUN R -e "install.packages('gstat')"
RUN R -e "install.packages('sp')"
RUN R -e "install.packages('raster')"
RUN R -e "install.packages('GSIF')"
RUN R -e "install.packages('SDraw')"
RUN R -e "install.packages('rgdal')"
RUN R -e "install.packages('spdep')"
RUN R -e "install.packages('compositions')"
RUN R -e "install.packages('tidyverse')"
RUN R -e "install.packages('jsonlite')"
RUN R -e "install.packages('tictoc')"
RUN R -e "install.packages('SpatialBSS')"
RUN R -e "install.packages('devtools')"
RUN R -e "install.packages('statnet.common')"
RUN R -e "install.packages('reshape2')"
RUN R -e "install.packages('tidygraph')"
RUN R -e "install.packages('digest')"
RUN R -e "install.packages('hash')"

# Copied from trestletech/plumber Dockerfile

RUN apt-get update -qq && apt-get install -y \
  git-core \
  libssl-dev \
  libcurl4-gnutls-dev

RUN install2.r plumber

EXPOSE 8000
ENTRYPOINT ["R", "-e", "pr <- plumber::plumb(commandArgs()[6]); pr$run(host='0.0.0.0', port=8000)"]

CMD ["/app/api.R"]
