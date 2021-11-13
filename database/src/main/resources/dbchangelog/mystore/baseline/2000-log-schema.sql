-- An audit history is important on most tables. Provide an audit trigger that logs to
-- a dedicated audit table for the major relations.
--
-- This file should be generic and not depend on application roles or structures,
-- as it's being listed here:
--
--    https://wiki.postgresql.org/wiki/Audit_trigger_91plus

CREATE SEQUENCE IF NOT EXISTS mystore_log.loac_seq
    INCREMENT 1
    MINVALUE 1
    MAXVALUE 9223372036854775807
    START 1
    CACHE 1;

CREATE TABLE mystore_log.logged_actions
(
    event_id BIGINT NOT NULL DEFAULT NEXTVAL('mystore_log.loac_seq') PRIMARY KEY,
    schema_name TEXT NOT NULL,
    table_name TEXT NOT NULL,
    relid OID NOT NULL,
    session_db_user TEXT NOT NULL,
    app_user TEXT,
    app_session_id TEXT,
    action_tstamp_tx TIMESTAMP WITH TIME ZONE NOT NULL,
    transaction_id BIGINT,
    application_name TEXT,
    client_addr INET,
    client_query TEXT,
    action TEXT NOT NULL CHECK (action IN ('I','D','U','T')),
    row_pk TEXT,
    row_data public.hstore,
    changed_fields public.hstore,
    statement_only BOOLEAN NOT NULL
)
;

REVOKE ALL ON mystore_log.logged_actions FROM public;

COMMENT ON TABLE mystore_log.logged_actions IS 'History of auditable actions on audited tables, from pglog_if_modified_func()';
COMMENT ON COLUMN mystore_log.logged_actions.event_id IS 'Unique identifier for each auditable event';
COMMENT ON COLUMN mystore_log.logged_actions.schema_name IS 'Database schema audited table for this event is in';
COMMENT ON COLUMN mystore_log.logged_actions.table_name IS 'Non-schema-qualified table name of table event occured in';
COMMENT ON COLUMN mystore_log.logged_actions.relid IS 'Table OID. Changes with drop/create. Get with ''tablename''::regclass';
COMMENT ON COLUMN mystore_log.logged_actions.session_db_user IS 'Login / session db user whose statement caused the audited event';
COMMENT ON COLUMN mystore_log.logged_actions.app_user IS 'Application user whose statement caused the audited event';
COMMENT ON COLUMN mystore_log.logged_actions.app_session_id IS 'Application session which caused the audited event';
COMMENT ON COLUMN mystore_log.logged_actions.action_tstamp_tx IS 'Transaction start timestamp for tx in which audited event occurred';
COMMENT ON COLUMN mystore_log.logged_actions.transaction_id IS 'Identifier of transaction that made the change. May wrap, but unique paired with action_tstamp_tx.';
COMMENT ON COLUMN mystore_log.logged_actions.application_name IS 'Application name set when this audit event occurred. Can be changed in-session by client.';
COMMENT ON COLUMN mystore_log.logged_actions.client_addr IS 'IP address of client that issued query. Null for unix domain socket.';
COMMENT ON COLUMN mystore_log.logged_actions.client_query IS 'Top-level query that caused this auditable event. May be more than one statement.';
COMMENT ON COLUMN mystore_log.logged_actions.action IS 'Action type; I = insert, D = delete, U = update, T = truncate';
COMMENT ON COLUMN mystore_log.logged_actions.row_pk IS 'Record primary key value.';
COMMENT ON COLUMN mystore_log.logged_actions.row_data IS 'Record value. Null for statement-level trigger. For INSERT this is the new tuple. For DELETE and UPDATE it is the old tuple.';
COMMENT ON COLUMN mystore_log.logged_actions.changed_fields IS 'New values of fields changed by UPDATE. Null except for row-level UPDATE events.';
COMMENT ON COLUMN mystore_log.logged_actions.statement_only IS '''t'' if audit event is from an FOR EACH STATEMENT trigger, ''f'' for FOR EACH ROW';
