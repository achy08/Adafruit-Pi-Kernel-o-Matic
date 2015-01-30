#!/usr/bin/env bash

GIT_DIR="/rpi_linux"
MOD_DIR=`mktemp -d`
PKG_DIR=`mktemp -d`
TOOLS_DIR="/rpi_tools"
NUM_CPUS=`nproc`
GIT_REPO="https://github.com/raspberrypi/linux"
GIT_BRANCH=""

if [ -f /vagrant/saved_config ]; then
  COMPILE_CONFIG="/vagrant/saved_config"
else
  COMPILE_CONFIG="arch/arm/configs/bcmrpi_defconfig"
fi

function usage() {
  cat << EOF
usage: adabuild [options]
 This will build the Raspberry Pi Kernel.
 OPTIONS:
    -h        Show this message
    -r        The remote git repo to clone
              Default: $GIT_REPO
    -b        The git branch to use
              Default: Default git branch of repo
    -c        The config file to use when compiling
              Default: $COMPILE_CONFIG
EOF
}

function clone() {
  echo "**** CLONING GIT REPO ****"
  echo "REPO: ${GIT_REPO}"
  echo "BRANCH: ${GIT_BRANCH}"
  git clone --depth 1 --recursive $GIT_BRANCH ${GIT_REPO} $GIT_DIR
}

while getopts "hb:r:c:" opt; do
  case "$opt" in
  h)  usage
      exit 0
      ;;
  b)  GIT_BRANCH="--branch $OPTARG"
      ;;
  r)  GIT_REPO="$OPTARG"
      ;;
  c)  COMPILE_CONFIG="$OPTARG"
      ;;
  \?) usage
      exit 1
      ;;
  esac
done

echo -e "\n**** USING ${NUM_CPUS} AVAILABLE CORES ****\n"

if [ "$GIT_REPO" != "https://github.com/raspberrypi/linux" ]; then
  # use temp dir if we aren't using the default linux repo
  GIT_DIR=`mktemp -d`
  clone
fi

if [ ! -d $TOOLS_DIR ]; then
  echo "**** CLONING TOOL REPO ****"
  git clone --depth 1 https://github.com/raspberrypi/tools $TOOLS_DIR
fi

cd $TOOLS_DIR
git pull
CCPREFIX=${TOOLS_DIR}/arm-bcm2708/arm-bcm2708-linux-gnueabi/bin/arm-bcm2708-linux-gnueabi-

if [ ! -d $GIT_DIR ]; then
  clone
fi

cd $GIT_DIR
git pull
git submodule update --init
cp ${COMPILE_CONFIG} .config
cp .config /vagrant/saved_config

echo "**** COMPILING KERNEL ****"
ARCH=arm CROSS_COMPILE=${CCPREFIX} make menuconfig
ARCH=arm CROSS_COMPILE=${CCPREFIX} make -j${NUM_CPUS} -k
ARCH=arm CROSS_COMPILE=${CCPREFIX} INSTALL_MOD_PATH=${MOD_DIR} make -j${NUM_CPUS} modules_install

# confirm the control version
cp -r /kernel_builder/package/* $PKG_DIR
OLD_VERSION=`date +%Y%m%d`
read -e -p "Confirm the new version: " -i "${OLD_VERSION}-1" NEW_VERSION
sed -i $PKG_DIR/DEBIAN/control -e "s/^Version.*/Version: ${NEW_VERSION}/"

cp ${GIT_DIR}/arch/arm/boot/Image $PKG_DIR/boot/kernel.img
cp -r ${MOD_DIR}/lib ${PKG_DIR}

echo "**** BUILDING DEB PACKAGE ****"
fakeroot dpkg-deb -b $PKG_DIR /vagrant/raspberrypi-bootloader-custom_${NEW_VERSION}.deb

echo -e "\n**** DONE: /vagrant/raspberrypi-bootloader-custom_${NEW_VERSION}.deb ****\n"

echo -e "THE raspberrypi-bootloader-custom_${NEW_VERSION}.deb PACKAGE\nSHOULD NOW BE AVAILABLE IN THE KERNEL-O-MATIC FOLDER ON YOUR HOST MACHINE\n\n"
