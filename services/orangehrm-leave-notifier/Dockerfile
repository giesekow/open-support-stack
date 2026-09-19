FROM python:3.12-alpine

RUN apk add --no-cache su-exec tzdata \
    && addgroup -S notifier \
    && adduser -S -G notifier notifier \
    && mkdir -p /data \
    && chown notifier:notifier /data

WORKDIR /app

COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

COPY notifier.py ./
COPY entrypoint.sh /usr/local/bin/notifier-entrypoint

RUN chmod 755 /usr/local/bin/notifier-entrypoint

ENTRYPOINT ["/usr/local/bin/notifier-entrypoint"]
