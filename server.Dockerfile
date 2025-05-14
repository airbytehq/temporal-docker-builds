ARG BASE_SERVER_IMAGE=alpine:3.21

# The base image base-server.Dockerfile installs
# dockerize (with vulnerablities) and a couple of packages (curl, tzdata...)
# doing this inline so that we don't need to publish a fixed temporal base image
FROM golang:1.23-alpine3.21 AS dockerize

ARG DOCKERIZE_VERSION=v0.9.3
RUN go install github.com/jwilder/dockerize@${DOCKERIZE_VERSION}
RUN cp $(which dockerize) /usr/local/bin/dockerize


FROM ${BASE_SERVER_IMAGE} as temporal-server
ARG TARGETARCH
ARG TEMPORAL_SHA=unknown
ARG TCTL_SHA=unknown

WORKDIR /etc/temporal

ENV TEMPORAL_HOME=/etc/temporal
EXPOSE 6933 6934 6935 6939 7233 7234 7235 7239

# From base image
RUN apk upgrade --no-cache
RUN apk add --no-cache \
    ca-certificates \
    tzdata \
    bash \
    curl

COPY --from=dockerize /usr/local/bin/dockerize /usr/local/bin
# End base image block

# TODO switch WORKDIR to /home/temporal and remove "mkdir" and "chown" calls.
RUN addgroup -g 1000 temporal
RUN adduser -u 1000 -G temporal -D temporal
RUN mkdir /etc/temporal/config
RUN chown -R temporal:temporal /etc/temporal/config
USER temporal

# store component versions in the environment
ENV TEMPORAL_SHA=${TEMPORAL_SHA}

# binaries
COPY ./build/${TARGETARCH}/temporal-server /usr/local/bin
COPY ./build/${TARGETARCH}/temporal /usr/local/bin

# configs
COPY ./temporal/config/dynamicconfig/docker.yaml /etc/temporal/config/dynamicconfig/docker.yaml
COPY ./temporal/docker/config_template.yaml /etc/temporal/config/config_template.yaml

# scripts
COPY ./docker/entrypoint.sh /etc/temporal/entrypoint.sh
COPY ./docker/start-temporal.sh /etc/temporal/start-temporal.sh

### Server release image ###
FROM temporal-server as server
ENTRYPOINT ["/etc/temporal/entrypoint.sh"]

### Server auto-setup image ###
##### Admin Tools #####
# This is injected as a context via the bakefile so we don't take it as an ARG
FROM temporaliotest/admin-tools as admin-tools
FROM temporal-server as auto-setup

WORKDIR /etc/temporal

# binaries
COPY ./build/${TARGETARCH}/temporal-cassandra-tool /usr/local/bin
COPY ./build/${TARGETARCH}/temporal-sql-tool /usr/local/bin

# configs
COPY  ./temporal/schema /etc/temporal/schema

# scripts
COPY ./docker/entrypoint.sh /etc/temporal/entrypoint.sh
COPY ./docker/start-temporal.sh /etc/temporal/start-temporal.sh
COPY ./docker/auto-setup.sh /etc/temporal/auto-setup.sh

ENTRYPOINT ["/etc/temporal/entrypoint.sh"]
CMD ["autosetup"]
