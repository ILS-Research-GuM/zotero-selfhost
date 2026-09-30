FROM node:22-alpine AS build
WORKDIR /app
COPY docker/portal/package.json docker/portal/package-lock.json ./
RUN npm ci --no-fund --no-audit
COPY docker/portal/ ./
RUN npm run check && npm run build && npm prune --omit=dev

FROM node:22-alpine
WORKDIR /app
COPY --from=build /app/build ./build
COPY --from=build /app/node_modules ./node_modules
COPY --from=build /app/package.json ./
COPY docker/portal/docker-entrypoint.sh /usr/local/bin/
# Translation requests (import) can be large
ENV PORT=80 BODY_SIZE_LIMIT=10M NODE_ENV=production
USER node
EXPOSE 80
ENTRYPOINT ["docker-entrypoint.sh"]
