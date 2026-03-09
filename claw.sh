#!/bin/bash
set -e

IMAGE_NAME="claudeclaw"
CONTAINER_PREFIX="claw"
DATA_DIR="./data"

usage() {
  echo "Usage:"
  echo "  ./claw.sh add <name>       Create and start a new instance"
  echo "  ./claw.sh rm <name>        Stop and remove an instance"
  echo "  ./claw.sh login <name>     Run claude login for an instance"
  echo "  ./claw.sh logs <name>      Tail logs for an instance"
  echo "  ./claw.sh ps               List all running instances"
  echo "  ./claw.sh restart <name>   Restart an instance"
  echo "  ./claw.sh stop <name>      Stop an instance"
  echo "  ./claw.sh start <name>     Start a stopped instance"
  echo "  ./claw.sh build            Build the Docker image"
  echo "  ./claw.sh rebuild          Rebuild image and restart all instances"
  exit 1
}

container_name() {
  echo "${CONTAINER_PREFIX}-${1}"
}

ensure_image() {
  if ! docker image inspect "$IMAGE_NAME" > /dev/null 2>&1; then
    echo "Image not found. Building..."
    docker build -t "$IMAGE_NAME" .
  fi
}

cmd_build() {
  docker build -t "$IMAGE_NAME" .
}

cmd_rebuild() {
  docker build -t "$IMAGE_NAME" .
  # Restart all running claw containers
  for cid in $(docker ps -q --filter "name=^${CONTAINER_PREFIX}-"); do
    local name=$(docker inspect --format '{{.Name}}' "$cid" | sed 's|^/||')
    echo "Restarting $name..."
    docker stop "$name" && docker rm "$name"
    local user="${name#${CONTAINER_PREFIX}-}"
    cmd_add "$user"
  done
}

cmd_add() {
  local name="$1"
  [ -z "$name" ] && usage
  local cname=$(container_name "$name")

  if docker ps -a --format '{{.Names}}' | grep -q "^${cname}$"; then
    echo "Instance '$name' already exists. Use: ./claw.sh rm $name"
    exit 1
  fi

  ensure_image
  mkdir -p "${DATA_DIR}/${name}/home-claude" "${DATA_DIR}/${name}/workspace" "${DATA_DIR}/${name}/home-config"
  # Match UID of 'claw' user inside container (1001)
  if [ "$(id -u)" -eq 0 ]; then
    chown -R 1001:1001 "${DATA_DIR}/${name}"
  else
    sudo chown -R 1001:1001 "${DATA_DIR}/${name}"
  fi

  docker run -d \
    --name "$cname" \
    --restart unless-stopped \
    -v "$(pwd)/${DATA_DIR}/${name}/home-claude:/home/claw/.claude" \
    -v "$(pwd)/${DATA_DIR}/${name}/home-config:/home/claw/.config" \
    -v "$(pwd)/${DATA_DIR}/${name}/workspace:/workspace" \
    "$IMAGE_NAME"

  echo ""
  echo "Instance '$name' created."
  echo ""
  echo "Next steps:"
  echo "  1. Claude login:  ./claw.sh login $name"
  echo "  2. Edit settings: vi ${DATA_DIR}/${name}/workspace/.claude/claudeclaw/settings.json"
  echo "     Set telegram.token and telegram.allowedUserIds"
  echo "  3. Restart:       ./claw.sh restart $name"
}

cmd_rm() {
  local name="$1"
  [ -z "$name" ] && usage
  local cname=$(container_name "$name")

  docker stop "$cname" 2>/dev/null || true
  docker rm "$cname" 2>/dev/null || true
  echo "Instance '$name' removed. Data preserved in ${DATA_DIR}/${name}/"
}

cmd_login() {
  local name="$1"
  [ -z "$name" ] && usage
  docker exec -it "$(container_name "$name")" claude login
}

cmd_logs() {
  local name="$1"
  [ -z "$name" ] && usage
  docker logs -f "$(container_name "$name")"
}

cmd_ps() {
  docker ps --filter "name=^${CONTAINER_PREFIX}-" --format "table {{.Names}}\t{{.Status}}\t{{.CreatedAt}}"
}

cmd_restart() {
  local name="$1"
  [ -z "$name" ] && usage
  docker restart "$(container_name "$name")"
}

cmd_stop() {
  local name="$1"
  [ -z "$name" ] && usage
  docker stop "$(container_name "$name")"
}

cmd_start() {
  local name="$1"
  [ -z "$name" ] && usage
  docker start "$(container_name "$name")"
}

case "${1:-}" in
  add)     cmd_add "$2" ;;
  rm)      cmd_rm "$2" ;;
  login)   cmd_login "$2" ;;
  logs)    cmd_logs "$2" ;;
  ps)      cmd_ps ;;
  restart) cmd_restart "$2" ;;
  stop)    cmd_stop "$2" ;;
  start)   cmd_start "$2" ;;
  build)   cmd_build ;;
  rebuild) cmd_rebuild ;;
  *)       usage ;;
esac
