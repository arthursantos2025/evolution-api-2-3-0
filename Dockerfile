FROM node:20-alpine AS builder

# Instalar solo lo necesario
RUN apk --no-cache add git ffmpeg bash openssl curl wget

LABEL version="2.3.0" description="API to control WhatsApp features via HTTP" \
      maintainer="Davidson Gomes" git="https://github.com/DavidsonGomes" \
      contact="contato@evolution-api.com"

WORKDIR /evolution

# Si la variable existe en el entorno, crea el archivo .env
# Eliminar el bloque RUN que genera el .env

COPY package*.json tsconfig.json ./

# Usa versión local actualizada de npm si realmente es necesario
RUN npm install -g npm@latest && \
    npm install --legacy-peer-deps && \
    npm cache clean --force

COPY ./src ./src
COPY ./public ./public
COPY ./prisma ./prisma
COPY ./manager ./manager
COPY .env.example .env
COPY runWithProvider.js .
COPY tsup.config.ts .
COPY Docker ./Docker

# Asegurar permisos en scripts
RUN chmod +x ./Docker/scripts/* && dos2unix ./Docker/scripts/*

# Si falla este paso, puede moverlo al contenedor final
RUN ./Docker/scripts/generate_database.sh || echo "Skipping DB generation (may be handled at runtime)"

RUN npm run build


# ---------------- FINAL STAGE ----------------
FROM node:20-alpine AS final

RUN apk --no-cache add tzdata ffmpeg bash openssl

ENV TZ=America/Sao_Paulo

WORKDIR /evolution

COPY --from=builder /evolution/package*.json ./
COPY --from=builder /evolution/node_modules ./node_modules
COPY --from=builder /evolution/dist ./dist
COPY --from=builder /evolution/prisma ./prisma
COPY --from=builder /evolution/manager ./manager
COPY --from=builder /evolution/public ./public
COPY --from=builder /evolution/Docker ./Docker
COPY --from=builder /evolution/runWithProvider.js .
COPY --from=builder /evolution/tsup.config.ts .

ENV DOCKER_ENV=true

EXPOSE 8080

# Ejecutar migraciones en contenedor final
ENTRYPOINT ["/bin/sh", "-c", "echo 'DATABASE_URL='$DATABASE_URL; if [ ! -f .env ] && [ ! -z \"$DATABASE_URL\" ]; then echo \"DATABASE_URL=\\\"$DATABASE_URL\\\"\" > .env; fi; echo 'Contenido de .env:'; cat .env; npx prisma migrate deploy && npm run start:prod"]
