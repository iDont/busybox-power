#!/bin/sh
# A script to restore /bin/busybox and delete the symlinks made during 
# installation.
#
# Symbolic links to applets are only removed if they are
# 1) created by the installer script ("install-binary.sh")
# 2) not replaced by a binary (i.e. they are still a symbolic link)
# 3) pointing to a busybox binary
#
# By Dennis Groenen <tj.groenen@gmail.com>
# GPLv3 licensed
#

INSTALLDIR="/opt/busybox-power"
EXECPWR="$INSTALLDIR/busybox.power"
DISTBIN="/bin/busybox.distrib"

VERBOSE="0"
MODIFIEDBIN="0"

INSTBINARY_SHA1=`sha1sum $EXECPWR | awk '{ print $1 }'`
if test -e $DISTBIN; then
  ORIGBINARY_SHA1=`sha1sum $DISTBIN | awk '{ print $1 }'`; fi

# Load shared functions
source $INSTALLDIR/functions

# Check whether we can load the list of created symlinks during installation
CHECK_SYMLINKSFILE() {
    if test ! -e $INSTALLDIR/busybox-power.symlinks; then
      echo -e "Warning: cannot find the list of symlinks to be removed. No" \
        "symlinks will be removed at all!\n" >> /tmp/busybox-power-error
    fi
}

# Check the (integrity) of our BusyBox backup
CHECK_BACKUP() {
    # Firstly, check whether the backup still exists
    if test ! -e $DISTBIN; then
      if test "$ENVIRONMENT" == "SDK"; then return; fi # SDK comes without BB
      echo -e "Warning: the backup of the original BusyBox binary is missing!" \
        "/bin/busybox will not be touched.\n" >> /tmp/busybox-power-error
      return
    fi

    # Secondly, check the integrity of the backup
    if test -e $INSTALLDIR/busybox.distrib.sha1; then
      if test "`cat $INSTALLDIR/busybox.distrib.sha1`" != "$ORIGBINARY_SHA1"; then
        if test "`cat $INSTALLDIR/busybox.distrib.version`" == "`GETBBVERSION`"; then
          # The backup has been changed whilst busybox hasn't been upgraded
          echo -e "Warning: the backup of the original BusyBox binary has" \
            "been modified since installing busybox-power (invalid SHA1" \
            "checksum). Do not continue unless you're sure that $DISTBIN" \
            "is not corrupted.\n" >> /tmp/busybox-power-error
        fi
      fi
    else
      echo -e "Warning: could not load the saved SHA1 checksum of the backup" \
        "of the original BusyBox binary; the integrity of the backup of the" \
        "original binary can not be guaranteed.\n" >> /tmp/busybox-power-error
    fi
}

# Check whether /bin/busybox has been modified after bb-power's installation
CHECK_INSTALLEDBIN() {
    if test "$INSTBINARY_SHA1" != "`sha1sum /bin/busybox | awk '{ print $1 }'`"; then
      echo -e "Warning: /bin/busybox has been modified since installing" \
        "busybox-power (invalid SHA1 checksum). Your current /bin/busybox" \
        "won't be touched and the diversion of /bin/busybox to $DISTBIN will" \
        "not be removed. \n" >> /tmp/busybox-power-error
      MODIFIEDBIN="1"
    fi
}

# Display encountered errors
DISPLAY_ERRORS() {
    case $ENVIRONMENT in
      SDK)
        echo -e "\n\n-----------Attention!-----------"
        cat /tmp/busybox-power-error
        rm /tmp/busybox-power-error
        echo "-> Please press [enter] to ignore the above errors/warnings."
        echo "   Hit [ctrl-c] to break"
        read 
        ;;
      FREMANTLE)
        echo "Click \"I Agree\" to ignore the above errors/warnings. Ask for" \
          "help if you don't know what to do." >> /tmp/busybox-power-error
        echo "Please confirm the text on the screen of your device"
        maemo-confirm-text "Attention!" /tmp/busybox-power-error
        res=$?
        rm /tmp/busybox-power-error
        if test ! $res == 0; then exit 1; fi
        ;;
      esac
}

# Uninstallation of the enhanced binary
UNINSTALL() {
    if test $MODIFIEDBIN == 1; then
      # /bin/busybox has been modified since installing busybox-power
      # Leave both the file and the diversion in place
      return
    elif test -e $DISTBIN; then
      cp -af $DISTBIN /bin/busybox
      if test -e /bin/busybox; then
        rm $DISTBIN; fi
    elif test "$ENVIRONMENT" == "SDK"; then
      # There was no /bin/busybox to begin with..
      rm /bin/busybox
    fi

    /usr/sbin/dpkg-divert --remove /bin/busybox
}

# Remove all symlinks that the installation script has made
UNSYMLINK() {
    # Load list of installed symlinks
    touch $INSTALLDIR/busybox-power.symlinks
    source $INSTALLDIR/busybox-power.symlinks

    # Walk through all possible destinations
    for DESTDIR in $DESTINATIONS; do 
      # Enable us to see all entries in $DESTINATIONS as variables
      eval "APPLICATIONS=\$$DESTDIR"
      # Set destination directory accordingly
      case $DESTDIR in
        DEST_BIN)
          DIR="/bin"
          ;;
        DEST_SBIN)
          DIR="/sbin"
          ;;
        DEST_USRBIN)
          DIR="/usr/bin"
          ;;
        DEST_USRSBIN)
          DIR="/usr/sbin"
          ;;
      esac

      ECHO_VERBOSE "\nRemoving symlinks in $DIR"
      # Walk through all applications from the current destination
      for APP in $APPLICATIONS; do
        # The following code is executed for every application in the current
        # destination
        if test -h $DIR/$APP; then 
          # Good, this app is still a symbolic link ..
          if test -n "`ls -l $DIR/$APP | grep busybox`"; then
            ECHO_VERBOSE "Removing link: $DIR/$APP"
            rm $DIR/$APP
          fi
        fi
      done
    done
}

# Action to be performed after restoring original busybox
CLEANUP() {
    OLDFILES="busybox-power.symlinks
      busybox.distrib.version
      busybox.distrib.sha1"

    for file in $OLDFILES; do
      if test -e $INSTALLDIR/$file; then
        rm $INSTALLDIR/$file
      fi
    done
}

### Codepath ###
ECHO_VERBOSE "busybox-power: verbose mode"
ECHO_VERBOSE "  binary: $EXECPWR"
ECHO_VERBOSE "  version string: `$EXECPWR | $EXECPWR head -n 1`"
CHECK_ENV && ECHO_VERBOSE "  environment: $ENVIRONMENT"

CHECK_STANDALONE
CHECK_SYMLINKSFILE
if test "$ENVIRONMENT" != "SDK"; then
  CHECK_ROOT
  CHECK_BACKUP
  CHECK_INSTALLEDBIN
fi
if test -e /tmp/busybox-power-error; then
  # An error has occured during the checks
  DISPLAY_ERRORS
fi
UNSYMLINK
UNINSTALL
CLEANUP

