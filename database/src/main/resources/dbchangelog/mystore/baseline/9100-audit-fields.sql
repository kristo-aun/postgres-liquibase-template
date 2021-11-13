SELECT public.add_audit_columns_to_table(t.table_schema || '.' || t.table_name)
FROM information_schema.tables t
WHERE t.table_schema = 'mystore'
  AND t.table_type <> 'VIEW'
  AND NOT EXISTS (
        SELECT * FROM information_schema.columns c
        WHERE (c.table_schema = t.table_schema)
          AND (c.table_name = t.table_name )
          AND (c.column_name = 'created_by')
    )
ORDER BY t.table_name;
