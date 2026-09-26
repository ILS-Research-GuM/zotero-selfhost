FROM node:24-alpine

# Built from the pinned submodule, including its translators; utils/update.sh moves the pin.
# The upstream image instead pulls the latest translators on every start.
WORKDIR /app
COPY src/server/translation-server/package.json src/server/translation-server/package-lock.json ./
RUN npm ci --omit=dev
COPY src/server/translation-server/ ./

USER node
EXPOSE 1969
CMD ["node", "src/server.js"]
