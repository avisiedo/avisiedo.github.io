ARG RUST_VERSION=1.57.0
FROM docker.io/rust:${RUST_VERSION} AS builder
RUN rustup target add aarch64-unknown-linux-gnu

RUN git clone https://github.com/cobalt-org/cobalt.rs.git /git
WORKDIR /git
RUN cargo build --verbose --release
RUN cargo install --path .

COPY . /src
WORKDIR /src
RUN cobalt build
CMD  ["cobalt", "serve"]
CMD  ["cobalt", "serve", "--drafts"]



ARG NGINX_VERSION=1.21.5
FROM docker.io/nginx:1.21.5 AS service
COPY --from=builder /src/_site /usr/share/nginx/html
WORKDIR /usr/share/nginx/html
