FROM alpine:3.10.3 as base
LABEL maintainer="clabu"

RUN true \
 && apk add --no-cache \
      cairo \
      findutils \
      librrd \
      logrotate \
      nginx \
      nodejs \
      npm \
      runit \
      sqlite \
      expect \
      dcron \
      python3 \
 && rm -rf \
      /etc/nginx/conf.d/default.conf \
 && mkdir -p \
      /var/log/carbon \
      /var/log/graphite

FROM base as build
LABEL maintainer="clabu"

RUN true \
 && apk add --update \
      alpine-sdk \
      git \
      libffi-dev \
      pkgconfig \
      py3-cairo \
      py3-pip \
      py3-virtualenv \
      py-rrd \
      python3-dev \
      rrdtool-dev \
      wget \
 && virtualenv /opt/graphite \
 && . /opt/graphite/bin/activate \
 && pip3 install \
      django==1.11.25 \
      django-statsd-mozilla \
      fadvise \
      gunicorn \
      msgpack-python \
      rrdtool

ARG version=1.1.6

# install whisper
ARG whisper_version=${version}
ARG whisper_repo=https://github.com/graphite-project/whisper.git
RUN git clone -b ${whisper_version} --depth 1 ${whisper_repo} /usr/local/src/whisper \
 && cd /usr/local/src/whisper \
 && . /opt/graphite/bin/activate \
 && python3 ./setup.py install

# install carbon
ARG carbon_version=${version}
ARG carbon_repo=https://github.com/graphite-project/carbon.git
RUN . /opt/graphite/bin/activate \
 && git clone -b ${carbon_version} --depth 1 ${carbon_repo} /usr/local/src/carbon \
 && cd /usr/local/src/carbon \
 && pip3 install -r requirements.txt \
 && python3 ./setup.py install

# install graphite
ARG graphite_version=${version}
ARG graphite_repo=https://github.com/graphite-project/graphite-web.git
RUN . /opt/graphite/bin/activate \
 && git clone -b ${graphite_version} --depth 1 ${graphite_repo} /usr/local/src/graphite-web \
 && cd /usr/local/src/graphite-web \
 && pip3 install -r requirements.txt \
 && python3 ./setup.py install

# install statsd (as we have to use this ugly way)
ARG statsd_version=0.8.5
ARG statsd_repo=https://github.com/statsd/statsd.git
WORKDIR /opt
RUN git clone "${statsd_repo}" \
 && cd /opt/statsd \
 && git checkout tags/v"${statsd_version}" \
 && npm install

COPY conf/opt/graphite/conf/                             /opt/defaultconf/graphite/
COPY conf/opt/graphite/webapp/graphite/local_settings.py /opt/defaultconf/graphite/local_settings.py

# config graphite
COPY conf/opt/graphite/conf/*.conf /opt/graphite/conf/
COPY conf/opt/graphite/webapp/graphite/local_settings.py /opt/graphite/webapp/graphite/local_settings.py
WORKDIR /opt/graphite/webapp
RUN mkdir -p /var/log/graphite/ \
  && PYTHONPATH=/opt/graphite/webapp /opt/graphite/bin/django-admin.py collectstatic --noinput --settings=graphite.settings

# config statsd
COPY conf/opt/statsd/config/ /opt/defaultconf/statsd/config/

FROM base as production
LABEL maintainer="clabu"

ENV STATSD_INTERFACE udp

COPY conf /

# copy /opt from build image
COPY --from=build /opt /opt

# defaults
EXPOSE 80 2003-2004 2013-2014 2023-2024 8080 8125 8125/udp 8126
VOLUME ["/opt/graphite/conf", "/opt/graphite/storage", "/opt/graphite/webapp/graphite/functions/custom", "/etc/nginx", "/opt/statsd/config", "/etc/logrotate.d", "/var/log", "/var/lib/redis"]

STOPSIGNAL SIGHUP

ENTRYPOINT ["/entrypoint"]
