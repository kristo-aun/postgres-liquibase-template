SELECT mystore.mglog_audit_table(t.table_schema || '.' || t.table_name)
FROM information_schema.tables t
WHERE t.table_schema = 'mystore'
  AND t.table_type <> 'VIEW'
  AND NOT EXISTS (
        SELECT * FROM information_schema.triggers tr
        WHERE (tr.trigger_schema = t.table_schema)
          AND (tr.trigger_name = 'log_trigger_row')
          AND (tr.event_object_schema = t.table_schema)
          AND (tr.event_object_table = t.table_name)
    )
ORDER BY t.table_name;
