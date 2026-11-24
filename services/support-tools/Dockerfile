FROM python:3.12-alpine@sha256:4c47124a8391cb7a9f571164147d154777cf012a4ece5f86097130d7a4478111

RUN apk add --no-cache su-exec tzdata \
    && addgroup -S support-tools \
    && adduser -S -G support-tools support-tools \
    && mkdir -p /app /runtime/templates \
    && chown -R support-tools:support-tools /app /runtime

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY alembic.ini ./
COPY migrations ./migrations
COPY app ./app
COPY tests ./tests
COPY entrypoint.sh /usr/local/bin/support-tools-entrypoint

RUN chmod 755 /usr/local/bin/support-tools-entrypoint

EXPOSE 8000

ENTRYPOINT ["/usr/local/bin/support-tools-entrypoint"]
