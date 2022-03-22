#!/bin/bash

set -e
#set -x

# `````

PROJECT_BASE=$(pwd)
CONFIG_FILE=${PROJECT_BASE}/.dev-config

if ! [ "$BASH_SOURCE" ]; then
  echo "Do not use subshell, exiting"
  exit 1
fi

get_script_dir() {
  SOURCE="${BASH_SOURCE[0]}"
  while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
  done
  SCRIPT_PATH="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
  echo "$SCRIPT_PATH"
}

DEV_STACK_BASE="${PROJECT_BASE}/vendor/solcloud/dev-stack"
if ! [ -d "$DEV_STACK_BASE" ]; then
  DEV_STACK_BASE=$(realpath "$(get_script_dir)/../")
  if ! [ -d "$DEV_STACK_BASE" ]; then
    echo "Cannot decide script path"
    exit 1
  fi
fi

if [ "$1" ] && [ "$1" == "init" ]; then
  cp -i ${DEV_STACK_BASE}/src/.dev-config.example $CONFIG_FILE
  echo "Example config file created $CONFIG_FILE"
  exit 0
fi

if [[ ! -f $CONFIG_FILE ]]; then
  echo "No config file found, run init command or create it manually"
  exit 1
fi

PROJECT_NAME=$(cat $CONFIG_FILE | grep "PROJECT_NAME=" | grep -o "=.*" | cut -d'=' -f 2)
PREFIX=$(cat $CONFIG_FILE | grep "PREFIX=" | grep -o "=.*" | cut -d'=' -f 2)
PREFIX=${PREFIX:-'solcloud_'}
PROXY_PORT=${PROXY_PORT:-1122}
REMOTE_PROXY_PORT=${REMOTE_PROXY_PORT:-$PROXY_PORT}
NETWORK_NAME="n_${PREFIX}net"
COMPOSE_FILE=${COMPOSE_FILE:-"${DEV_STACK_BASE}/src/docker/docker-compose.yml"}
WEBSERVER_NAME="${PROJECT_NAME}-webserver"
NODE_VERSION=${NODE_VERSION:-"node:current-alpine"}

if [ -z "$PROJECT_NAME" ]; then
    echo "Project name cannot be empty"
    exit 1
fi

######
######
######

service_ip() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}'  $1
}

setup_network() {
  if [[ $(docker network ls -f name=${NETWORK_NAME} | grep -w ${NETWORK_NAME} ) ]]; then
    echo "Network $NETWORK_NAME exists"
  else
    echo "Creating network $NETWORK_NAME"
    docker network create --driver=bridge $NETWORK_NAME
  fi
}

start_service() {
  if [[ $(docker ps -f name="$1" | grep -w "$1") ]]; then
     echo "Service $1 already running"
  else
    echo "Starting $1"
    if [[ $(docker ps -a -f name="$1" | grep -w "$1") ]]; then
        docker start "$1"
    else
      docker run -d --network=${NETWORK_NAME} --name="$1" $2
    fi
  fi
}

volume_path() {
  docker volume inspect "v_${PREFIX}$1" | grep Mountpoint | cut -d  ':' -f 2 | grep -oP '"(.+)",' | cut -d'"' -f 2
}

setup_services() {
  if [[ $HAS_PROXY == 1 ]]; then
    start_service "n_jw_proxy_${NETWORK_NAME}" "-p ${REMOTE_PROXY_PORT}:80 -v /var/run/docker.sock:/tmp/docker.sock:ro -v ${DEV_STACK_BASE}/src/docker/proxy.conf:/etc/nginx/conf.d/my_proxy.conf:ro jwilder/nginx-proxy@sha256:53004448ff1b987e2ae01841365b7f121c75c7928a3c4621cde69ac498badcff"
  fi

  if [[ $HAS_DB == 1 ]]; then
    DATA=$(volume_path 'mysql')
    start_service "${PREFIX}mysql" "--env MYSQL_USER=dev --env MYSQL_ROOT_PASSWORD=dev -v ${DATA}:/var/lib/mysql ${DB_VERSION:-mariadb:10.2.18}"

    start_service "${PREFIX}adminer" "--user www-data:www-data --env VIRTUAL_HOST=adminer.localhost --env ADMINER_DESIGN=nette --env NETWORK_ACCESS=internal --env ADMINER_DEFAULT_SERVER=${PREFIX}mysql adminer@sha256:983035c7ace2a1c300226fb7e901498eb7af0707ee4c8128d12d6460b07995c9" # 4.7.7-standalone
  fi

  if [[ $HAS_RABBIT == 1 ]]; then
    DATA=$(volume_path 'rabbitmq')
    start_service "${PREFIX}rabbitmq" "--hostname rabbitmq --env VIRTUAL_HOST=rabbitmq.localhost --env VIRTUAL_PORT=15672 --env RABBITMQ_DEFAULT_USER=dev --env RABBITMQ_DEFAULT_PASS=dev --env NETWORK_ACCESS=internal --env RABBITMQ_NODENAME=bunny1@rabbitmq -v ${DATA}:/var/lib/rabbitmq ${RABBITMQ_VERSION:-rabbitmq:3.6.12-management-alpine}"
  fi

  if [[ $HAS_REDIS == 1 ]]; then
    DATA=$(volume_path 'redis')
    start_service "${PREFIX}redis" "-v ${DATA}:/data ${REDIS_VERSION:-redis:3.2.12-alpine}"
  fi

  if [[ $HAS_MINIO == 1 ]]; then
    start_service "${PREFIX}minio" "--env MINIO_ROOT_USER=dev --env MINIO_ROOT_PASSWORD=devdevdev --env NETWORK_ACCESS=internal --env VIRTUAL_HOST=minio.localhost -p 9001:9001 --env VIRTUAL_PORT=9001 ${MINIO_VERSION:-minio/minio} server /data --console-address 0.0.0.0:9001"
  fi
}

create_volumes() {
  if [[ $HAS_DB == 1 ]]; then
    if [[ ! $(docker volume ls | grep "v_${PREFIX}mysql") ]]; then
       docker volume create --name="v_${PREFIX}mysql"
    fi
  fi

  if [[ $HAS_REDIS == 1 ]]; then
    if [[ ! $(docker volume ls | grep "v_${PREFIX}redis") ]]; then
      docker volume create --name="v_${PREFIX}redis"
    fi
  fi

  if [[ $HAS_RABBIT == 1 ]]; then
    if [[ ! $(docker volume ls | grep "v_${PREFIX}rabbitmq") ]]; then
      docker volume create --name="v_${PREFIX}rabbitmq"
    fi
  fi
}

delete_volumes() {
  docker volume rm v_${PREFIX}mysql
  docker volume rm v_${PREFIX}redis
  docker volume rm v_${PREFIX}rabbitmq
}

list_proxy() {
  [ $HAS_PROXY == 1 ] && echo -n " $1"
}

list_services() {
  echo "################################################################################"
  echo ""
  echo "Webserver:$(list_proxy http://${PROJECT_NAME}.localhost:${PROXY_PORT}) http://$(service_ip ${WEBSERVER_NAME})"
  echo ""
  if [[ $HAS_DB == 1 ]]; then
    echo "Adminer:$(list_proxy http://adminer.localhost:${PROXY_PORT}) http://$(service_ip ${PREFIX}adminer):8080"
    echo "Mysql: $(service_ip ${PREFIX}mysql):3306"
  fi
  if [[ $HAS_RABBIT == 1 ]]; then
    echo "Rabbitmq management:$(list_proxy http://rabbitmq.localhost:${PROXY_PORT}) http://$(service_ip ${PREFIX}rabbitmq):15672"
  fi
  if [[ $HAS_REDIS == 1 ]]; then
    echo "Redis: $(service_ip ${PREFIX}redis):6378"
  fi
  if [[ $HAS_MINIO == 1 ]]; then
    echo "Minio management:$(list_proxy http://minio.localhost:${PROXY_PORT}) http://$(service_ip ${PREFIX}minio):9001"
    echo "Minio default user 'dev' pass 'devdevdev', S3 api http://$(service_ip ${PREFIX}minio):9000"
  fi
  echo ""
  echo "################################################################################"
}

COMPOSE="docker-compose -p $PROJECT_NAME -f $COMPOSE_FILE"
export PREFIX
export PROJECT_NAME
export PROJECT_BASE
export WEBSERVER_NAME
export CONFIG_FILE
export NETWORK_NAME
export USER=$(id -u)
export GROUP=$(id -g)
export APACHE_LOG_DIR=${APACHE_LOG_DIR:-'/var/log/apache2'}
export APACHE_LOG_LEVEL=${APACHE_LOG_LEVEL:-'warn'}
source <(sed 's/^/export /' $CONFIG_FILE)

# Prefix's defaults services
[ -z $DOCUMENT_ROOT ] && export DOCUMENT_ROOT=''
[ -z $PHP_VERSION ] && export PHP_VERSION=7.4
if [[ $PREFIX == 'solcloud_' ]]; then
  [ -z $HAS_PROXY ] && HAS_PROXY=1
  [ -z $HAS_DB ] && HAS_DB=1
  [ -z $HAS_RABBIT ] && HAS_RABBIT=1
  [ -z $HAS_REDIS ] && HAS_REDIS=1
  [ -z $HAS_MINIO ] && HAS_MINIO=0
else
  [ -z $HAS_PROXY ] && HAS_PROXY=0
  [ -z $HAS_DB ] && HAS_DB=0
  [ -z $HAS_RABBIT ] && HAS_RABBIT=0
  [ -z $HAS_REDIS ] && HAS_REDIS=0
  [ -z $HAS_MINIO ] && HAS_MINIO=0
fi

export COMPOSE_CONTEXT=${COMPOSE_CONTEXT:-'.'}
export BASE_IMAGE=${BASE_IMAGE:-"solcloud/php:${PHP_VERSION}"}

compose_up() {
  create_volumes
  setup_network
  setup_services

  export XDEBUG_MODE=${XDEBUG_MODE:-'off'}
  export GATEWAY=$(docker network inspect $NETWORK_NAME | grep 'Gateway' | grep -ohE '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}')
  $COMPOSE up -d --force-recreate --build
  [[ -n "${ROOT_SETUP}" ]] && docker exec --detach "$WEBSERVER_NAME" sh -c "$ROOT_SETUP" || true
}

compose_down() {
  export XDEBUG_MODE=''
  export GATEWAY=''
  $COMPOSE down
}

########
ARGS=( "$@" )
ARGS=("${ARGS[@]:1}")
if [[ $(tty) == "not a tty" ]]; then
  DOCKER_EXEC="docker exec -i --user $USER:$GROUP"
else
  DOCKER_EXEC="docker exec -it --user $USER:$GROUP"
fi

if [ "$1" ] && [ "$1" == "down" ]; then
  compose_down
  exit 0
fi
if [ "$1" ] && [ "$1" == "xdebug" ]; then
  echo "(Re)starting containers with xdebug enabled"
  XDEBUG_MODE=debug
  compose_up > /dev/null
  exit 0
fi
if [ "$1" ] && [ "$1" == "up" ]; then
  if [ "$2" ] && [ "$2" == "-v" ]; then
    compose_up
  else
    compose_up > /dev/null
  fi
  list_services
  exit 0
fi
if [ "$1" ] && [ "$1" == "www" ]; then
    if [ $HAS_PROXY == 1 ]; then
      echo "http://${PROJECT_NAME}.localhost:${PROXY_PORT}"
    else
      echo "http://$(service_ip ${WEBSERVER_NAME})"
    fi
    exit 0
fi
if [ "$1" ] && [ "$1" == "status" ]; then
  if [[ $(docker ps -f name="${WEBSERVER_NAME}" | grep -w "${WEBSERVER_NAME}") ]]; then
     list_services
  else
    echo "Project not UP, use 'dev up'"
  fi
  exit 0
fi
if [ "$1" ] && [ "$1" == "start" ]; then
  $COMPOSE start
  exit 0
fi
if [ "$1" ] && [ "$1" == "stop" ]; then
  $COMPOSE stop
  if [ "$2" ] && [ "$2" == "all" ]; then
    docker stop "$(docker ps -q -f name=$PREFIX)"
  fi
  exit 0
fi
if [ "$1" ] && [ "$1" == "volume" ]; then
  if [ "$2" ] && [ "$2" == "delete" ]; then
    delete_volumes
  else
    echo "delete: remove volumes"
  fi
  exit 0
fi
if [ "$1" ] && [ "$1" == "exec" ]; then
  if [ "$2" ]; then
    $DOCKER_EXEC $2 ${3:-'sh'}
  else
    docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  fi
  exit 0
fi
if [ "$1" ] && [ "$1" == "php" ]; then
  $DOCKER_EXEC "${WEBSERVER_NAME}" sh -c "umask 007 ; php ${ARGS[*]}"
  exit 0
fi
if [ "$1" ] && [ "$1" == "debug" ]; then
  $DOCKER_EXEC "${WEBSERVER_NAME}" sh -c "umask 007 ; export XDEBUG_MODE=debug ; php ${ARGS[*]}"
  exit 0
fi
if [ "$1" ] && [ "$1" == "worker" ]; then
  $DOCKER_EXEC "${WEBSERVER_NAME}" sh -c "umask 007 ; php ${ARGS[*]:-run.php}"
  exit 0
fi
if [ "$1" ] && [ "$1" == "compose" ]; then
  shift
  docker-compose $*
  exit 0
fi
if [ "$1" ] && [ "$1" == "composer" ]; then
  $DOCKER_EXEC "${WEBSERVER_NAME}" sh -c "mkdir -p /tmp/.composer/ ; php /utils/composer2.phar config --global process-timeout 6000 ; umask 007 ; php /utils/composer2.phar ${ARGS[*]}"
  exit 0
fi
if [ "$1" ] && [ "$1" == "composerssh" ]; then
  if [ ! "$SSH_AUTH_SOCK_PATH" ]; then
    SSH_AUTH_SOCK_PATH=/tmp/dev-stack-agent
    private_key=${PRIVATE_KEY:-~/.ssh/id_rsa}
    if ! test -r $private_key; then
      echo "Cannot read key from: $private_key use PRIVATE_KEY variable for alternative"
      exit 1
    fi
    rm -f $SSH_AUTH_SOCK_PATH
    eval $(ssh-agent -a $SSH_AUTH_SOCK_PATH)
    ssh-add -t 300 $private_key
  fi
  auth_json=${AUTH_JSON:-~/.composer/auth.json}
  test -r $auth_json && cp $auth_json /tmp/dev-stack-auth.json

  $DOCKER_EXEC "${WEBSERVER_NAME}" sh -c "mkdir -p /tmp/.composer/ ; php /utils/composer2.phar config --global process-timeout 6000 ; ln -sf /share/dev-stack-auth.json /tmp/.composer/auth.json ; export SSH_AUTH_SOCK=$SSH_AUTH_SOCK_PATH ; umask 007 ; php /utils/composer2.phar ${ARGS[*]}"

  rm -f /tmp/dev-stack-auth.json
  [ "$SSH_AGENT_PID" ] && eval $(ssh-agent -k)
  exit 0
fi
if [ "$1" ] && [ "$1" == "stan" ]; then
  $DOCKER_EXEC "${WEBSERVER_NAME}" sh -c "umask 007 ; php /utils/phpstan.phar --memory-limit=256M ${ARGS[*]}"
  exit 0
fi
if [ "$1" ] && [ "$1" == "md" ]; then
  $DOCKER_EXEC "${WEBSERVER_NAME}" sh -c "umask 007 ; php /utils/phpmd.phar ${ARGS[*]}"
  exit 0
fi
if [ "$1" ] && [ "$1" == "unit" ]; then
  $DOCKER_EXEC "${WEBSERVER_NAME}" sh -c "umask 007 ; php /utils/phpunit.phar ${ARGS[*]}"
  exit 0
fi
if [ "$1" ] && [ "$1" == "node" ]; then
    docker run -it --user $USER:$GROUP -v ${PROJECT_BASE}:/dir -w /dir --env HOME=/tmp $NODE_VERSION "${ARGS[@]:-sh}"
    exit 0
fi
if [ "$1" ] && [ "$1" == "greenmail" ]; then
    docker run -d \
      -e GREENMAIL_OPTS='-Dgreenmail.users=user:user@nice.localhost -Dgreenmail.setup.test.all -Dgreenmail.hostname=0.0.0.0 -Dgreenmail.verbose' \
      -e JAVA_OPTS='-Djava.net.preferIPv4Stack=true -Xmx648m' \
      -p 3025:3025 -p 3110:3110 -p 3143:3143 -p 3465:3465 -p 3993:3993 -p 3995:3995 -p 8080:8080 \
      greenmail/standalone:1.6.3
    exit 0
fi
if [ "$1" ] && [ "$1" == "logs" ]; then
    docker logs $2
    exit 0
fi
if [ "$1" ] && [ "$1" == "cmd" ]; then
    $DOCKER_EXEC "${WEBSERVER_NAME}" "${ARGS[@]:-sh}"
    exit 0
fi
if [ "$1" ] && [ "$1" == "ws" ]; then
  $DOCKER_EXEC "${WEBSERVER_NAME}" ${2:-bash}
  exit 0
fi
if [ "$1" ] && [ "$1" == "root" ]; then
  docker exec -it --user 0:0 "${2:-$WEBSERVER_NAME}" ${2:-sh}
  exit 0
fi
if [ "$1" ] && [ "$1" == "rebuild" ]; then
  if [ "$2" ] && [ "$2" == "-f" ]; then
    compose_down
    services=$(docker ps --quiet --all --filter name=${PREFIX})
    [[ $services == '' ]] || docker rm --force --volumes $services
    compose_up
    list_services
    exit 0
  else
    echo "Destructive action, are you sure, use -f"
    exit 0
  fi
  exit 0
fi

usage() {
  cat >&2 << USAGE_HELP
$0 COMMAND [options]

  cmd [PARAMS = sh]- run PARAMS inside webserver container

  compose - run docker compose

  composer - run php composer inside webserver container
             update
             install
             -o --no-dev

  composerssh - run php composer with ssh-agent, for cloning private repositories

  debug [PHP_OPTION] - enable xdebug's debug mode on single php binary execution, mostly for single shot xdebugging php program 'dev debug file.php'

  down - stop project container(s)

  exec - list containers with same prefix

  exec [CONTAINER_NAME] [COMMAND = sh] - exec into container CONTAINER_NAME using COMMAND, without CONTAINER_NAME list current prefix containers

  greenmail - run localhost greenmail instance for email testing

  init - copy template .dev-config file to project root

  logs - docker logs

  md - run PHP Mess Detector, static analysis tool for php
       md [sources] [ansi|html|text|xml|json]  ruleset       PHP Mess Detector
       md src/,tests/ ansi cleancode,codesize,controversial,design,naming,unusedcode

  node - run NODE_VERSION node command
         npm
         npx

  php - run php command inside webserver container
        -a
        -r
        -v
        --ini
        file.php

  rebuild - remove volumes and rebuild whole PREFIX images, danger action use with care

  root [CONTAINER_NAME = webserver] [COMMAND = sh] - exec into container (by default webserver) as user 0:0 spawning COMMAND (by default sh)

  stan - run PHPStan, static analysis tool for php
         analyse --level max

  start - run docker compose start

  status - print info about containers

  stop - run docker compose stop

  unit - run PHPUnit, testing framework for php

  up - start project container(s)

  volume delete - delete current PREFIX volumes, danger use with care

  worker - run php binary inside webserver container with path run.php

  ws [COMMAND = sh] - exec inside webserver container spawning COMMAND (default sh)

  xdebug - (re)start container(s) with xdebug's debug mode enabled on webserver (slower response)


USAGE_HELP
  exit 1
}

usage
########

