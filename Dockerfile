FROM ubuntu:22.04 AS compiler-common
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

ENV AUTOVACUUM=on
ENV UPDATES=disabled
ENV REPLICATION_URL=https://planet.openstreetmap.org/replication/hour/
ENV MAX_INTERVAL_SECONDS=3600
ENV PG_VERSION 15
ENV DOWNLOAD_PBF=

# Based on
# https://switch2osm.org/serving-tiles/manually-building-a-tile-server-18-04-lts/

# Set up environment
ENV TZ=UTC
ENV AUTOVACUUM=on
ENV UPDATES=disabled
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

RUN apt-get update \
&& apt-get install -y --no-install-recommends \
 ca-certificates gnupg lsb-release locales \
 wget curl \
 git-core unzip unrar \
&& locale-gen $LANG && update-locale LANG=$LANG \
&& sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' \
&& wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | apt-key add - \
&& apt-get update && apt-get -y upgrade

# Install dependencies
RUN apt-get update \
  && apt-get install -y wget gnupg2 lsb-core apt-transport-https ca-certificates curl \
  && echo 'INFO: downloading node' \
  && wget -O - https://deb.nodesource.com/setup_20.x | bash - \
  && apt-get update \
  && apt-get install -y nodejs


# RUN sh -c 'echo  "deb http://us.archive.ubuntu.com/ubuntu jammy main multiverse" > /etc/apt/sources.list'

RUN apt-get update && \
  apt-get install -y --no-install-recommends \
  apache2 \
  apache2-dev \
  fonts-dejavu-core \
  fonts-hanazono \
  fonts-noto-cjk \
  fonts-noto-hinted \
  fonts-noto-unhinted \
  libapache2-mod-tile \
  osm2pgsql \
  postgresql-$PG_VERSION \
  postgresql-$PG_VERSION-postgis-3 \
  postgresql-$PG_VERSION-postgis-3-scripts \
  postgresql-contrib-$PG_VERSION \
  postgresql-server-dev-$PG_VERSION \
  postgis \
  renderd \
  sudo \
  unifont \
&& apt-get clean autoclean \
&& apt-get autoremove --yes \
&& rm -rf /var/lib/{apt,dpkg,cache,log}/

RUN npm config set update-notifier false

# Set up renderer user
RUN adduser --disabled-password --gecos "" renderer
RUN echo "renderer:renderer" | sudo chpasswd

# RUN apt install libapache2-mod-tile renderd

# Configure Noto Emoji font
RUN mkdir -p /home/renderer/src \
&& cd /home/renderer/src \
&& git clone https://github.com/googlei18n/noto-emoji.git \
&& git -C noto-emoji checkout e0aa9412575fc39384efd39f90c4390d66bdd18f \
&& cp noto-emoji/fonts/NotoColorEmoji.ttf /usr/share/fonts/truetype/noto \
&& cp noto-emoji/fonts/NotoEmoji-Regular.ttf /usr/share/fonts/truetype/noto \
&& rm -rf noto-emoji

# Get Noto Emoji Regular font, despite it being deprecated by Google
RUN wget --quiet https://github.com/googlefonts/noto-emoji/blob/9a5261d871451f9b5183c93483cbd68ed916b1e9/fonts/NotoEmoji-Regular.ttf?raw=true --content-disposition -P /usr/share/fonts/

# Configure stylesheet
RUN mkdir -p /home/renderer/src \
 && cd /home/renderer/src \
 && git clone https://github.com/bencollinsuk/world-bike-map-cartocss-style.git \
 && cd world-bike-map-cartocss-style \
 && sed -i 's/, "unifont Medium", "Unifont Upper Medium"//g' style/fonts.mss \
 && sed -i 's/"Noto Sans Tibetan Regular",//g' style/fonts.mss \
 && sed -i 's/"Noto Sans Tibetan Bold",//g' style/fonts.mss \
 && sed -i 's/Noto Sans Syriac Eastern Regular/Noto Sans Syriac Regular/g' style/fonts.mss \
 && cp views.sql / \
 && rm -rf .git \
 && echo 'INFO: Installing carto' \
 && npm install -g carto@0.18.2 \
 && mkdir data \
 && cd data \
 && wget -O simplified-land-polygons.zip http://osmdata.openstreetmap.de/download/simplified-land-polygons-complete-3857.zip \
 && wget -O land-polygons.zip http://osmdata.openstreetmap.de/download/land-polygons-split-3857.zip \
 && unzip simplified-land-polygons.zip \
 && unzip land-polygons.zip \
 && rm /home/renderer/src/world-bike-map-cartocss-style/data/*.zip \
 && cd .. \
 && sed -i 's/dbname: "osm"/dbname: "gis"/g' project.mml \
 && sed -i 's,http://osmdata.openstreetmap.de/download/simplified-land-polygons-complete-3857.zip,data/simplified-land-polygons-complete-3857/simplified_land_polygons.shp,g' project.mml \
 && sed -i 's,http://osmdata.openstreetmap.de/download/land-polygons-split-3857.zip,data/land-polygons-split-3857/land_polygons.shp,g' project.mml

COPY renderd.conf /etc/renderd.conf

# # Configure renderd
# RUN sed -i 's/renderaccount/renderer/g' /etc/renderd.conf \
#  && sed -i 's/\/truetype//g' /etc/renderd.conf \
#  && sed -i 's/hot/tile/g' /etc/renderd.conf \
#  && sed -i 's/openstreetmap-carto/world-bike-map-cartocss-style/g' /etc/renderd.conf

# Configure Apache
RUN mkdir /var/lib/mod_tile \
 && chown renderer /var/lib/mod_tile \
 && mkdir /var/run/renderd \
 && chown renderer /var/run/renderd \
 && echo "LoadModule tile_module /usr/lib/apache2/modules/mod_tile.so" >> /etc/apache2/conf-available/mod_tile.conf \
 && echo "LoadModule headers_module /usr/lib/apache2/modules/mod_headers.so" >> /etc/apache2/conf-available/mod_headers.conf \
 && a2enconf mod_tile && a2enconf mod_headers
COPY apache.conf /etc/apache2/sites-available/000-default.conf
COPY security.conf /etc/apache2/conf-enabled/security.conf
RUN rm /var/www/html/index.html
COPY leaflet.html /var/www/html/index.html
COPY leaflet.js /var/www/html/
COPY leaflet.css /var/www/html/
RUN ln -sf /dev/stdout /var/log/apache2/access.log \
 && ln -sf /dev/stderr /var/log/apache2/error.log


# Create volume directories
RUN mkdir -p /run/renderd/ \
  &&  mkdir  -p  /data/style/  \
  &&  mkdir  -p  /home/renderer/src/  \
  &&  chown  -R  renderer:  /data/  \
  &&  chown  -R  renderer:  /home/renderer/src/  \
  &&  chown  -R  renderer:  /run/renderd  \
  &&  chown  -R  renderer: /var/cache/renderd/tiles \
;

# Copy update scripts
COPY openstreetmap-tiles-update-expire /usr/bin/
RUN chmod +x /usr/bin/openstreetmap-tiles-update-expire \
 && mkdir /var/log/tiles \
 && chmod a+rw /var/log/tiles \
 && ln -s /home/renderer/src/mod_tile/osmosis-db_replag /usr/bin/osmosis-db_replag \
 && echo "*  *    * * *   renderer    openstreetmap-tiles-update-expire\n" >> /etc/crontab

# Install trim_osc.py helper script
RUN mkdir -p /home/renderer/src \
 && cd /home/renderer/src \
 && git clone https://github.com/zverik/regional \
 && cd regional \
 && git checkout 889d630a1e1a1bacabdd1dad6e17b49e7d58cd4b \
 && rm -rf .git \
 && chmod u+x /home/renderer/src/regional/trim_osc.py

# Start running
COPY ./scripts/render_list_geo.pl /
COPY indexes.sql /
COPY scripts/server.sh /
COPY scripts/import.sh /
COPY wait-for-it.sh /
COPY wait-for-file.sh /
CMD ["run.sh"]
EXPOSE 80
