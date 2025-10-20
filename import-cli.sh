#!/usr/bin/env bash
#
# Copyright (C) 2022 Divyanshu-Modi <divyan.m05@gmail.com>
#
# based on <pig.priv@gmail.com> module importer
#
# SPDX-License-Identifier: Apache-2.0
#

R='\033[1;31m'
G='\033[1;32m'
W='\033[1;37m'

echo -e "$G                 ___   __                 _  __     "
echo -e "$G                /   | / /_____  ________ | |/ /     "
echo -e "$G               / /| |/ __/ __ \/ __  __ \|   /      "
echo -e "$G              / ___ / /_/ /_/ / / / / / /   |       "
echo -e "$G             /_/  |_\__/\____/_/ /_/ /_/_/|_|       "
echo -e "$G           __  ___ ___  ____  __  __ _    ______    "
echo -e "$G          /  |/  / __ \/ __ \/ / / / /   / ____/    "
echo -e "$G         / /|_/ / / / / / / / / / / /   / __/       "
echo -e "$G        / /  / / /_/ / /_/ / /_/ / /___/ /___       "
echo -e "$G       /_/  /_/\____/_____/\____/_____/_____/       "
echo -e "$G     ______  _______  ____  ____  ________________  "
echo -e "$G    /  _/  |/  / __ \/ __ \/ __ \/_  __/ ____/ __ \ "
echo -e "$G    / // /|_/ / /_/ / / / / /_/ / / / / __/ / /_/ / "
echo -e "$G  _/ // /  / / ____/ /_/ / _, _/ / / / /___/ _, _/  "
echo -e "$G /___/_/  /_/_/    \____/_/ |_| /_/ /_____/_/ |_|   "
echo -e "$W"

error() {
	clear
	echo -e ""
	echo -e "$R Error! $W" "$@"
	echo -e ""
	exit 1
}

success() {
	echo -e ""
	echo -e "$G" "$@" "$W"
	echo -e ""
}

# Commonised Importer
importer() {
	DIR=$1
	REPO=$2
	TAG=$3
	MSG=$4

	if [[ -d $DIR ]]; then
		error "$DIR directory is already present."
	fi

	git subtree add --prefix="$DIR" "$REPO" "$TAG" -m "$MSG"
	git commit --amend --no-edit
}

indicatemodir() {
	br="redwood-u-oss"
	case $num in
		1)
			mod=audio-kernel
			mod_url=vendor_opensource_audio_kernel
			prefix=audio
			;;
		2)
			mod=camera-kernel
			mod_url=vendor_opensource_camera_kernel
			prefix=camera
			;;
		3)
			mod=dataipa
			mod_url=vendor_opensource_dataipa_driver
			prefix=$mod
			;;
		4)
			mod=display-drivers
			mod_url=vendor_opensource_display_drivers
			prefix=display
			;;
		5)
			mod=video-driver
			mod_url=vendor_opensource_video_drivers
			prefix=video
			;;
		6)
			mod=touch-kernel
			mod_url=vendor_opensource_touch_drivers
			prefix=touch
			;;
		7)
			mod=vibrator
			mod_url=android_driver_awinic_vibrator
			prefix=vibrator
			br="staging-v2"
			;;
	esac
	msg1=$(echo '`DUMMY_TAG`' | sed s/DUMMY_TAG/$br/g)

	importer "techpack/$prefix"  https://github.com/atomx-sm8350/"$mod_url" $br "techpack: $mod: Import from $msg1"
}

for arg in "$@"; do
	case "${arg}" in
		"--module="*)
			MODULE=${arg#*=}
			MODULE=${MODULE,,}
			case $MODULE in
				audio)
					num=1
					;;
				camera)
					num=2
					;;
				dataipa)
					num=3
					;;
				display)
					num=4
					;;
				video)
					num=5
					;;
				touch)
					num=6
					;;
				haptic)
					num=7
					;;
				*)
					error 'device not supported'
					;;
			esac
			;;
	esac
done

indicatemodir