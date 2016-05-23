# ibm-containers-postgres

```yaml
# docker-compose.yml
postgres:
  image: registry.ng.bluemix.net/namespace/postgres:production
  volumes:
    - postgres-data-volume:/var/lib/postgresql/data
  ports:
    - "5432"
  ```
