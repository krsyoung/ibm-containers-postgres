FROM postgres:9.4

ENV PGBASE /var/lib/postgresql/data
ENV PGDATA /var/lib/postgresql/data/pgdata

COPY docker-entrypoint-bluemix.sh /

ENTRYPOINT ["/docker-entrypoint-bluemix.sh"]

EXPOSE 5432
CMD ["postgres"]
