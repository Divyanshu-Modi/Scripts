#!/bin/bash

#########################    CONFIGURATION    ##############################

# User details
KBUILD_USER="$USER"
KBUILD_HOST=$(uname -n)
CORES=$(nproc)
############################################################################

########################   DIRECTORY PATHS   ###############################

# Kernel Directory
KERNEL_DIR=$(pwd)

# Propriatary Directory (default paths may not work!)
PRO_PATH="$KERNEL_DIR/.."

# Toolchain Directory
TLDR="$PRO_PATH/toolchain"
PYTHON3=$(which python3)

# Anykernel Directories
AK3_DIR="$PRO_PATH/AnyKernel3"
AKVDR="$AK3_DIR/modules/vendor/lib/modules"

# device tree blob install path
DTB_PATH="${KERNEL_DIR}/work/dtbs/vendor/qcom"

############################################################################

###############################   COLORS   #################################

R='\033[1;31m'
G='\033[1;32m'
B='\033[1;34m'
W='\033[1;37m'

############################################################################

################################   MISC   ##################################

# functions
error()
{
	echo -e ""
	echo -e "$R ${FUNCNAME[0]}: $W" "$@"
	echo -e ""
	exit 1
}

inform()
{
	echo -e ""
	echo -e "$B ${FUNCNAME[1]}: $W" "$@" "$G"
	echo -e ""
}

success()
{
	inform $@
	exit 0
}

amake()
{
	if [[ -z $COMPILER || -z $COMPILER32 ]]; then
		COMPILER=clang
		COMPILER32=clang
		compiler_setup
	fi

	make "${MAKE_ARGS[@]}" "$@"
}

usage()
{
	inform " ./AtomX.sh <arg>
		--compiler   Sets the compiler to be used.
		--compiler32 Sets the 32bit compiler to be used,
					 (defaults to clang).
		--device     Sets the device for kernel build.
		--clean      Clean up build directory before running build,
					 (default behaviour is incremental).
		--dtbs       Builds dtbs, dtbo & dtbo.img.
		--dtb_zip    Builds flashable zip with dtbs, dtbo.
		--obj        Builds specified objects.
		--regen      Regenerates defconfig (savedefconfig).
		--log        Builds logs saved to log.txt in current dir.
		--silence    Silence shell output of Kbuild".
	exit 2
}

############################################################################

compiler_setup()
{
	############################  COMPILER SETUP  ##############################
	# default to clang
	CC='clang'
	C_PATH="$TLDR/$CC"

	if [[ $COMPILER == gcc ]]; then
		CC='aarch64-elf-gcc'
		C_PATH="$TLDR/gcc-arm64"
	fi

	LLVM_PATH="$C_PATH/bin"
	C_NAME=$("$LLVM_PATH"/$CC --version | head -n 1 | perl -pe 's/\(http.*?\)//gs')
	C_NAME_32="$C_NAME"
	MAKE_ARGS+=("CROSS_COMPILE_COMPAT=arm-linux-gnueabi-")

	if [[ "$COMPILER32" == "gcc" ]]; then
		MAKE_ARGS=("CC_COMPAT=$TLDR/gcc-arm/bin/arm-eabi-gcc"
				   "CROSS_COMPILE_COMPAT=$TLDR/gcc-arm/bin/arm-eabi-")
		C_NAME_32=$($(echo "${MAKE_ARGS[0]}" | cut -f2 -d"=") --version | head -n 1)
	fi

	MAKE_ARGS+=("O=work"
		"ARCH=arm64"
		"LLVM=1"
		"LLVM_IAS=1"
		"-j"$CORES""
		"HOSTLD=ld.lld" "CC=$CC"
		"PATH=$C_PATH/bin:$PATH"
		"INSTALL_HDR_PATH="headers""
		"KBUILD_BUILD_USER=$KBUILD_USER"
		"KBUILD_BUILD_HOST=$KBUILD_HOST"
		"CROSS_COMPILE=aarch64-linux-gnu-"
		"LD_LIBRARY_PATH=$C_PATH/lib:$LD_LIBRARY_PATH"
		"$(head -1 build.config.common)")
	############################################################################
}

config_generator()
{
	#########################  .config GENERATOR  ############################
	if [[ -z $CODENAME ]]; then
		error 'Codename not present connot proceed'
	fi

	DFCF="${CODENAME}-${SUFFIX}_defconfig"
	if [[ ! -z $BASE ]]; then
		DFCF="${BASE}-${SUFFIX}_defconfig"
	fi

	if [[ ! -f arch/arm64/configs/vendor/$DFCF ]]; then
		# cleanup work dir as no builds
		rm -rf work

		inform "Generating defconfig"

		export "${MAKE_ARGS[@]}" "TARGET_BUILD_VARIANT=user"

		bash scripts/gki/generate_defconfig.sh "$DFCF"
		amake vendor/$DFCF vendor/lahaina_QGKI.config savedefconfig
		rm -rf arch/arm64/configs/vendor/$DFCF
		mv work/defconfig arch/arm64/configs/vendor/$DFCF

		# cleanup work dir as no builds
		rm -rf work
	fi
	inform "Generating .config"

	# Make .config
	amake "vendor/$DFCF"
	if [[ ! -z $BASE ]]; then
		amake "vendor/$DFCF" "vendor/${CODENAME}-fragment.config"
	fi

	############################################################################
}

config_regenerator()
{
	########################  DEFCONFIG REGENERATOR  ###########################
	if [[ -z $CODENAME ]]; then
		error 'Codename not present connot proceed'
	fi

	MAKE_ARGS+=("-s")
	DFCF="${CODENAME}-${SUFFIX}_defconfig"
	if [[ ! -z $BASE ]]; then
		DFCF="${BASE}-${SUFFIX}_defconfig"
	fi
	amake "vendor/$DFCF" savedefconfig

	cat work/defconfig > arch/arm64/configs/vendor/"$DFCF"

	success "Regeneration completed"
	############################################################################
}

obj_builder()
{
	##############################  OBJ BUILD  #################################
	if [[ -z $OBJ ]]; then
		error "obj not defined"
	fi
	if [[ ! -d work/ ]]; then
		config_generator
	fi

	inform "Building $OBJ"
	amake olddefconfig "$OBJ"
	success "built $OBJ"
	############################################################################
}

emod_builder()
{
	##############################  EMOD BUILD  #################################
	if [[ -z $EMOD_PATH ]]; then
		error "obj not defined"
	fi
	if [[ ! -d work/ ]]; then
		error "External modules not possible without full kernel build"
	fi

	MAKE_ARGS+=("olddefconfig"
				"-C $KERNEL_DIR" 
				"M=$EMOD_PATH"
				"MODNAME=$EMOD_NAME"
				"$EMOD_ROOT=$EMOD_PATH")

	if [[ $BUILD == "clean" ]]; then
		inform "Cleaning $EMOD_PATH"
		MAKE_ARGS+=("clean")
	fi

	inform "Building $EMOD_PATH"
	amake
	success "EMOD: $EMOD_NAME built successfully"
	############################################################################
}

dtb_build()
{
	##############################  DTB BUILD  #################################
	if [[ ! -d work/ ]]; then
		config_generator
	fi

	MAKE_ARGS+=("olddefconfig"
				"dtbs"
				"INSTALL_DTBS_PATH="dtbs""
				"DTB_TYPES=${PLATFORM}-overlays-"
				"dtbs_install")

	amake
	${PYTHON3} ${TLDR}/mkdtboimg.py create ${DTB_PATH}/dtbo.img --page_size=4096 ${DTB_PATH}/*.dtbo

	inform "dtbs and dtbo.img built for board: ${PLATFORM}"
	############################################################################
}

dtb_zip()
{
	##############################  DTB BUILD  #################################
	dtb_build

	if [[ ! -d $AK3_DIR ]]; then
		error 'Anykernel not present cannot zip'
	fi
	if [[ ! -d "$KERNEL_DIR/out" ]]; then
		mkdir "$KERNEL_DIR"/out
	fi

	LAST_HASH=$(git rev-parse --short=8 HEAD)
	VERSION=$(scripts/config --file work/.config -s LOCALVERSION)

	# Making sure everything is ok before making zip
	cd "$AK3_DIR" || exit
	make clean

	cp $DTB_PATH/${PLATFORM}.dtb "$AK3_DIR"/dtb
	cp $DTB_PATH/dtbo.img "$AK3_DIR"/dtbo.img

	MAKE_ARGS=("CODENAME=$CODENAME"
				"VERSION="
				"CUSTOM=dtb-$LAST_HASH")

	make zip ${MAKE_ARGS[@]}

	cp ./*-signed.zip "$KERNEL_DIR"/out

	make clean

	cd "$KERNEL_DIR" || exit

	success "dtbs zip built"
	############################################################################
}

kernel_builder()
{
	##################################  BUILD  #################################
	# Build Start
	BUILD_START=$(date +"%s")

	if [[ "$BUILD" == "clean" ]]; then
		inform "Cleaning work directory, please wait...."
		amake -s clean mrproper distclean
	fi
	if [[ "$BUILD" == "incremental" ]]; then
		amake olddefconfig
	else
		config_generator
	fi

	MOD_NAME="$(amake kernelrelease -s)"
	KERNEL_VERSION=$(echo "$MOD_NAME" | cut -c -7)
	MODULES=$(scripts/config --file work/.config -s MODULES)

	inform "
	*************Build Triggered*************
	Date: $(date +"%Y-%m-%d %H:%M")
	Linux Version: $KERNEL_VERSION
	Kernel Name: $MOD_NAME
	Device: $DEVICENAME
	Board: $PLATFORM
	Codename: $CODENAME
	Compiler: $C_NAME
	Compiler_32: $C_NAME_32
	"

	# Compile
	amake
	amake INSTALL_DTBS_PATH="dtbs" DTB_TYPES="${PLATFORM}-overlays-" dtbs_install
	${PYTHON3} ${TLDR}/mkdtboimg.py create ${DTB_PATH}/dtbo.img --page_size=4096 ${DTB_PATH}/*.dtbo
	if [[ $MODULES == "y" ]]; then
		amake 'modules_install' INSTALL_MOD_STRIP=1 INSTALL_MOD_PATH="modules"
	fi

	zipper

	# Build End
	DIFF=$(("$(date +"%s")" - "$BUILD_START"))

	success "build completed in $((DIFF / 60)).$((DIFF % 60)) mins"
	############################################################################
}

zipper()
{
	####################################  ZIP  #################################
	local TARGET="$(amake image_name -s)"

	if [[ ! -f $KERNEL_DIR/work/$TARGET ]]; then
		error 'Kernel image not found'
	fi
	if [[ ! -d $AK3_DIR ]]; then
		error 'Anykernel not present cannot zip'
	fi
	if [[ ! -d "$KERNEL_DIR/out" ]]; then
		mkdir "$KERNEL_DIR"/out
	fi

	# Making sure everything is ok before making zip
	cd "$AK3_DIR" || exit
	make clean
	cd "$KERNEL_DIR" || exit

	cp "$KERNEL_DIR"/work/"$TARGET" "$AK3_DIR"
	cp $DTB_PATH/${PLATFORM}.dtb "$AK3_DIR"/dtb
	cp $DTB_PATH/dtbo.img "$AK3_DIR"/dtbo.img

	if [[ $MODULES == "y" ]]; then
		MOD_PATH="work/modules/lib/modules/$MOD_NAME"
		sed -i 's/\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)/\/vendor\/lib\/modules\/\2/g' "$MOD_PATH"/modules.dep
		sed -i 's/.*\///g' "$MOD_PATH"/modules.order
		cp  $(find "$MOD_PATH" -name '*.ko') "$AKVDR"/
		cp "$MOD_PATH"/modules.{alias,dep,softdep} "$AKVDR"/
		cp "$MOD_PATH"/modules.order "$AKVDR"/modules.load
	fi

	LAST_COMMIT=$(git show -s --format=%s)
	LAST_HASH=$(git rev-parse --short=8 HEAD)
	VERSION=$(scripts/config --file work/.config -s LOCALVERSION)
	LTO=$(scripts/config --file work/.config -s LTO_CLANG)

	cd "$AK3_DIR" || exit

	MAKE_ARGS+=("CODENAME=$CODENAME"
				"VERSION=")

	if [[ $LTO == "y" ]]; then
		MAKE_ARGS+=("CUSTOM=$LAST_HASH-lto")
	else
		MAKE_ARGS+=("CUSTOM=$LAST_HASH")
	fi

	make zip ${MAKE_ARGS[@]}

	cp ./*-signed.zip "$KERNEL_DIR"/out

	make clean

	cd "$KERNEL_DIR" || exit

	inform "
	*************AtomX-Kernel*************
	Linux Version: $KERNEL_VERSION
	Kernel Name: $MOD_NAME
	Device: $DEVICENAME
	Platform: $PLATFORM
	Codename: $CODENAME
	Compiler: $C_NAME
	Compiler_32: $C_NAME_32
	Build Date: $(date +"%Y-%m-%d %H:%M")

	-----------last commit details-----------
	Last: $LAST_COMMIT ($LAST_HASH)
	"
	############################################################################
}

###############################  COMMAND_MODE  ##############################
if [[ -z $@ ]]; then
	usage
fi
for arg in "$@"; do
	case "${arg}" in
		"--clean")
			BUILD='clean'
			;;
		"--incremental")
			BUILD='incremental'
			;;
		# "--log")
		# 	MAKE_ARGS+=("2>&1 | tee log.txt")
		# 	;;
		"--silence")
			MAKE_ARGS+=("-s")
			;;
	esac
done
for arg in "$@"; do
	case "${arg}" in
		"--clean" | "--incremental" | "--log" | "--silence")
			;;
		"--compiler="*)
			COMPILER=${arg#*=}
			COMPILER=${COMPILER,,}
			;&
		"--compiler32="*)
			COMPILER32=${arg#*=}
			COMPILER32=${COMPILER32,,}
			compiler_setup
			;;
		"--device="*)
			CODENAME=${arg#*=}
			case $CODENAME in
				lisa)
					DEVICENAME='Xiaomi 11 lite 5G NE'
					CODENAME='lisa'
					BASE='xiaomi'
					SUFFIX='qgki'
					PLATFORM='yupik'
					;;
				redwood)
					DEVICENAME='Poco X5 Pro 5G'
					CODENAME='redwood'
					BASE='xiaomi'
					SUFFIX='qgki'
					PLATFORM='yupik'
					;;
				lahaina)
					DEVICENAME='Lahaina QGKI'
					CODENAME='lahaina'
					SUFFIX='qgki'
					PLATFORM='yupik'
					;;
				*)
					error 'device not supported'
					;;
			esac
			;;
		"--dtb-zip")
			dtb_zip
			;&
		"--dtbs")
			dtb_build
			exit 0
			;;
		"--obj="*)
			OBJ=${arg#*=}
			obj_builder
			;;
		"--emod="*)
			EMOD_PATH=${arg#*=}
			if [ -z $EMOD_PATH ]; then
				read -rp "PATH: " EMOD_PATH
			fi
			read -rp "MODNAME: " EMOD_NAME
			read -rp "ROOT: " EMOD_ROOT
			emod_builder
			;;
		"--regen")
			config_regenerator
			;;
		*)
			usage
			;;
	esac
done
############################################################################

kernel_builder
