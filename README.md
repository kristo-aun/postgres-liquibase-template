# Postgres + Liquibase bare template

This template should be a good start if you need to develop a proper RDBMS with version control and auditing.

Fetures:

- Docker Compose for local development.
- Postgres running on Docker.
- Liquibase container starts up after PG on Docker as well.
- Liquibase applies changesets on the empty database.

Other features:

- Gradle task to apply changesets to other databases.
- By embedding this codebase into a Java project, the database.jar can be used by Liquibase during runtime.
- Automatic changelog of all tables.

## Run 

Up

    docker-compose -f docker-compose.yml up -d

The compose will apply LB changeset to the local database automatically.
You can apply further LB changes manually like so:

    ./gradlew :database:update

Down

    docker-compose -f docker-compose.yml down

Apply the changesets to another database:

    ./gradlew :database:update  \
        -PliquibaseUrl=jdbc:postgresql://coredb.acme.com:5432/coredb \
        -PliquibaseUsername=coredb_owner \
        -PliquibasePassword=changeit \
        -PliquibaseContexts=faker

## Links

- https://wiki.postgresql.org/wiki/Audit_trigger_91plus
