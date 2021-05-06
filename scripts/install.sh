#!/bin/sh

# check for root access
SUDO=
if [ "$(id -u)" -ne 0 ]; then
    SUDO=$(command -v sudo 2> /dev/null)

    if [ ! -x "$SUDO" ]; then
        echo "Error: Run this script as root"
        exit 1
    fi
fi

set -e
ARCH=$(uname -m)
BASE_URL=https://repo.nordvpn.com/
KEY_PATH=/gpg/nordvpn_public.asc
REPO_PATH_DEB=/deb/nordvpn/debian
RELEASE="stable main"

# Parse command line arguments. Available arguments are:
# -n                Non-interactive mode. With this flag present, 'assume yes' or 
#                   'non-interactive' flags will be passed when installing packages.
# -b <url>          The base URL of the public key and repository locations.
# -k <path>         Path to the public key for the repository.
# -d <path|file>    Repository location for debian packages.
# -r <version>      Debian package version to use.
# -v <version>      NordVPN version to install.
while getopts 'nb:k:d:r:v:' opt
do
    case $opt in
        n) ASSUME_YES=true ;;
        b) BASE_URL=$OPTARG ;;
        k) KEY_PATH=$OPTARG ;;
        d) REPO_PATH_DEB=$OPTARG ;;
        r) RELEASE=$OPTARG ;;
        v) VERSION=$OPTARG ;;
        *) ;;
    esac
done

# Construct the paths to the package repository and its key
PUB_KEY=${BASE_URL}${KEY_PATH}
REPO_URL_DEB=${BASE_URL}${REPO_PATH_DEB}

check_cmd() {
    command -v "$1" 2> /dev/null
}

get_install_opts_for_apt() {
    flags=$(get_install_opts_for "apt")
    RETVAL="$flags"
}

get_install_opts_for() {
    if $ASSUME_YES; then
        case "$1" in
            zypper)
                echo " -n";;
            *)
                echo " -y";;
        esac
    fi
    echo ""
}

install_apt() {
    if check_cmd apt-get; then
        get_install_opts_for_apt
        install_opts="$RETVAL"
        # Ensure apt is set up to work with https sources
        $SUDO apt-get $install_opts update
        $SUDO apt-get $install_opts install apt-transport-https

        # Add the repository key with either wget or curl
        if check_cmd wget; then
            wget -qO - "${PUB_KEY}" | $SUDO tee /etc/apt/trusted.gpg.d/nordvpn_public.asc > /dev/null
        elif check_cmd curl; then
            curl -s "${PUB_KEY}" | $SUDO tee /etc/apt/trusted.gpg.d/nordvpn_public.asc > /dev/null
        else
            echo "Couldn't find wget or curl - one of them is needed to proceed with the installation"
            exit 1
        fi

        echo "deb ${REPO_URL_DEB} ${RELEASE}" | $SUDO tee /etc/apt/sources.list.d/nordvpn.list
        $SUDO apt-get $install_opts update
        $SUDO apt-get $install_opts install nordvpn=${VERSION}
        _post_install_cleanup
        exit
    fi
}

_post_install_cleanup() {
    $SUDO apt-get remove -qq nordvpn-release
    $SUDO apt-get autoremove -qq
    $SUDO apt-get autoclean -qq
    $SUDO rm -rf \
        /tmp/* \
        /var/cache/apt/archives/* \
        /var/lib/apt-lists/* \
        /var/tmp/*
    $SUDO mkdir -p /run/nordvpn
}

install_apt