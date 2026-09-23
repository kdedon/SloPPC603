FROM debian:bookworm-20250811-slim@sha256:b1a741487078b369e78119849663d7f1a5341ef2768798f7b7406c4240f86aef

ARG DEBIAN_SNAPSHOT=20250811T000000Z
ARG SOURCE_DATE_EPOCH=0

RUN printf '%s\n' \
      "deb [check-valid-until=no] http://snapshot.debian.org/archive/debian/${DEBIAN_SNAPSHOT}/ bookworm main" \
      > /etc/apt/sources.list \
    && rm -f /etc/apt/sources.list.d/debian.sources \
    && apt-get -o Acquire::Check-Valid-Until=false update \
    && apt-get install --yes --no-install-recommends \
      binutils-powerpc-linux-gnu=2.40-2 \
      gcc-powerpc-linux-gnu=4:12.2.0-5 \
      make=4.3-4.1 \
      python3-minimal=3.11.2-1+b1 \
    && rm -rf /var/lib/apt/lists/*

ENV LC_ALL=C.UTF-8 \
    LANG=C.UTF-8 \
    SOURCE_DATE_EPOCH=${SOURCE_DATE_EPOCH}

WORKDIR /work/toolchain
CMD ["make", "all", "check"]
