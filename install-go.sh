#!/bin/bash

ENV_FILE="$HOME/environment-variables"
TMP='/tmp'
SDK_DIR="$HOME/software/sdk"
GOLANG_VERSION='1.20.2'
GOLANG_SDK="go$GOLANG_VERSION.linux-amd64.tar.gz"
GOLANG_SDK_URL="https://go.dev/dl/$GOLANG_SDK"

# make sure sdk directory exists
mkdir -p "$SDK_DIR"

# download golang and extract to sdk directory
pushd $TMP && { curl -O $GOLANG_SDK_URL ; popd || exit; }
tar -xzvf $TMP/$GOLANG_SDK -C "$SDK_DIR"

# use symlink to manage go install
pushd "$SDK_DIR" || exit
mv go go-$GOLANG_VERSION
ln -s go-$GOLANG_VERSION go
popd || exit

# setup environment variables
# we want this to output without expansion
# shellcheck disable=SC2016
echo '
GO_HOME=$HOME/software/sdk/go/bin
export PATH=$GO_HOME:$PATH
export PATH=$(go env GOPATH)/bin:$PATH
' >> "$ENV_FILE"
