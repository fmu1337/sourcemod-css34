# Prebuilt smoke/botplay runtime (test-images.yml): the pinned base image with
# testing/scripts/install-deps.sh already run. The build context holds only
# install-deps.sh. In the result, install-deps.sh from the same commit is a no-op.
ARG BASE
FROM ${BASE}
COPY install-deps.sh /opt/css34/install-deps.sh
RUN CSS34_DEPS_MARKER=1 bash /opt/css34/install-deps.sh \
 && rm -rf /var/lib/apt/lists/* /var/cache/apt/archives/*.deb /var/cache/yum /var/cache/dnf
LABEL org.opencontainers.image.source="https://github.com/fmu1337/sourcemod-css34" \
      org.opencontainers.image.description="CS:S v34 srcds smoke/botplay runtime (install-deps.sh prebuilt)"
