CREATE OR REPLACE FUNCTION mystore.mglog_if_modified_func()
    RETURNS TRIGGER AS
$body$
DECLARE
    audit_row mystore_log.logged_actions;
    excluded_cols text[] = ARRAY[]::text[];
    pk_col text;
BEGIN
    IF TG_WHEN <> 'AFTER' THEN
        RAISE EXCEPTION 'mglog_if_modified_func() may only run as an AFTER trigger';
    END IF;

    audit_row = ROW(
        nextval('mystore_log.loac_seq'),          -- event_id
        TG_TABLE_SCHEMA::text,                        -- schema_name
        TG_TABLE_NAME::text,                          -- table_name
        TG_RELID,                                     -- relation OID for much quicker searches
        session_user::text,                           -- session_user_name
        public.mg_get_app_user(),					  -- application user
        public.mg_get_app_session_id(),			      -- application session
        current_timestamp,                            -- action_tstamp_tx
        txid_current(),                               -- transaction ID
        current_setting('application_name'),          -- client application
        inet_client_addr(),                           -- client_addr
        current_query(),                              -- top-level query or queries (if multistatement) from client
        substring(TG_OP,1,1),                         -- action
        NULL, NULL, NULL,                             -- row_pk, row_data, changed_fields
        'f'                                           -- statement_only
        );

    IF NOT TG_ARGV[0]::boolean IS DISTINCT FROM 'f'::boolean THEN
        audit_row.client_query = NULL;
    END IF;

    IF TG_ARGV[1] IS NOT NULL THEN
        excluded_cols = TG_ARGV[1]::text[];
    END IF;

    IF TG_ARGV[2] IS NOT NULL THEN
        pk_col = TG_ARGV[2]::text;
    END IF;

    IF (TG_OP = 'UPDATE' AND TG_LEVEL = 'ROW') THEN
        audit_row.row_data = hstore(OLD.*) - excluded_cols;
        audit_row.changed_fields =  (hstore(NEW.*) - audit_row.row_data) - excluded_cols;
        IF audit_row.changed_fields = hstore('') THEN
            -- All changed fields are ignored. Skip this update.
            RETURN NULL;
        END IF;
        IF pk_col IS NOT NULL THEN
            audit_row.row_pk = hstore(NEW.*) -> pk_col;
        END IF;
    ELSIF (TG_OP = 'DELETE' AND TG_LEVEL = 'ROW') THEN
        audit_row.row_data = hstore(OLD.*) - excluded_cols;
        IF pk_col IS NOT NULL THEN
            audit_row.row_pk = hstore(OLD.*) -> pk_col;
        END IF;
    ELSIF (TG_OP = 'INSERT' AND TG_LEVEL = 'ROW') THEN
        audit_row.row_data = hstore(NEW.*) - excluded_cols;
        IF pk_col IS NOT NULL THEN
            audit_row.row_pk = hstore(NEW.*) -> pk_col;
        END IF;
    ELSIF (TG_LEVEL = 'STATEMENT' AND TG_OP IN ('INSERT','UPDATE','DELETE','TRUNCATE')) THEN
        audit_row.statement_only = 't';
    ELSE
        RAISE EXCEPTION '[mglog_if_modified_func] - Trigger func added as trigger for unhandled case: %, %',TG_OP, TG_LEVEL;
    END IF;
    INSERT INTO mystore_log.logged_actions VALUES (audit_row.*);
    RETURN NULL;
END;
$body$ LANGUAGE 'plpgsql' SECURITY DEFINER SET search_path = pg_catalog, public;


COMMENT ON FUNCTION mystore.mglog_if_modified_func() IS $body$
Track changes to a table at the statement and/or row level.
Optional parameters to trigger in CREATE TRIGGER call:

param 0: boolean, whether to log the query text. Default 't'.
param 1: text[], columns to ignore in updates. Default [].
         Updates to ignored cols are omitted from changed_fields.

         Updates with only ignored cols changed are not inserted
         into the audit log.

         Almost all the processing work is still done for updates
         that ignored. If you need to save the load, you need to use
         WHEN clause on the trigger instead.

         No warning or error is issued if ignored_cols contains columns
         that do not exist in the target table. This lets you specify
         a standard set of ignored columns.

There is no parameter to disable logging of values. Add this trigger as
a 'FOR EACH STATEMENT' rather than 'FOR EACH ROW' trigger if you do not
want to log row values.

Note that the user name logged is the login role for the session. The audit trigger
cannot obtain the active role because it is reset by the SECURITY DEFINER invocation
of the audit trigger its self.
$body$;

CREATE OR REPLACE FUNCTION mystore.mglog_audit_table(
      target_table regclass
    , audit_rows boolean
    , audit_query_text boolean
    , ignored_cols text[]
) RETURNS void AS
$body$
DECLARE
    stm_targets text = 'INSERT OR UPDATE OR DELETE OR TRUNCATE';
    _q_txt text;
    _ignored_cols_snip text = '';
    _pk_col text;
BEGIN
    EXECUTE 'DROP TRIGGER IF EXISTS log_trigger_row ON ' || target_table::TEXT;
    EXECUTE 'DROP TRIGGER IF EXISTS log_trigger_stm ON ' || target_table::TEXT;

    SELECT
        ',' || a.attname INTO _pk_col
    FROM pg_index i
        JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY(i.indkey)
    WHERE i.indrelid = target_table AND i.indisprimary;

    IF audit_rows THEN
        _ignored_cols_snip = ', ' || quote_literal(ignored_cols);
        _q_txt = 'CREATE TRIGGER log_trigger_row AFTER INSERT OR UPDATE OR DELETE ON ' ||
                 target_table::TEXT ||
                 ' FOR EACH ROW EXECUTE PROCEDURE mystore.mglog_if_modified_func(' ||
                 quote_literal(audit_query_text) || _ignored_cols_snip || _pk_col || ');';
        RAISE NOTICE '%',_q_txt;
        EXECUTE _q_txt;
        stm_targets = 'TRUNCATE';
    ELSE
    END IF;

    _q_txt = 'CREATE TRIGGER log_trigger_stm AFTER ' || stm_targets || ' ON ' ||
             target_table::TEXT ||
             ' FOR EACH STATEMENT EXECUTE PROCEDURE mystore.mglog_if_modified_func('||
             quote_literal(audit_query_text) || ');';
    RAISE NOTICE '%',_q_txt;
    EXECUTE _q_txt;

    EXCEPTION WHEN SQLSTATE '22004' THEN
    RAISE exception '%.%', target_table::TEXT, _pk_col;
END;
$body$ language 'plpgsql';

COMMENT ON FUNCTION mystore.mglog_audit_table(regclass, boolean, boolean, text[]) IS $body$
Add auditing support to a table.

Arguments:
   target_table:     Table name, schema qualified if not on search_path
   audit_rows:       Record each row change, or only audit at a statement level
   audit_query_text: Record the text of the client query that triggered the audit event?
   ignored_cols:     Columns to exclude from update diffs, ignore updates that change only ignored cols.
$body$;


-- Pg doesn't allow variadic calls with 0 params, so provide a wrapper
CREATE OR REPLACE FUNCTION mystore.mglog_audit_table(target_table regclass, audit_rows boolean, audit_query_text boolean)
    RETURNS void AS
$body$
    SELECT mystore.mglog_audit_table($1, $2, $3, ARRAY[]::text[]);
$body$ LANGUAGE 'sql';

-- And provide a convenience call wrapper for the simplest case
-- of row-level logging with excluded sys_created and sys_modified columns and query logging disabled.
CREATE OR REPLACE FUNCTION mystore.mglog_audit_table(target_table regclass)
    RETURNS void AS
$body$
    SELECT mystore.mglog_audit_table($1, BOOLEAN 't', BOOLEAN 'f', '{created_by, created_dtime, modified_by, modified_dtime}'::text[]);
$body$ LANGUAGE 'sql';

COMMENT ON FUNCTION mystore.mglog_audit_table(regclass) IS $body$
Add auditing support to the given table. Row-level changes will be logged with full client query text. No cols are ignored.
$body$;
