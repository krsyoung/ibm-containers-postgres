#!/bin/bash
set -e
set -x
if [ "${1:0:1}" = '-' ]; then
	set -- postgres "$@"
fi

if [ "$1" = 'postgres' ]; then

  STARTTIME=$(date +%s)

  echo "START: hack for IBM Container Volumes"
  # Bluemix hack for using NFS based Volumes.  We have to do some special things
  # here because 'root' in a volume isn't the same as 'root' in the container.
  # This leads to problems like the container 'root' being unable to access
  # a directory created by the postgres use.

  # set things up so we can modify with `postgres` user
  chmod 775 "$PGBASE"
  adduser postgres root
  eval "gosu postgres mkdir -p $PGDATA"
  eval "gosu postgres chown -R postgres $PGDATA"
  eval "gosu postgres chmod 700 $PGDATA"

  # put things back to normal
  deluser postgres root
  chmod 755 "$PGBASE"
  echo "END: hack for IBM Container Volumes"


	chmod g+s /run/postgresql
	chown -R postgres /run/postgresql

	# look specifically for PG_VERSION, as it is expected in the DB dir
  # Need to do this as postgres otherwise we get permission denied.
  set +e
  gosu postgres test -s $PGDATA/PG_VERSION
  rc=$?
  set -e
	# if [ ! -s "$PGDATA/PG_VERSION" ]; then
  if [ $rc -ne 0 ]; then
		eval "gosu postgres initdb $POSTGRES_INITDB_ARGS"

		# check password first so we can output the warning before postgres
		# messes it up
		if [ "$POSTGRES_PASSWORD" ]; then
			pass="PASSWORD '$POSTGRES_PASSWORD'"
			authMethod=md5
		else
			# The - option suppresses leading tabs but *not* spaces. :)
			cat >&2 <<-'EOWARN'
				****************************************************
				WARNING: No password has been set for the database.
				         This will allow anyone with access to the
				         Postgres port to access your database. In
				         Docker's default configuration, this is
				         effectively any other container on the same
				         system.
				         Use "-e POSTGRES_PASSWORD=password" to set
				         it in "docker run".
				****************************************************
			EOWARN

			pass=
			authMethod=trust
		fi

		# { echo; echo "host all all 0.0.0.0/0 $authMethod"; } >> "$PGDATA/pg_hba.conf"
    { echo; echo "host all all 0.0.0.0/0 $authMethod"; } | gosu postgres tee -a "$PGDATA/pg_hba.conf"

		# internal start of server in order to allow set-up using psql-client
		# does not listen on TCP/IP and waits until start finishes
		gosu postgres pg_ctl -D "$PGDATA" \
			-o "-c listen_addresses=''" \
			-w start

		: ${POSTGRES_USER:=postgres}
		: ${POSTGRES_DB:=$POSTGRES_USER}
		export POSTGRES_USER POSTGRES_DB

		psql=( psql -v ON_ERROR_STOP=1 )

		if [ "$POSTGRES_DB" != 'postgres' ]; then
			"${psql[@]}" --username postgres <<-EOSQL
				CREATE DATABASE "$POSTGRES_DB" ;
			EOSQL
			echo
		fi

		if [ "$POSTGRES_USER" = 'postgres' ]; then
			op='ALTER'
		else
			op='CREATE'
		fi
		"${psql[@]}" --username postgres <<-EOSQL
			$op USER "$POSTGRES_USER" WITH SUPERUSER $pass ;
		EOSQL
		echo

		psql+=( --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" )

		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)     echo "$0: running $f"; . "$f" ;;
				*.sql)    echo "$0: running $f"; "${psql[@]}" < "$f"; echo ;;
				*.sql.gz) echo "$0: running $f"; gunzip -c "$f" | "${psql[@]}"; echo ;;
				*)        echo "$0: ignoring $f" ;;
			esac
			echo
		done

		gosu postgres pg_ctl -D "$PGDATA" -m fast -w stop

		echo
		echo 'PostgreSQL init process complete; ready for start up.'
		echo
	fi

  ENDTIME=$(date +%s)
  echo " >> runtime (seconds): $(($ENDTIME - $STARTTIME))"

	exec gosu postgres "$@"
fi

exec "$@"
