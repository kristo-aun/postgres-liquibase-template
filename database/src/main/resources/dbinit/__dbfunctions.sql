-- Add audit columns to table
\c coredb
CREATE OR REPLACE FUNCTION add_audit_columns_to_table(target_table TEXT)
    RETURNS VOID AS
$BODY$
DECLARE
    _q_txt text;
BEGIN
    _q_txt = 'ALTER TABLE ' || target_table ||
             ' ADD COLUMN created_by VARCHAR(100) NOT NULL,' ||
             ' ADD COLUMN created_dtime TIMESTAMP WITH TIME ZONE NOT NULL,' ||
             ' ADD COLUMN modified_by VARCHAR(100) NOT NULL,' ||
             ' ADD COLUMN modified_dtime TIMESTAMP WITH TIME ZONE NOT NULL' ||
             ';';
    RAISE NOTICE '%',_q_txt;
    EXECUTE _q_txt;
END
$BODY$ LANGUAGE 'plpgsql' SECURITY DEFINER;

ALTER FUNCTION add_audit_columns_to_table(TEXT) OWNER TO coredb_owner;

-- Audit columns trigger function
CREATE OR REPLACE FUNCTION audit()
    RETURNS TRIGGER AS $BODY$
DECLARE
    v_time     TIMESTAMP WITH TIME ZONE;
    v_app_user VARCHAR(30);
BEGIN

    v_time := current_timestamp;
    v_app_user := coalesce(current_setting('SESSION_CONTEXT.APP_USER', 't'), session_user);

    IF v_app_user = '' THEN
        RAISE EXCEPTION 'Session context not initialised';
    END IF;

    IF TG_OP = 'INSERT'
    THEN
        NEW.created_dtime := v_time;
        NEW.created_by    := v_app_user;
    ELSE
        NEW.created_dtime := OLD.created_dtime;
        NEW.created_by    := OLD.created_by;
    END IF;

    NEW.modified_dtime := v_time;
    NEW.modified_by := v_app_user;

    RETURN NEW;
END
$BODY$ LANGUAGE 'plpgsql' SECURITY DEFINER;

ALTER FUNCTION audit() OWNER TO coredb_owner;

-- Organization audit columns trigger function
CREATE OR REPLACE FUNCTION org_audit()
    RETURNS TRIGGER AS $BODY$
DECLARE
    v_org_code VARCHAR(50);
BEGIN

    v_org_code := current_setting('SESSION_CONTEXT.ORG_CODE', 't');

    IF v_org_code = '' THEN
        RAISE EXCEPTION 'Organization context not initialised';
    END IF;

    NEW.org_code := v_org_code;

    RETURN NEW;
END
$BODY$ LANGUAGE 'plpgsql' SECURITY DEFINER;

ALTER FUNCTION org_audit() OWNER TO coredb_owner;

-- Add audit trigger to table
CREATE OR REPLACE FUNCTION add_audit_trigger_to_table(target_table text)
    RETURNS VOID AS
$BODY$
DECLARE
    _q_txt text;
BEGIN
    _q_txt = 'DROP TRIGGER IF EXISTS trg_audit ON ' || target_table || ';'
                 || 'CREATE TRIGGER trg_audit BEFORE INSERT OR UPDATE ON ' || target_table || ' FOR EACH ROW EXECUTE PROCEDURE public.audit();';
    RAISE NOTICE '%',_q_txt;
    EXECUTE _q_txt;
END
$BODY$ LANGUAGE 'plpgsql' SECURITY DEFINER;

ALTER FUNCTION add_audit_trigger_to_table(TEXT) OWNER TO coredb_owner;

-- Add organization audit trigger to table
CREATE OR REPLACE FUNCTION add_org_audit_trigger_to_table(target_table text)
    RETURNS VOID AS
$BODY$
DECLARE
    _q_txt text;
BEGIN
    _q_txt = 'DROP TRIGGER IF EXISTS trg_org_audit ON ' || target_table || ';'
                 || 'CREATE TRIGGER trg_org_audit BEFORE INSERT OR UPDATE ON ' || target_table || ' FOR EACH ROW EXECUTE PROCEDURE public.org_audit();';
    RAISE NOTICE '%',_q_txt;
    EXECUTE _q_txt;
END
$BODY$ LANGUAGE 'plpgsql' SECURITY DEFINER;

ALTER FUNCTION add_org_audit_trigger_to_table(TEXT) OWNER TO coredb_owner;

-- Session context functions
CREATE OR REPLACE FUNCTION set_session_context(i_user VARCHAR, i_app_session_id VARCHAR, i_org_code VARCHAR)
    RETURNS VOID AS
$BODY$
BEGIN
    PERFORM set_config('SESSION_CONTEXT.APP_USER', i_user, true);
    PERFORM set_config('SESSION_CONTEXT.APP_SESSION_ID', i_app_session_id, true);
    PERFORM set_config('SESSION_CONTEXT.ORG_CODE', i_org_code, true);
END;
$BODY$ LANGUAGE 'plpgsql' VOLATILE SECURITY DEFINER COST 100;

ALTER FUNCTION set_session_context( VARCHAR, VARCHAR, VARCHAR) OWNER TO coredb_owner;

REVOKE ALL ON FUNCTION set_session_context(VARCHAR, VARCHAR, VARCHAR) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION set_session_context(VARCHAR, VARCHAR, VARCHAR) TO coredb_owner;
GRANT EXECUTE ON FUNCTION set_session_context(VARCHAR, VARCHAR, VARCHAR) TO egd_usr;
GRANT EXECUTE ON FUNCTION set_session_context(VARCHAR, VARCHAR, VARCHAR) TO participant_support_rw;


-- execute with the following statement
-- SELECT add_missing_audit_columns();
CREATE OR REPLACE FUNCTION add_missing_audit_columns()
    RETURNS VOID AS
$BODY$
DECLARE
    r record;
BEGIN
    FOR r IN
        SELECT t.table_schema, t.table_name
        FROM information_schema.tables t
        WHERE (t.table_schema NOT IN ('public', 'information_schema', 'pg_catalog'))
          AND t.table_name NOT IN ('databasechangelog', 'databasechangeloglock')
          AND NOT EXISTS (
                SELECT * FROM information_schema.columns c
                WHERE (c.table_schema = t.table_schema)
                  AND (c.table_name = t.table_name )
                  AND (c.column_name = 'created_by')
            )
        ORDER BY 1, 2
        LOOP
            PERFORM add_audit_columns_to_table(r.table_schema || '.' || r.table_name);
        END LOOP;
END
$BODY$ LANGUAGE 'plpgsql' SECURITY DEFINER;

ALTER FUNCTION add_missing_audit_columns() OWNER TO coredb_owner;

CREATE OR REPLACE FUNCTION mg_get_app_user() RETURNS varchar AS $body$
BEGIN
    RETURN current_setting('SESSION_CONTEXT.APP_USER');
EXCEPTION WHEN OTHERS THEN
    RETURN null;
END;
$body$ LANGUAGE 'plpgsql' SECURITY DEFINER;

ALTER FUNCTION mg_get_app_user() OWNER TO coredb_owner;

CREATE OR REPLACE FUNCTION mg_get_app_session_id() RETURNS varchar AS $body$
BEGIN
    RETURN current_setting('SESSION_CONTEXT.APP_SESSION_ID');
EXCEPTION WHEN OTHERS THEN
    RETURN null;
END;
$body$ LANGUAGE 'plpgsql' SECURITY DEFINER;

ALTER FUNCTION mg_get_app_session_id() OWNER TO coredb_owner;

-- sample execution for one schema to (re)create audit triggers
--SELECT public.add_audit_trigger_to_table(t.table_schema || '.' || t.table_name)
--FROM information_schema.tables t
--WHERE (t.table_schema = 'party' AND t.table_name NOT IN ('databasechangelog', 'databasechangeloglock'))
--ORDER BY t.table_name;
