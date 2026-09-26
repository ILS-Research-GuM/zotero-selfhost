FROM node:22-alpine

WORKDIR /app
COPY src/server/stream-server/package.json src/server/stream-server/package-lock.json ./
RUN npm ci --omit=dev
COPY src/server/stream-server/ ./
COPY config/stream-server.js ./config/local.js

USER node
EXPOSE 8080
CMD ["node", "index.js"]
