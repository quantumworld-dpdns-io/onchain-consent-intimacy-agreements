FROM rust:1.77 AS builder
WORKDIR /app
COPY . .
RUN cargo build --release

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/rust-zk-service /usr/local/bin/
EXPOSE 3000
CMD ["rust-zk-service"]
