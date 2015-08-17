#!/bin/sh
#
#    Licensed to the Apache Software Foundation (ASF) under one or more
#    contributor license agreements.  See the NOTICE file distributed with
#    this work for additional information regarding copyright ownership.
#    The ASF licenses this file to You under the Apache License, Version 2.0
#    (the "License"); you may not use this file except in compliance with
#    the License.  You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS,
#    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#    See the License for the specific language governing permissions and
#    limitations under the License.
#
# chkconfig: 2345 20 80
# description: Apache NiFi is a dataflow system based on the principles of Flow-Based Programming.
#
# This script is based on the bin/nifi.sh script in the NiFi binary distribution.
# Script structure inspired from Apache Karaf and other Apache projects with similar startup approaches

# the bootstrap file lives here
# CONF_DIR :: The directory where the role configuration is placed

date >> /tmp/cm-nifi.out
echo "Working directory" `pwd` >> /tmp/cm-nifi.out
echo "Called: $0 $@" >> /tmp/cm-nifi.out
echo "Env: " `env` >> /tmp/cm-nifi.out

NIFI_HOME="$CDH_NIFI_PARCEL_DIR/lib/nifi";
NIFI_CONF="$CONF_DIR/conf/nifi.properties";
BOOTSTRAP_CONF="$CONF_DIR/conf/bootstrap.conf";
PROGNAME=`basename "$0"`

finishConfiguration() {
    # ensure the directory for the pid file exists
    mkdir -p $CONF_DIR/bin

    if [ -e "$CONF_DIR/ncm.properties" ]; then
        cluster_manager=`cat $CONF_DIR/ncm.properties | awk -F':' '{print $1}'`
        echo "nifi.cluster.node.unicast.manager.address=$cluster_manager" >> $NIFI_CONF
        rm $CONF_DIR/ncm.properties # remove the file
    fi

    # recreate bootstrap.conf
    cat $CONF_DIR/aux/bootstrap.conf.template > $BOOTSTRAP_CONF
    echo "lib.dir=$NIFI_HOME/lib" >> $BOOTSTRAP_CONF
    echo "conf.dir=$CONF_DIR/conf" >> $BOOTSTRAP_CONF
    echo "java=$JAVA" >> $BOOTSTRAP_CONF
}


warn() {
    echo "${PROGNAME}: $*"
}

die() {
    warn "$*"
    exit 1
}

detectOS() {
    # OS specific support (must be 'true' or 'false').
    cygwin=false;
    aix=false;
    os400=false;
    darwin=false;
    case "`uname`" in
        CYGWIN*)
            cygwin=true
            ;;
        AIX*)
            aix=true
            ;;
        OS400*)
            os400=true
            ;;
        Darwin)
                darwin=true
                ;;
    esac
    # For AIX, set an environment variable
    if $aix; then
         export LDR_CNTRL=MAXDATA=0xB0000000@DSA
         echo $LDR_CNTRL
    fi
}

unlimitFD() {
    # Use the maximum available, or set MAX_FD != -1 to use that
    if [ "x$MAX_FD" = "x" ]; then
        MAX_FD="maximum"
    fi

    # Increase the maximum file descriptors if we can
    if [ "$os400" = "false" ] && [ "$cygwin" = "false" ]; then
        MAX_FD_LIMIT=`ulimit -H -n`
        if [ "$MAX_FD_LIMIT" != 'unlimited' ]; then
            if [ $? -eq 0 ]; then
                if [ "$MAX_FD" = "maximum" -o "$MAX_FD" = "max" ]; then
                    # use the system max
                    MAX_FD="$MAX_FD_LIMIT"
                fi

                ulimit -n $MAX_FD > /dev/null
                # echo "ulimit -n" `ulimit -n`
                if [ $? -ne 0 ]; then
                    warn "Could not set maximum file descriptor limit: $MAX_FD"
                fi
            else
                warn "Could not query system maximum file descriptor limit: $MAX_FD_LIMIT"
            fi
        fi
    fi
}



locateJava() {
    # Setup the Java Virtual Machine
    if $cygwin ; then
        [ -n "$JAVA" ] && JAVA=`cygpath --unix "$JAVA"`
        [ -n "$JAVA_HOME" ] && JAVA_HOME=`cygpath --unix "$JAVA_HOME"`
    fi

    if [ "x$JAVA" = "x" ] && [ -r /etc/gentoo-release ] ; then
        JAVA_HOME=`java-config --jre-home`
    fi
    if [ "x$JAVA" = "x" ]; then
        if [ "x$JAVA_HOME" != "x" ]; then
            if [ ! -d "$JAVA_HOME" ]; then
                die "JAVA_HOME is not valid: $JAVA_HOME"
            fi
            JAVA="$JAVA_HOME/bin/java"
        else
            warn "JAVA_HOME not set; results may vary"
            JAVA=`type java`
            JAVA=`expr "$JAVA" : '.* \(/.*\)$'`
            if [ "x$JAVA" = "x" ]; then
                die "java command not found"
            fi
        fi
    fi
}

init() {
    # Determine if there is special OS handling we must perform
    detectOS

    # Unlimit the number of file descriptors if possible
    unlimitFD

    # Locate the Java VM to execute
    locateJava

    # Make sure the configuration files are ready
    finishConfiguration
}


run() {
    if $cygwin; then
        NIFI_HOME=`cygpath --path --windows "$NIFI_HOME"`
        BOOTSTRAP_CONF=`cygpath --path --windows "$BOOTSTRAP_CONF"`
    fi

    echo
    echo "Java home: $JAVA_HOME"
    echo "NiFi home: $NIFI_HOME"
    echo
    echo "Bootstrap Config File: $BOOTSTRAP_CONF"
    echo

    exec "$JAVA" -cp "$NIFI_HOME"/lib/bootstrap/* -Xms12m -Xmx24m -Dorg.apache.nifi.bootstrap.config.file="$BOOTSTRAP_CONF" org.apache.nifi.bootstrap.RunNiFi $@
}

main() {
    init
    run "$@"
}


case "$1" in
    start-ncm)
        if [ "x$IS_MASTER" == "x" ]; then
          die "Cannot start: not configured as master"
        fi

        main "start"
        ;;

    start-worker)
        if [ "x$IS_WORKER" == "x" ]; then
          die "Cannot start: not configured as worker"
        fi

        main "start"
        ;;

    stop|run|restart|status|dump)
        main "$@"
        ;;
    *)
        echo "Usage nifi {start-ncm|start-worker|stop|run|restart|status|dump}"
        ;;
esac
