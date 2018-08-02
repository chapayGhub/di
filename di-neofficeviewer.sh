#!/bin/zsh -f
# Purpose: Download and install the latest NeoOffice Viewer app (free)
#
# From:	Timothy J. Luoma
# Mail:	luomat at gmail dot com
# Date:	2018-07-20

NAME="$0:t:r"

INSTALL_TO='/Applications/NeoOffice.app'

if [ -e "$HOME/.path" ]
then
	source "$HOME/.path"
else
	PATH='/usr/local/scripts:/usr/local/bin:/usr/bin:/usr/sbin:/sbin:/bin'
fi

function die
{
	echo "$NAME: $@"
	exit 1
}

UA="Mozilla/5.0 (Macintosh; Intel Mac OS X 10_13_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/11.1.2 Safari/605.1.15"

########################################################################################################################

URL1=$(curl -A "$UA" -sfL "https://www.neooffice.org/neojava/en/download.php" 2>&1 \
		| egrep 'href=".*NeoOffice-.*_Viewer-Intel.dmg' \
		| head -1 \
		| sed 's#.*mirrors.php#https://www.neooffice.org/neojava/en/mirrors.php#g ; s#">.*##g')

[[ "$URL1" == "" ]] && echo "$NAME: Failed to find value for \$URL1" && exit 1

SHORT_FILE=$(echo "$URL1:t" | sed 's#mirrors.php?file=##g')

[[ "$SHORT_FILE" == "" ]] && echo "$NAME: Failed to find value for \$SHORT_FILE" && exit 1

LATEST_VERSION=`echo "$SHORT_FILE:t:r" | tr -dc '[0-9]\.'`

[[ "$LATEST_VERSION" == "" ]] && echo "$NAME: Failed to find value for \$LATEST_VERSION" && exit 1

URL2="https://www.neooffice.org/neojava/en/mirrors.php?curl=${SHORT_FILE}&file=${SHORT_FILE}&mirror=0"

FILENAME="$HOME/Downloads/NeoOfficeViewer-$LATEST_VERSION.dmg"

	## Useful debugging info if something isn't working:
	# echo "
	# URL1: $URL1
	# URL2: $URL2
	# SHORT_FILE: $SHORT_FILE
	# LATEST_VERSION: $LATEST_VERSION
	# FILENAME: $FILENAME
	# "

########################################################################################################################

if [[ -e "$INSTALL_TO" ]]
then

	INSTALLED_VERSION=$(defaults read "${INSTALL_TO}/Contents/Info" CFBundleShortVersionString)

	autoload is-at-least

	is-at-least "$LATEST_VERSION" "$INSTALLED_VERSION"

	VERSION_COMPARE="$?"

	if [ "$VERSION_COMPARE" = "0" ]
	then
		echo "$NAME: Up To Date ($INSTALLED_VERSION)"
		exit 0
	fi

	echo "$NAME: Outdated: $INSTALLED_VERSION vs $LATEST_VERSION"

	FIRST_INSTALL='no'

else

	FIRST_INSTALL='yes'
fi

########################################################################################################################

if [[ -e "$FILENAME" ]]
then
		## The download servers do not support resuming a download, so if the FILENAME is already there, we'll try to use it
	echo "$NAME: $FILENAME already exists. Skipping download. If you want to force a re-download, delete it."
else

	echo "$NAME: Downloading \"$URL2\" to \"$FILENAME\":"

	curl --progress-bar  --location -A "$UA" --output "$FILENAME" "$URL2"

	EXIT="$?"

		## exit 22 means 'the file was already fully downloaded'
	[ "$EXIT" != "0" -a "$EXIT" != "22" ] && echo "$NAME: Download of \"$URL2\" failed (EXIT = $EXIT)" && exit 0

	[[ ! -e "$FILENAME" ]] && echo "$NAME: $FILENAME does not exist." && exit 0

	[[ ! -s "$FILENAME" ]] && echo "$NAME: $FILENAME is zero bytes." && rm -f "$FILENAME" && exit 0
fi

########################################################################################################################
##
## 2018-07-20:
## The mirroring system for downloads tends to want to give us an HTML page instead of an actual DMG
## So we test for file type. This _could_ break if they package their DMGs differently in the future
## but that seems unlikely.

TYPE=`file -b "$FILENAME"`

if [ "$TYPE" != "zlib compressed data" ]
then
	echo "$NAME: $FILENAME downloaded, but does not appear to be the right file type.
	Expected 'zlib compressed data' but received \"$TYPE\" instead."

	exit 1
fi

########################################################################################################################

MNTPNT=$(hdiutil attach -nobrowse -plist "$FILENAME" 2>/dev/null \
		| fgrep -A 1 '<key>mount-point</key>' \
		| tail -1 \
		| sed 's#</string>.*##g ; s#.*<string>##g')

if [[ "$MNTPNT" == "" ]]
then
	echo "$NAME: MNTPNT is empty"
	exit 1
fi

PKG=$(find "$MNTPNT" -iname \*.pkg -maxdepth 1 -print)

if [[ "$PKG" == "" ]]
then
	echo "$NAME: Failed to find a .pkg file in $MNTPNT"
	open "$MNTPNT"
	exit 1
fi

echo "$NAME: Preparing to install PKG: $PKG"


if (( $+commands[unpkg.py] ))
then
	# Get unpkg.py from https://github.com/tjluoma/unpkg/blob/master/unpkg.py

	if [[ -e "$INSTALL_TO" ]]
	then
		echo "$NAME: Moving old version to trash:"

		mv -vf "$INSTALL_TO" "$HOME/.Trash/$INSTALL_TO:t:r.${INSTALLED_VERSION}.app"
	fi

	echo "$NAME: running 'unpkg.py' on '$PKG':"

	UNPKG=`unpkg.py "$PKG" 2>&1`

	[[ "$UNPKG" == "" ]] && die "unpkg.py failed"

	EXTRACTED_TO=$(echo "$UNPKG" | egrep '^Extracted to ' | sed 's#Extracted to "##g ; s#".##g')

	[[ "$EXTRACTED_TO" == "" ]] && die "unpkg.py failed (EXTRACTED_TO empty)"

	echo "$NAME: Moving '$EXTRACTED_TO/$INSTALL_TO:t' to '$INSTALL_TO'."

	mv -vf "$EXTRACTED_TO/$INSTALL_TO:t" "$INSTALL_TO" || die 'move failed'

		# This should be an empty folder now
	rmdir "$EXTRACTED_TO" 2>/dev/null

elif (( $+commands[pkginstall.sh] ))
then
	pkginstall.sh "$PKG"
else
	sudo /usr/sbin/installer -verbose -pkg "$PKG" -dumplog -target / -lang en 2>&1
fi

EXIT="$?"

if [[ "$EXIT" == "0" ]]
then

	echo "$NAME: Installation was a success. Ejecting $MNTPNT now:"

	diskutil eject "$MNTPNT"

	exit 0

else
	echo "$NAME: installation failed (\$EXIT = $EXIT)"

	open "$MNTPNT"

	exit 1
fi


exit 0
#EOF
