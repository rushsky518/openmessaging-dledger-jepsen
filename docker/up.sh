#!/usr/bin/env bash

# Licensed to the Apache Software Foundation (ASF) under one or more
# contributor license agreements.  See the NOTICE file distributed with
# this work for additional information regarding copyright ownership.
# The ASF licenses this file to You under the Apache License, Version 2.0
# (the "License"); you may not use this file except in compliance with
# the License.  You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# "To provide additional docker-compose args, set the COMPOSE var. Ex:
# COMPOSE="-f FILE_PATH_HERE"

set -e # exit on an error

ERROR(){
    /bin/echo -e "\e[101m\e[97m[ERROR]\e[49m\e[39m $@"
}

WARNING(){
    /bin/echo -e "\e[101m\e[97m[WARNING]\e[49m\e[39m $@"
}

INFO(){
    /bin/echo -e "\e[104m\e[97m[INFO]\e[49m\e[39m $@"
}

exists() {
    type $1 > /dev/null 2>&1
}

POSITIONAL=()
while [[ $# -gt 0 ]]
do
    key="$1"

    case $key in
        --help)
            HELP=1
            shift # past argument
            ;;
        --init-only)
            INIT_ONLY=1
            shift # past argument
            ;;
        --dev)
            if [ ! "$JEPSEN_ROOT" ]; then
                export JEPSEN_ROOT=$(cd ../ && pwd)
                INFO "JEPSEN_ROOT is not set, defaulting to: $JEPSEN_ROOT"
            fi
            INFO "Running docker-compose with dev config"
            DEV="-f docker-compose.dev.yml"
            shift # past argument
            ;;
        --compose)
            COMPOSE="-f $2"
            shift # past argument
            shift # past value
            ;;
        -d|--daemon)
            INFO "Running docker-compose as daemon"
            RUN_AS_DAEMON=1
            shift # past argument
            ;;
        *)
            POSITIONAL+=("$1")
            ERROR "unknown option $1"
            shift # past argument
            ;;
    esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [ "$HELP" ]; then
    echo "Usage: $0 [OPTION]"
    echo "  --help                                                Display this message"
    echo "  --init-only                                           Initializes ssh-keys, but does not call docker-compose"
    echo "  --daemon                                              Runs docker-compose in the background"
    echo "  --dev                                                 Mounts dir at host's JEPSEN_ROOT to /jepsen on jepsen-control container, syncing files for development"
    echo "  --compose PATH                                        Path to an additional docker-compose yml config."
    echo "To provide multiple additional docker-compose args, set the COMPOSE var directly, with the -f flag. Ex: COMPOSE=\"-f FILE_PATH_HERE -f ANOTHER_PATH\" ./up.sh --dev"
    exit 0
fi

exists ssh-keygen || { ERROR "Please install ssh-keygen (apt-get install openssh-client)"; exit 1; }
exists perl || { ERROR "Please install perl (apt-get install perl)"; exit 1; }

# Generate SSH keys for the control node
if [ ! -f ./secret/node.env ]; then
    INFO "Generating key pair"
    ssh-keygen -t rsa -N "" -f ./secret/id_rsa

    INFO "Generating ./secret/control.env"
    echo "# generated by jepsen/docker/up.sh, parsed by jepsen/docker/control/bashrc" > ./secret/control.env
    echo "# NOTE: \\n is expressed as ↩" >> ./secret/control.env
    echo SSH_PRIVATE_KEY="$(cat ./secret/id_rsa | perl -p -e "s/\n/↩/g")" >> ./secret/control.env
    echo SSH_PUBLIC_KEY=$(cat ./secret/id_rsa.pub) >> ./secret/control.env

    INFO "Generating ./secret/node.env"
    echo "# generated by jepsen/docker/up.sh, parsed by the \"tutum/debian\" docker image entrypoint script" > ./secret/node.env
    echo ROOT_PASS=root >> ./secret/node.env
    echo AUTHORIZED_KEYS=$(cat ./secret/id_rsa.pub) >> ./secret/node.env
else
    INFO "No need to generate key pair"
fi

# Make sure folders referenced in control Dockerfile exist and don't contain leftover files
rm -rf ./control/jepsen
mkdir -p ./control/jepsen/jepsen
# Copy the jepsen directory if we're not mounting the JEPSEN_ROOT
if [ ! "$DEV" ]; then
    # Dockerfile does not allow `ADD ..`. So we need to copy it here in setup.
    INFO "Copying .. to control/jepsen"
    (
        (cd ..; tar --exclude=./docker --exclude=./.git --exclude-ignore=.gitignore -cf - .)  | tar Cxf ./control/jepsen -
    )
fi

if [ "$INIT_ONLY" ]; then
    exit 0
fi

exists docker || { ERROR "Please install docker (https://docs.docker.com/engine/installation/)"; exit 1; }
exists docker-compose || { ERROR "Please install docker-compose (https://docs.docker.com/compose/install/)"; exit 1; }

INFO "Running \`docker-compose build\`"
docker-compose -f docker-compose.yml $COMPOSE $DEV build

INFO "Running \`docker-compose up\`"
if [ "$RUN_AS_DAEMON" ]; then
    docker-compose -f docker-compose.yml $COMPOSE $DEV up -d
    INFO "All containers started, run \`docker ps\` to view"
    exit 0
else
    INFO "Please run \`docker exec -it jepsen-control bash\` in another terminal to proceed"
    docker-compose -f docker-compose.yml $COMPOSE $DEV up
fi