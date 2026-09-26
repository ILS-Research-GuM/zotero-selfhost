FROM node:22-alpine

WORKDIR /app
RUN npm install --omit=dev tinymce.html@4.5.2 mocha@10
COPY src/server/tinymce-clean-server/lib ./lib
COPY src/server/tinymce-clean-server/test ./test
COPY docker/tinymce-clean/server.js ./
RUN npx mocha test && npm uninstall mocha

USER node
EXPOSE 16342
CMD ["node", "server.js"]
