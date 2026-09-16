# ==============================================================================
# Multi-stage Dockerfile para MistakeMap (Flutter Web no Google Cloud Run)
# Totalmente otimizado para baixo consumo de memória e inicialização rápida
# ==============================================================================

# Etapa 1: Build da aplicação Flutter Web
FROM ghcr.io/cirruslabs/flutter:stable AS builder

WORKDIR /app

# Copia dependências e resolve os pacotes
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

# Copia o código-fonte e compila para Web (release)
COPY . .
RUN flutter build web --release

# ------------------------------------------------------------------------------
# Etapa 2: Servidor Nginx Alpine ultraleve (< 25MB) para servir os arquivos estáticos
# ------------------------------------------------------------------------------
FROM nginx:alpine-slim

# Remove a configuração padrão do Nginx
RUN rm -rf /etc/nginx/conf.d/*

# Copia nossa configuração otimizada de SPA e porta do Cloud Run
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copia os artefatos compilados do Flutter Web
COPY --from=builder /app/build/web /usr/share/nginx/html

# Porta padrão utilizada pelo Google Cloud Run (8080)
EXPOSE 8080

# Inicia o Nginx em primeiro plano
CMD ["nginx", "-g", "daemon off;"]
