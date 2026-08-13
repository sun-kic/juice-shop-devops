# Juice Shop's own Dockerfile, v20.1.1 — annotated.
# This is the file the project ships. It is used unchanged, and the reason it
# looks "wrong" is itself the lesson. See the note below.

FROM node:24 AS installer

# The whole source is copied BEFORE any install. That is normally an
# anti-pattern -- see the note -- but Juice Shop's postinstall script does
# "cd frontend && npm install", so the source must already be present.
COPY . /juice-shop
WORKDIR /juice-shop

RUN npm install -g typescript@^6.0.3
RUN npm install --omit=dev
RUN npm dedupe --omit=dev

RUN rm -rf frontend/node_modules frontend/.angular frontend/src/assets
RUN mkdir logs && chown -R 65532 logs
RUN chgrp -R 0 ftp/ frontend/dist/ logs/ data/ i18n/ \
 && chmod -R g=u ftp/ frontend/dist/ logs/ data/ i18n/
RUN rm ftp/legal.md || true
RUN rm i18n/*.json || true

ARG CYCLONEDX_NPM_VERSION='^2.0.0||^3.0.0||^4.0.0'
RUN npm install -g @cyclonedx/cyclonedx-npm@$CYCLONEDX_NPM_VERSION
RUN npm run sbom

# ---- runtime: distroless, non-root ----
FROM gcr.io/distroless/nodejs24-debian13
WORKDIR /juice-shop
COPY --from=installer --chown=65532:0 /juice-shop .
USER 65532
EXPOSE 3000
CMD ["/juice-shop/build/app.js"]
