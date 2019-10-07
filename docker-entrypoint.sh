#!/bin/bash
set -e


if [ "$1" = "slurmdbd" ]
then
    echo "---> Checking for mounted config ..."
    # This code facilitates dynamically replacing the DbdAddr and DbdHost
    # in the slurmdbd.conf and moving the config to /etc/slurm/ in the container.
    SLURMDBD_SRC_CONFIG_FILE=/mnt/slurmdbd.conf
    SLURMDBD_TGT_CONFIG_FILE=/etc/slurm/slurmdbd.conf

    if [ -f "$SLURMDBD_SRC_CONFIG_FILE" ]; then
        echo "---> Found mounted config ..."
	SLURMDBD_HOSTNAME=`hostname -f`

        awk -v var="DbdHost" -v new_val=$SLURMDBD_HOSTNAME \
	    'BEGIN{FS=OFS="="}match($1, "^\\s*" var "\\s*") {$2="" new_val}1' \
	        $SLURMDBD_SRC_CONFIG_FILE | \
		    awk -v var="DbdAddr" -v new_val=$SLURMDBD_HOSTNAME \
		        'BEGIN{FS=OFS="="}match($1, "^\\s*" var "\\s*") {$2="" new_val}1' > \
			    $SLURMDBD_TGT_CONFIG_FILE
    else
        echo "---> No mounted config found ..."
    fi

    echo "---> Starting the MUNGE Authentication service (munged) ..."
    gosu munge /usr/sbin/munged

    echo "---> Starting the Slurm Database Daemon (slurmdbd) ..."

    {
        . $SLURMDBD_TGT_CONFIG_FILE
        until echo "SELECT 1" | mysql -h $StorageHost -u$StorageUser -p$StoragePass 2>&1 > /dev/null
        do
            echo "-- Waiting for database to become active ..."
            sleep 2
        done
    }
    echo "-- Database is now active ..."

    echo "-- Starting slurmdbd ..."
    exec gosu slurm /usr/sbin/slurmdbd -Dvvv
fi

if [ "$1" = "slurmctld" ]
then
    echo "---> Checking for mounted config ..."
    # This code facilitates dynamically replacing the SlurmctldHost and SlurmctldAddr
    # in the slurmdbd.conf and moving the config to /etc/slurm/ in the container.
    SLURMCTLD_SRC_CONFIG_FILE=/mnt/slurm.conf
    SLURMCTLD_TGT_CONFIG_FILE=/etc/slurm/slurm.conf

    if [ -f "$SLURMCTLD_SRC_CONFIG_FILE" ]; then
        echo "---> Found mounted config ..."
	SLURMCTLD_HOSTNAME=`hostname -f`

        awk -v var="SlurmctldHost" -v new_val=$SLURMCTLD_HOSTNAME \
	    'BEGIN{FS=OFS="="}match($1, "^\\s*" var "\\s*") {$2="" new_val}1' \
	        $SLURMCTLD_SRC_CONFIG_FILE | \
		    awk -v var="SlurmctldAddr" -v new_val=$SLURMCTLD_HOSTNAME \
		        'BEGIN{FS=OFS="="}match($1, "^\\s*" var "\\s*") {$2="" new_val}1' > \
			    $SLURMCTLD_TGT_CONFIG_FILE
    else
        echo "---> No mounted config found ..."
    fi

    echo "---> Starting the MUNGE Authentication service (munged) ..."
    gosu munge /usr/sbin/munged

    echo "---> Waiting for slurmdbd to become active before starting slurmctld ..."

    until 2>/dev/null >/dev/tcp/slurmdbd/6819
    do
        echo "-- slurmdbd is not available.  Sleeping ..."
        sleep 2
    done
    echo "-- slurmdbd is now active ..."

    echo "---> Starting the Slurm Controller Daemon (slurmctld) ..."
    exec gosu slurm /usr/sbin/slurmctld -Dvvv 
fi

if [ "$1" = "slurmd" ]
then
    echo "---> Checking for mounted config ..."
    # This code facilitates dynamically replacing the SlurmctldHost and SlurmctldAddr
    # in the slurmdbd.conf and moving the config to /etc/slurm/ in the container.
    SLURMD_SRC_CONFIG_FILE=/mnt/slurm.conf
    SLURMD_TGT_CONFIG_FILE=/etc/slurm/slurm.conf

    if [ -f "$SLURMD_SRC_CONFIG_FILE" ]; then
        echo "---> Found mounted config ..."
        echo "---> Generating runtime config ..."
	cp $SLURMD_SRC_CONFIG_FILE $SLURMD_TGT_CONFIG_FILE
    else
        echo "---> No mounted config found ..."
    fi

    echo "---> Starting the MUNGE Authentication service (munged) ..."
    gosu munge /usr/sbin/munged

    echo "---> Waiting for slurmctld to become active before starting slurmd..."

    until 2>/dev/null >/dev/tcp/slurmctld/6817
    do
        echo "-- slurmctld is not available.  Sleeping ..."
        sleep 2
    done
    echo "-- slurmctld is now active ..."

    echo "---> Starting the Slurm Node Daemon (slurmd) ..."
    exec /usr/sbin/slurmd -Dvvv
fi

exec "$@"
