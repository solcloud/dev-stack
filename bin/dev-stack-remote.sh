#!/bin/bash

set -e

PROJECT_BASE="$(pwd)"
CONFIG_FILE=${PROJECT_BASE}/.dev-config
STORAGE_DIRVER=${STORAGE_DIRVER:-'virtiofs'} # virtiofs | sshfs | 9p | nfs
CODE_SRC_ROOT_DIR=${CODE_SRC_ROOT_DIR:-'/home/code/src/'}

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

LOCAL_PROXY_PORT=${LOCAL_PROXY_PORT:-1122}
REMOTE_PROXY_PORT=${REMOTE_PROXY_PORT:-80}

REMOTE_SYSTEM=${REMOTE_SYSTEM:-'qemu'} # qemu | real
REMOTE_DEV_STACK_BIN=${REMOTE_DEV_STACK_BIN:-'dev'}
REMOTE_USER=${REMOTE_USER:-'code'}
REMOTE_USER_UID=${REMOTE_USER_UID:-1007}
REMOTE_USER_GID=${REMOTE_USER_GID:-1007}
REMOTE_IP=${REMOTE_IP:-'virtual'} # routable IP from host perspective
REMOTE_IP_REAL=${REMOTE_IP_REAL:-'10.0.2.15'} # real interface ip from remote perspective
REMOTE_PORT=${REMOTE_PORT:-2201}

remote() {
    ssh -t -q -p $REMOTE_PORT $REMOTE_USER@$REMOTE_IP "export REMOTE_PROXY_PORT=$REMOTE_PROXY_PORT ; export PROXY_PORT=$LOCAL_PROXY_PORT ; $1" || echo "Remote command return error"
}
singleton_bg() {
    if [ $(ps aux | grep -- "$1" | wc -l) == 1 ] ; then
        $1 &
    fi
}
remote_dev_stack() {
    remote "cd $PROJECT_BASE && $REMOTE_DEV_STACK_BIN $@"
}


##########
##########

if [ "$1" ] && [ "$1" == "machine" ]; then
  if [ $REMOTE_SYSTEM == "qemu" ]; then
    if [ "$2" ] && [ "$2" == "up" ]; then
      if [ "$(ps aux | grep 'dev_stack=machine_qemu' | wc -l)" = "2" ]; then
        echo "Machine is already up"
        exit 0
      fi
      QEMU_OPTS="-nographic"
      if [ $STORAGE_DIRVER == "virtiofs" ]; then
        virtiofsd-rs --socket /tmp/dev-stack-qemu-virtiofs --shared-dir $CODE_SRC_ROOT_DIR --disable-xattr --sandbox none --no-announce-submounts &
        QEMU_OPTS="$QEMU_OPTS -chardev socket,id=char0,path=/tmp/dev-stack-qemu-virtiofs -device vhost-user-fs-pci,queue-size=1024,chardev=char0,tag=tag -object memory-backend-file,id=mem,size=${QEMU_RAM:-4G},mem-path=/dev/shm,share=on -numa node,memdev=mem"
      fi
      qemu-system-x86_64 -cpu host -smp ${QEMU_NPROC:-1} -m ${QEMU_RAM:-4G} -enable-kvm -device ahci,id=ahci -usb -device usb-tablet \
          -kernel "${QEMU_KERNEL:-/data/store/dev-machine/kernel}" -append "mitigations=off console=ttyS0 dev_stack=machine_qemu root=/dev/sda2 init=/init" \
          -drive id=disk0,file="${QEMU_HDA:-/data/store/dev-machine/sda.img}",if=none,format=raw -device ide-hd,drive=disk0,bus=ahci.0 \
          -drive id=disk1,file="${QEMU_HDA_1:-/data/store/dev-machine/sdb.img}",if=none,format=raw -device ide-hd,drive=disk1,bus=ahci.1 \
          -net user,hostfwd=tcp::$REMOTE_PORT-:22 -net nic,model=virtio-net-pci $QEMU_OPTS
    elif [ "$2" ] && [ "$2" == "down" ]; then
      remote "poweroff"
    fi
  else
    echo "Unknown REMOTE_SYSTEM"
    exit 1
  fi
  exit 0
elif [ "$1" ] && [ "$1" == "ssh" ]; then
  CHANGE_CWD=$PWD ssh -p $REMOTE_PORT $REMOTE_USER@$REMOTE_IP -o SendEnv=CHANGE_CWD
  exit 0
elif [ "$1" ] && [ "$1" == "forward" ]; then
  if [ "$4" ]; then
      echo "Forwarding local port $2 to remote IP $3:$4"
      ssh -N -L 127.0.0.1:$2:$3:$4 -p $REMOTE_PORT $REMOTE_USER@$REMOTE_IP
  else
      echo "Usage: $1 LOCAL_PORT REMOTE_IP REMOTE_PORT"
  fi
  exit 0
elif [ "$1" ] && [ "$1" == "publish" ]; then
  if [ "$2" ]; then
      remotePort=${3:-80}
      localPort=${4:-8080}
      echo "Forwarding 0.0.0.0:$localPort to remote $2:$remotePort"
      ssh -N -L 0.0.0.0:$localPort:$2:$remotePort -p $REMOTE_PORT $REMOTE_USER@$REMOTE_IP
  else
      echo "Usage: $1 REMOTE_IP [REMOTE_PORT=80] [LOCAL_PORT=8080]"
  fi
  exit 0
elif [ "$1" ] && [ "$1" == "x11" ]; then
  echo 'Need to match remote hostname and few mounts and environment variables, eg:'
  echo 'Hostname: dev'
  echo 'Mounts: /tmp/.X11-unix/:/tmp/.X11-unix/:ro and /home/code/.Xauthority:/tmp/.Xauthority:ro'
  echo 'Env: DISPLAY=:10 and XAUTHORITY=/tmp/.Xauthority'
  echo ''
  ssh -t -X -p $REMOTE_PORT $REMOTE_USER@$REMOTE_IP 'DISPLAY_NUMBER=$(echo $DISPLAY | cut -d. -f1 | cut -d: -f2) && mkdir -p /tmp/.X11-unix/ && echo "Forwarding x11 session, slot: $DISPLAY_NUMBER, path: /tmp/.X11-unix/X${DISPLAY_NUMBER}, use DISPLAY=:$DISPLAY_NUMBER at target" && socat $(echo "UNIX-LISTEN:/tmp/.X11-unix/X${DISPLAY_NUMBER},fork TCP4:localhost:60${DISPLAY_NUMBER}")'
  exit 0
fi

if [[ ! -f $CONFIG_FILE ]]; then
  echo "No config file found, run init command or create it manually"
  exit 1
fi

{
  # Init deamons

  # Proxy docker jwilder forward from host
  singleton_bg "ssh -q -N -L 127.0.0.1:$LOCAL_PROXY_PORT:127.0.0.1:$REMOTE_PROXY_PORT -p $REMOTE_PORT $REMOTE_USER@$REMOTE_IP"

  # Ports forwarding from remote (NEEDS sshd_config: GatewayPorts clientspecified or yes)
  #singleton_bg "ssh -q -N -R $REMOTE_IP_REAL:9000:127.0.0.1:9000 -p $REMOTE_PORT $REMOTE_USER@$REMOTE_IP > /dev/null 2>& 1" # xdebug 2 9000 port forward
  singleton_bg "ssh -q -N -R $REMOTE_IP_REAL:9003:127.0.0.1:9003 -p $REMOTE_PORT $REMOTE_USER@$REMOTE_IP > /dev/null 2>& 1" # xdebug 3 9003 port forward
}

# Params
if [ "$1" ] && [ "$1" == "up" ]; then
    # Setup directory and shares
    if [ $STORAGE_DIRVER == "sshfs" ]; then
      HOST_USER=${HOST_USER:-'code'}
      HOST_IP=${HOST_IP:-'10.0.2.2'}
      HOST_PORT=${HOST_PORT:-22}
      remote "mkdir -p $PROJECT_BASE ; mount | grep -- '$PROJECT_BASE' > /dev/null 2> /dev/null || sshfs -o uid=${REMOTE_USER_UID},gid=${REMOTE_USER_GID},direct_io,kernel_cache,ciphers=aes128-gcm@openssh.com,allow_root,default_permissions,compression=no,cache=no,reconnect,disable_hardlink,max_conns=12 -p $HOST_PORT $HOST_USER@$HOST_IP:$PROJECT_BASE $PROJECT_BASE"
    fi
    # Run remote dev-stack
    remote_dev_stack "$*"
elif [ "$1" ] && [ "$1" == "down" ]; then
    remote_dev_stack "$*"
    if [ $STORAGE_DIRVER == "sshfs" ]; then
      remote "cd /tmp && fusermount3 -u $PROJECT_BASE"
    fi
elif [ "$1" ] && [ "$1" == "composerssh" ]; then
    eval $(ssh-agent)
    ssh-add -t 300 ${PRIVATE_KEY:-~/.ssh/id_rsa}
    ssh -A -p $REMOTE_PORT $REMOTE_USER@$REMOTE_IP "cd $PROJECT_BASE && export SSH_AUTH_SOCK_PATH=\$(echo \$SSH_AUTH_SOCK | sed s@/tmp/@/share/@) ; $REMOTE_DEV_STACK_BIN $*"
    eval $(ssh-agent -k)
elif [ "$1" ] && [ "$1" == "greenmail" ]; then
    for port in 3025 3110; do
      ssh -N -L 127.0.0.1:${port}:127.0.0.1:${port} -p $REMOTE_PORT $REMOTE_USER@$REMOTE_IP &
    done;
    remote_dev_stack "$*"
else
    # Run remote dev-stack
    remote_dev_stack "$*"
fi
