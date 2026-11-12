# Builder e runtime DEVEM usar a mesma release do Debian: o binário é compilado
# num estágio e copiado para o outro, então glibc e libssl precisam bater.
FROM rust:slim-trixie AS builder

# openssl-sys linka dinamicamente contra a libssl do sistema.
RUN apt-get update && apt-get install -y pkg-config libssl-dev && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copia só os manifestos primeiro: se o código mudar mas as dependências não,
# o Docker reaproveita a camada com as dependências já compiladas.
COPY Cargo.toml Cargo.lock ./

RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release
RUN rm src/main.rs

# `touch` deixa o main.rs mais novo que o artefato do build anterior, forçando
# o cargo a recompilar o crate real em vez de reaproveitar o binário dummy.
COPY src ./src
RUN touch src/main.rs && cargo build --release

FROM debian:trixie-slim

# ca-certificates: TLS para Supabase, R2 e JWKS.
# openssl: puxa a libssl correta do trixie sem depender do nome do pacote.
RUN apt-get update && apt-get install -y ca-certificates openssl && rm -rf /var/lib/apt/lists/*

COPY --from=builder /app/target/release/mistakemap-worker /usr/local/bin/worker

CMD ["worker"]
