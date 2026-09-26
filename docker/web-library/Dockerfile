FROM node:24-bookworm AS build

# The build needs git metadata of the submodules, so clone instead of copying.
# Set to the commit of src/server/web-library (see utils/build.sh).
ARG WEB_LIBRARY_COMMIT
RUN test -n "$WEB_LIBRARY_COMMIT" \
	&& git clone https://github.com/zotero/web-library.git /src \
	&& cd /src && git checkout "$WEB_LIBRARY_COMMIT" \
	&& git submodule update --init --recursive --depth 1

WORKDIR /src
RUN npm ci && npm run build

FROM nginx:1-alpine

COPY --from=build /src/build/ /usr/share/nginx/html/
