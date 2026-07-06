# Reproducible build image matching rom4s Travis: Ubuntu 14.04 + clang-9 + gcc-9-multilib.
FROM ubuntu:14.04

ENV DEBIAN_FRONTEND=noninteractive
ENV WDIR=/src

# Trusty packages remain on archive.ubuntu.com (do not redirect to old-releases).
RUN apt-get update -qq && apt-get install -y -qq \
    software-properties-common \
    curl \
    git \
    ca-certificates \
    aria2 \
    build-essential \
    file \
    zlib1g-dev \
    libssl-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

# Match original Travis Python 3.6.8 (trusty ships 3.4).
RUN curl -fsSL https://www.python.org/ftp/python/3.6.8/Python-3.6.8.tgz -o /tmp/Python-3.6.8.tgz \
    && tar -xzf /tmp/Python-3.6.8.tgz -C /tmp \
    && cd /tmp/Python-3.6.8 \
    && ./configure --prefix=/opt/python3.6 \
    && make -j"$(nproc)" \
    && make install \
    && /opt/python3.6/bin/pip3 install --upgrade pip \
    && rm -rf /tmp/Python-3.6.8*

ENV PATH="/opt/python3.6/bin:${PATH}"

# Original Travis used gcc 9.3.0-11ubuntu0~14.04 from ubuntu-toolchain-r/test.
# That exact PPA revision is superseded; rebuild it from Launchpad source + diff.
COPY builder/docker/trusty/install-gcc-9.3.0.sh /usr/local/sbin/install-gcc-9.3.0.sh
RUN chmod +x /usr/local/sbin/install-gcc-9.3.0.sh \
    && dpkg --add-architecture i386 \
    && apt-get update -qq \
    && /usr/local/sbin/install-gcc-9.3.0.sh \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src

# Default command: run the trusty repro build inside the mounted workspace.
CMD ["bash", "-lc", "chmod +x builder/run/linux-repro-trusty.sh builder/run/linux-repro.sh builder/install-clang9.sh builder/checkout-deps.sh builder/package.sh builder/prepare-package.sh builder/compare-release.sh builder/patches/*.sh && builder/run/linux-repro-trusty.sh"]
