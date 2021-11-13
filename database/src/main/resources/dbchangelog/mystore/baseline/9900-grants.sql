GRANT USAGE ON SCHEMA mystore TO egd_usr;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA mystore TO egd_usr;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA mystore TO egd_usr;

GRANT USAGE ON SCHEMA mystore TO participant_support_ro;
GRANT SELECT ON ALL TABLES IN SCHEMA mystore TO participant_support_ro;
GRANT USAGE ON SCHEMA mystore TO participant_support_rw;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA mystore TO participant_support_rw;
GRANT USAGE ON SCHEMA mystore_log TO participant_support_rw;
GRANT SELECT ON ALL TABLES IN SCHEMA mystore_log TO participant_support_rw;
