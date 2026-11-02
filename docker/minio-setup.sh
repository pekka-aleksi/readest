#!/bin/sh
# Create (or reuse) the Readest bucket on whatever S3/MinIO S3_ENDPOINT points at.
# Used both for the bundled MinIO service and for an external S3-compatible store.
set -eu

ENDPOINT="${S3_ENDPOINT:-http://minio:9000}"
BUCKET="${S3_BUCKET_NAME:-readest-files}"

i=0
until mc alias set myminio "$ENDPOINT" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD"; do
  i=$((i + 1))
  if [ "$i" -ge 30 ]; then
    echo "minio-setup: cannot reach $ENDPOINT" >&2
    exit 1
  fi
  sleep 2
done

mc mb --ignore-existing "myminio/$BUCKET"

# Presigned browser uploads are cross-origin unless S3 is reverse-proxied onto
# SITE_URL. AllowedOrigins is the Readest origin, not the MinIO host.
origins="${S3_CORS_ORIGINS:-${SITE_URL:-}}"
if [ -n "$origins" ]; then
  origins_json=""
  old_ifs=$IFS
  IFS=','
  for origin in $origins; do
    origin=$(printf '%s' "$origin" | tr -d ' ')
    [ -z "$origin" ] && continue
    if [ -n "$origins_json" ]; then
      origins_json="$origins_json,"
    fi
    origins_json="$origins_json\"$origin\""
  done
  IFS=$old_ifs
  if [ -n "$origins_json" ]; then
    printf '%s\n' "[{\"AllowedOrigins\":[$origins_json],\"AllowedMethods\":[\"GET\",\"PUT\",\"POST\",\"DELETE\",\"HEAD\"],\"AllowedHeaders\":[\"*\"],\"ExposeHeaders\":[\"ETag\",\"x-amz-request-id\",\"Content-Length\"],\"MaxAgeSeconds\":3600}]" >/tmp/cors.json
    mc cors set "myminio/$BUCKET" /tmp/cors.json || echo "minio-setup: warning: could not set CORS on $BUCKET" >&2
  fi
fi

echo "minio-setup: bucket '$BUCKET' ready on $ENDPOINT"
