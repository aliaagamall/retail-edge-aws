#!/bin/bash

set -uo pipefail

CONFIG_FILE="/opt/retailedge/config.env"
LOG_FILE="/var/log/retailedge-deploy.log"
CONTAINER_NAME="retailedge-app"
HEALTH_URL="http://localhost:8080/health"
HEALTH_RETRIES=10
HEALTH_INTERVAL=3

log() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $*" | tee -a "$LOG_FILE"
}

if [ $# -ne 1 ]; then
  log "ERROR: usage: deploy.sh <image_tag>"
  exit 1
fi

IMAGE_TAG="$1"

# Load environment-specific configuration.
if [ ! -f "$CONFIG_FILE" ]; then
  log "ERROR: config file $CONFIG_FILE not found"
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

log "=== Starting deployment of image tag: $IMAGE_TAG ==="

# Authenticate Docker with Amazon ECR.
if ! aws ecr get-login-password --region "$REGION" \
    | docker login --username AWS --password-stdin "$ECR_REPO" >>"$LOG_FILE" 2>&1; then
  log "ERROR: docker login to ECR failed"
  exit 1
fi

# Pull the requested image from ECR.
log "Pulling $ECR_REPO:$IMAGE_TAG"
if ! docker pull "$ECR_REPO:$IMAGE_TAG" >>"$LOG_FILE" 2>&1; then
  log "ERROR: docker pull failed for tag $IMAGE_TAG"
  exit 1
fi

# Replace the currently running container.
log "Stopping existing container (if any)"
docker stop "$CONTAINER_NAME" >>"$LOG_FILE" 2>&1 || true
docker rm "$CONTAINER_NAME" >>"$LOG_FILE" 2>&1 || true

log "Starting new container"
if ! docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    -p 8080:8080 \
    -e AWS_REGION="$REGION" \
    -e DB_SECRET_NAME="$DB_SECRET_NAME" \
    -e REDIS_SECRET_NAME="$REDIS_SECRET_NAME" \
    "$ECR_REPO:$IMAGE_TAG" >>"$LOG_FILE" 2>&1; then
  log "ERROR: docker run failed"
  exit 1
fi

# Wait until the application is healthy.
log "Waiting for health check at $HEALTH_URL"
attempt=0

while [ "$attempt" -lt "$HEALTH_RETRIES" ]; do
  if curl -sf -o /dev/null "$HEALTH_URL"; then
    log "=== Health check passed - $IMAGE_TAG is live ==="
    exit 0
  fi

  attempt=$((attempt + 1))
  sleep "$HEALTH_INTERVAL"
done

# Remove the failed container so another deployment or rollback can run.
log "ERROR: health check did not pass after $((HEALTH_RETRIES * HEALTH_INTERVAL))s"
log "Stopping failed container"

docker stop "$CONTAINER_NAME" >>"$LOG_FILE" 2>&1 || true
docker rm "$CONTAINER_NAME" >>"$LOG_FILE" 2>&1 || true

log "=== Deployment of $IMAGE_TAG FAILED ==="
exit 1