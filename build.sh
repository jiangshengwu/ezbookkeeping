#!/usr/bin/env sh

TYPE=""
RELEASE=${RELEASE_BUILD:-"0"};
VERSION=""
COMMIT_HASH=""
BUILD_UNIXTIME=""

echo_red() {
    printf "\033[31m$1\033[0m\n"
}

check_dependency() {
    for cmd in $1
    do
        which "$cmd" > /dev/null

        if [ $? != 0 ]; then
            echo_red "Error: \"$cmd\" is required."
            exit 127
        fi
    done
}

show_help() {
    cat <<-EOF
ezBookkeeping build script

Usage:
    build.sh type [options]

Types:
    backend             Build backend binary file
    frontend            Build frontend files
    docker              Build docker image

Options:
    -r, --release       Build release (The script will use environment variable "RELEASE_BUILD" to detect whether this is release building by default)
    -h, --help          Show help
EOF
}

parse_args() {
    if [ "$1" == "backend" ] || [ "$1" == "frontend" ] || [ "$1" == "docker" ]; then
        TYPE="$1"
        shift 1
    fi

    while [ ${#} -gt 0 ]; do
        case "${1}" in
            --release | -r)
                RELEASE="1"
                ;;
            --help | -h)
                show_help
                exit 0
                ;;
            *)
                echo_red "Invalid argument: $1"
                show_help
                exit 2
                ;;
        esac

        shift 1
    done
}

check_type_dependencies() {
    if [ "$TYPE" == "" ]; then
        echo_red "No specified type"
        show_help
        exit 2
    fi

    check_dependency "git"

    if [ "$TYPE" == "backend" ]; then
        check_dependency "go"
    elif [ "$TYPE" == "frontend" ]; then
        check_dependency "node npm"
    elif [ "$TYPE" == "docker" ]; then
        check_dependency "docker"
    fi
}

set_build_parameters() {
    VERSION="`grep '"version": ' package.json | awk -F ':' '{print $2}' | tr -d ' ' | tr -d ',' | tr -d '"'`"
    COMMIT_HASH="$(git rev-parse --short HEAD)"
    BUILD_UNIXTIME="$(date '+%s')"
}

build_backend() {
    local extra_arguments="-X github.com/mayswind/ezbookkeeping/pkg/version.Version=$VERSION"
    extra_arguments="$extra_arguments -X github.com/mayswind/ezbookkeeping/pkg/version.CommitHash=$COMMIT_HASH"

    if [ "$RELEASE" == "0" ]; then
        extra_arguments="$extra_arguments -X github.com/mayswind/ezbookkeeping/pkg/version.BuildUnixTime=$BUILD_UNIXTIME"
    fi

    echo "Building backend binary file..."

    CGO_ENABLED=1 go build -a -v -trimpath -ldflags "-w -s -linkmode external -extldflags '-static' $extra_arguments" -o ezbookkeeping ezbookkeeping.go
    chmod +x ezbookkeeping
}

build_frontend() {
    local build_arguments="--";

    if [ "$RELEASE" == "0" ]; then
        build_arguments="$build_arguments --buildUnixTime=$BUILD_UNIXTIME"
    fi

    echo "Pulling frontend dependencies..."
    npm install

    echo "Building frontend files..."
    npm run build $build_arguments
}

build_docker() {
    local docker_tag="$VERSION"

    if [ "$RELEASE" == "0" ]; then
        docker_tag="SNAPSHOT-$(date '+%Y%m%d')";
    fi

    echo "Building docker image \"ezbookkeeping:$docker_tag\"..."

    docker build . -t ezbookkeeping:$docker_tag
}

main() {
    if [ -z "$1" ]; then
        show_help
        exit 0
    fi

    parse_args "$@"
    check_type_dependencies "$TYPE"
    set_build_parameters

    if [ "$TYPE" == "backend" ]; then
        build_backend
    elif [ "$TYPE" == "frontend" ]; then
        build_frontend
    elif [ "$TYPE" == "docker" ]; then
        build_docker
    fi
}

main "$@"
