# syntax=docker/dockerfile:1
#
# cwv — static, single-binary image.
#
#   docker build -t cwv .
#   docker run --rm cwv rates --city berlin
#
# Stage 1 builds a fully static musl binary (rustls + bundled webpki roots,
# no OpenSSL). The builder uses the crate's MSRV, so the image build also
# proves `rust-version` is honest. Stage 2 is `scratch`: just the binary.

ARG RUST_VERSION=1.88

FROM rust:${RUST_VERSION}-alpine AS build
RUN apk add --no-cache musl-dev
WORKDIR /src
# Dependencies first, so source edits do not refetch the registry.
COPY Cargo.toml Cargo.lock ./
RUN mkdir -p src/bin/cwv \
 && echo '' > src/lib.rs \
 && echo 'fn main() {}' > src/bin/cwv/main.rs \
 && cargo fetch --locked
COPY src ./src
RUN touch src/lib.rs src/bin/cwv/main.rs \
 && cargo build --release --locked --bin cwv \
 && cp target/release/cwv /cwv \
 && /cwv --version

FROM scratch
ARG VERSION=0.1.0
LABEL org.opencontainers.image.title="cwv" \
      org.opencontainers.image.description="Flexible-office prices by city (CoworkingView Price Index, CC BY 4.0) and coworking search, from the command line." \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.source="https://github.com/coworkingview/flex-office-data" \
      org.opencontainers.image.url="https://coworkingview.com" \
      org.opencontainers.image.documentation="https://github.com/coworkingview/flex-office-data/tree/main/rust#readme" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.vendor="CoworkingView"
COPY --from=build /cwv /usr/local/bin/cwv
ENV PATH=/usr/local/bin
USER 65534:65534
ENTRYPOINT ["cwv"]
