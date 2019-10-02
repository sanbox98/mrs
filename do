#!/bin/bash -eu
export DJANGO_SETTINGS_MODULE=mrs.settings
export DB_ENGINE=django.db.backends.postgresql

# env.setup         Global environment variables and fs perms setup
env.setup() {
    export DJANGO_SETTINGS_MODULE=mrs.settings
    export DB_ENGINE=django.db.backends.postgresql
    test -n "${CI_COMMIT_SHA-}" || export CI_COMMIT_SHA=$(git rev-parse --short HEAD)
    export image=${image-betagouv/mrs:master}
    export instance=${instance-test}

    if ! test -f .env; then
        if ! env | grep ^DEBUG= ; then
            read -p    'Production config ? Leave empty, or type 1 for DEBUG config' DEBUG
        fi
    cat <<EOF > .env
ALLOWED_HOSTS=${ALLOWED_HOSTS-*}
DB_ENGINE=django.db.backends.postgresql
DB_NAME=${DB_NAME-mrs}
DB_PASSWORD=${DB_PASSWORD-}
DB_USER=${DB_USER-django}
DEBUG=${DEBUG-}
DEFAULT_FROM_EMAIL=
EMAIL_HOST=
EMAIL_PORT=
LIQUIDATION_EMAIL=
RESTIC_PASSWORD=notsecret
SECRET_KEY=notsecret
SENTRY_AUTH_TOKEN=
SENTRY_DSN=
SENTRY_ORG=sentry
SENTRY_PROJECT=
SENTRY_URL=
TEAM_EMAIL=
VIRTUAL_HOST=
VIRTUAL_PROTO=
EOF
    fi
    set -a && source .env
}

# db.reset          Drop and re-create the database
db.reset() {
    sudo systemctl start postgresql
    sudo -u postgres dropdb mrs || echo could not drop db
    sudo -u postgres createdb -E utf8 -O $USER mrs
}

# db.reload         Drop and re-create the database, load test data
db.reset() {
    db.reset && db.load
}

# db.load           Load test data
db.load() {
    mrs migrate --noinput
    djcli delete contenttypes.ContentType
    djcli delete auth.Group
    djcli delete mrsuser.User
    CI=1 mrs loaddata src/mrs/tests/data.json
}

# db.dump           Dump data from the database into test data.json
#                   This command is used to recreate the test dataset used in
#                   automated tests from the currently connected database.
db.dump() {
    CI=1 mrs mrsstat --refresh
    mrs dumpdata --indent=4 \
        $(grep model src/mrs/tests/data.json | sort -u | sed 's/.*model". "\([^"]*\)",*/\1/') \
        > src/mrs/tests/data.json
}

# runserver         DEBUG/development server on all interfaces port 8000
runserver() {
    django-admin runserver --traceback 0:8000
}


# clean.pyc         Find all __pycache__ and delete them recursively
clean.pyc() {
    if ! find . -type d -name __pycache__ | xargs rm -rf; then
        sudo chown -R $USER. .
        find . -type d -name __pycache__ | xargs rm -rf
    fi
}

# venv              Setup and activate a venv for a python executable
#                   Having venv=none makes this job a no-op.
venv() {
  if [ "${venv-}" != "none" ]; then
    python=${python-python3}
    venv=${path-.venv.${python-python3}}

    test -d $venv || virtualenv --python=$python $venv

    set +eux; echo activating $venv; source $venv/bin/activate; set -eux
  fi
}

# pip.install       Install project and runtime dependencies
pip.install() {
    pip install -U -e .
}

# pip.dev           Install project development dependencies
pip.dev() {
    pip.install
    pip install -r requirements-dev.txt
}

# py.test           Test executor, supports a $cov and $CODECOV env var.
py.test() {
    export WEBPACK_LOADER=webpack_mock
    export CI=true
    export DEBUG=true
    clean.pyc
    venv
    pip.install
    pip.dev

    if [ -n "${CODECOV_TOKEN-}" ]; then
        cov="${cov-src}"
    fi

    if [ -n "${cov-}" ]; then
        cov="--cov $cov"
    fi

    $(which py.test) -x -s -vvv --strict -r fEsxXw ${cov-} ${@-src}

    if [ -n "${CODECOV_TOKEN-}" ]; then
        codecov --token $CODECOV_TOKEN
    fi
}

# py.testrewrite    Rewrite the autogenerated test code at your own discretion
py.testrewrite() {
    FIXTURE_REWRITE=1 py.test
}

# py.qa             Flake8 python linter
py.qa() {
    flake8 \
        --show-source \
        --exclude migrations,settings \
        --max-complexity=8 \
        --ignore=E305,W503,N801 \
        src
}

# docker.build      Build the docker container image
docker.build() {
    docker build \
        --shm-size 512M \
        -t $image \
        --build-arg GIT_COMMIT=$CI_COMMIT_SHA \
        .
}

# docker.test       Run tests in docker containers
docker.test() {
    db.start
    docker run -t
        -v $(pwd):/app
        -w /app
        -e DB_HOST=$DB_HOST
        -e DB_USER=$USER
        -e rewrite=${rewrite-}
        --user root
        ${img-yourlabs/python} ./do py.test
}

# docker.testbuild  Build a docker container and test in it
docker.testbuild() {
    db.start
    docker.build
    docker.test
}

# docker.dump       Dump data into ./dump for remote backup and restore
docker.dump() {
    if test -d dump; then
        rm -rf dump.previous
        mv dump dump.previous || echo Could not move ./dump out of the way
    fi
    mkdir -p dump
    cp do dump

    getcommit="docker inspect --format='{{.Config.Env}}' betagouv/mrs:master | grep -o 'GIT_COMMIT=[a-z0-9]*'"
    if $getcommit; then
        export $($getcommit)
    fi

    image="$(docker inspect --format='{{.Config.Image}}' mrs-$instance || echo betagouv/mrs:master)"
    echo $image > dump/image

    echo Backing-up container logs before docker shoots them
    docker logs mrs-$instance &> ./log/docker.log || echo "Couldn't get logs from instance"

    if [ -d ./postgres/data ] && docker start mrs-$instance-postgres; then
        docker start mrs-$instance-postgres
        docker logs mrs-$instance-postgres >> ./log/postgres.log
        docker exec mrs-$instance-postgres pg_dumpall -U $POSTGRES_USER -c -f /dump/data.dump
    fi
    cp -a log dump
}

# docker.load       Load dumped data from ./dump
docker.load() {
    export image=$(<./dump/image)
    # backup current data dir by moving it away, in case of manual restore
    postgres_current=postgres/current
    sudo rm -rf $postgres_current
    docker stop mrs-$instance-postgres
    docker rm -f mrs-$instance || echo could not rm container mrs-$instance
    [ ! -d postgres/data ] || sudo mv postgres/data $postgres_current
    docker.db.start
    docker exec mrs-$instance-postgres psql -d mrs-$instance -U django -f /dump/data.dump
    sudo rm -rf $postgres_current
    docker.start
}

# docker.backup     Backup a dump remotely
docker.backup() {
    export RESTIC_REPOSITORY=./restic
    if [ -f ./.backup_password ]; then
        export RESTIC_PASSWORD_FILE=.backup_password
    fi

    mkdir -p mrsattachments

    restic backup dump mrsattachments --tag $GIT_COMMIT
    lftp -c "set ssl:check-hostname false;connect $FTP_HOST; mkdir -p mrs-$instance; mirror -Rv $(pwd)/restic mrs-$instance/restic"
    rm -rf $(pwd)/postgres/data/data.dump
}

# docker.dumpbackup Backup a dump remotely
docker.dumpbackup() {
    docker.dump
    docker.backup
}

# docker.network    Create a docker network
docker.network() {
    docker network inspect mrs-$instance \
    || docker network create --driver bridge mrs-$instance
}

# docker.db.start   Start a docker database instance
docker.db.start() {
    docker ps -a | grep mrs-$instance-postgres \
    || docker run \
        --detach \
        --name mrs-$instance-postgres \
        --volume $(pwd)/postgres/data:/var/lib/postgresql/data \
        --volume $(pwd)/postgres/run:/var/run/postgresql \
        --volume $(pwd)/dump:/dump \
        --env-file $(pwd)/.env \
        --restart always \
        --log-driver journald \
        --network mrs-$instance \
        postgres:10

    docker start mrs-$instance-postgres
    for i in {1..5}; do docker logs mrs-$instance-postgres 2>&1 | grep 'ready to accept connections' && break || sleep 1; done
    docker logs mrs-$instance-postgres
    for i in {1..5}; do test -S postgres/run/.s.PGSQL.5432 && break || sleep 1; done
}

# docker.db.stop    Stop the docker database instance
docker.db.stop() {
    docker stop mrs-$instance-postgres
}

# docker.db.reset   Destroy all db data and create a new one with test data.
#                   Note that it will not execute a data dump prior to wiping
#                   the data.
docker.db.reset() {
    docker.db.stop
    docker rm -f mrs-$instance-postgres
    docker.db.start
}

# docker.start      Start a docker instance
docker.start() {
    docker.network
    docker rm -f mrs-$instance || echo could not rm container
    docker.db.start
    sleep 5 # unfortunate fix for db not ready
    docker run \
        --rm \
        --name mrs-$instance-migrate \
        --volume $(pwd)/log:/app/log \
        --env-file $(pwd)/.env \
        --network mrs-$instance \
        $image \
        mrs migrate
    docker run \
        --name mrs-$instance \
        --restart unless-stopped \
        --log-driver journald \
        --network mrs-$instance \
        --volume $(pwd)/spooler:/app/spooler \
        --volume $(pwd)/media:/media \
        --volume $(pwd)/log:/app/log \
        --env-file $(pwd)/.env \
        ${*-$image}
    (! docker network inspect mailcatcher ) || docker network connect mailcatcher mrs-$instance
    docker logs mrs-$instance
}

# docker.runserver  Run a development server on port 8000 with docker
docker.start() {
    docker.start --publish=8000:8000 --volume $(pwd)/src:/app/src betagouv/mrs mrs runserver 0:8000
}

# docker.mount      Mount the current directory into /app for development
docker.mount() {
    docker.start --volume $(pwd):/app $image
}

# docker.stop       Stop docker instances
docker.stop() {
    (! docker ps | grep ^mrs-$instance\$) || docker stop mrs-$instance
    (! docker ps | grep ^mrs-$instance-postgres\$) || docker stop mrs-$instance-postgres
}

# docker.rm         Remove everything
docker.rm() {
    docker rm -f mrs-$instance-postgres || echo container mrs-$instance-postgres not removed
    docker rm -f mrs-$instance || echo container mrs-$instance not removed
    docker network rm mrs-$instance || echo network mrs-$instance not removed
}

# docker.reset      DELETE ALL DATA and start again
docker.reset() {
    if docker network inspect mrs-$instance; then
        docker network disconnect mrs-$instance mrs-$instance || echo could not disconnect instance
        docker network disconnect mrs-$instance mrs-$instance-postgres || echo could not disconnect postgres
        if docker ps -a | grep mrs-$instance-postgres; then
            docker rm -f mrs-$instance-postgres
        fi
        docker network rm mrs-$instance
    fi
    if docker ps -a | grep mrs-$instance\$; then
        docker rm -f mrs-$instance
    fi
    docker.start
}

# docker.ps         Show docker process
docker.ps() {
    docker ps -a | grep mrs-$instance
}

# docker.logs       Show docker process
docker.logs() {
    docker logs mrs-$instance-postgres
    docker logs mrs-$instance
}

# docker.shell      Shell on docker process
docker.shell() {
    docker exec -it mrs-$instance bash
}

# waituntil             Wait for a statement until 150 tries elapsed
waituntil() {
    set +x
    printf "$*"
    i=${i-150}
    success=false
    until [ $i = 0 ]; do
        i=$((i-1))
        printf "\e[31m.\e[0m"
        if $* &> ".waituntil.outerr"; then
            printf "\e[32mSUCCESS\e[0m:\n"
            success=true
            break
        else
            sleep 1
        fi
    done
    cat ".waituntil.outerr"
    if ! $success; then
        printf "\e[31mFAILED\e[0m:\n"
        exit 1
    fi
    set -x
}

if [ -z "${1-}" ]; then
    grep '^# ' $0
else
    fun=$1
    shift
    $fun $*
fi
