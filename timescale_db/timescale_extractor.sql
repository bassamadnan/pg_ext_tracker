\echo '-- PostgreSQL and TimescaleDB Version Information'
SELECT version();
SELECT extname, extversion FROM pg_extension WHERE extname = 'timescaledb';
\echo ''

-- formatting to check diff
\pset format unaligned
\pset tuples_only off
\pset footer off

\echo '-- ================================================================================'
\echo '-- TIMESCALEDB VIEW COLUMN INFORMATION'
\echo '-- ================================================================================'

-- Get all TimescaleDB views from various schemas
SELECT 
    n.nspname AS schema_name,
    c.relname AS view_name,
    STRING_AGG(a.attname, ', ' ORDER BY a.attnum) AS columns
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_attribute a ON c.oid = a.attrelid
WHERE 
    n.nspname IN ('timescaledb_information', 'timescaledb_experimental', '_timescaledb_catalog', '_timescaledb_internal', 'public')
    AND c.relkind = 'v'
    AND a.attnum > 0
    AND NOT a.attisdropped
    AND (
        c.relname LIKE '%timescale%' OR
        c.relname LIKE '%hypertable%' OR
        c.relname LIKE '%chunk%' OR
        c.relname LIKE '%dimension%' OR
        c.relname LIKE '%compression%' OR
        c.relname LIKE '%continuous_aggregate%' OR
        c.relname LIKE '%job%' OR
        c.relname LIKE '%policy%' OR
        n.nspname LIKE '%timescaledb%'
    )
GROUP BY 
    n.nspname, c.relname
ORDER BY 
    n.nspname, c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- TIMESCALEDB FUNCTION INFORMATION'
\echo '-- ================================================================================'

-- Get all TimescaleDB functions
SELECT 
    n.nspname AS schema_name,
    p.proname AS function_name,
    pg_get_function_arguments(p.oid) AS function_args,
    t.typname AS return_type
FROM 
    pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    JOIN pg_type t ON p.prorettype = t.oid
WHERE 
    n.nspname IN ('timescaledb_information', 'timescaledb_experimental', '_timescaledb_catalog', '_timescaledb_internal', 'public')
    AND (
        p.proname LIKE '%timescale%' OR
        p.proname LIKE '%hypertable%' OR
        p.proname LIKE '%chunk%' OR
        p.proname LIKE '%dimension%' OR
        p.proname LIKE '%compression%' OR
        p.proname LIKE '%continuous_aggregate%' OR
        p.proname LIKE '%job%' OR
        p.proname LIKE '%policy%' OR
        n.nspname LIKE '%timescaledb%'
    )
ORDER BY 
    n.nspname, p.proname;

\echo ''
\echo '-- ================================================================================'
\echo '-- TIMESCALEDB VIEW DEFINITIONS'
\echo '-- ================================================================================'

-- Get view definitions
\pset fieldsep '|\n'
SELECT 
    n.nspname AS schema_name,
    c.relname AS view_name,
    pg_get_viewdef(c.oid, true) AS definition
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE 
    n.nspname IN ('timescaledb_information', 'timescaledb_experimental', '_timescaledb_catalog', '_timescaledb_internal', 'public')
    AND c.relkind = 'v'
    AND (
        c.relname LIKE '%timescale%' OR
        c.relname LIKE '%hypertable%' OR
        c.relname LIKE '%chunk%' OR
        c.relname LIKE '%dimension%' OR
        c.relname LIKE '%compression%' OR
        c.relname LIKE '%continuous_aggregate%' OR
        c.relname LIKE '%job%' OR
        c.relname LIKE '%policy%' OR
        n.nspname LIKE '%timescaledb%'
    )
ORDER BY 
    n.nspname, c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- TIMESCALEDB INFORMATION SCHEMA VIEWS'
\echo '-- ================================================================================'

-- Get specific TimescaleDB information schema views
SELECT 
    schemaname,
    viewname,
    viewowner,
    definition
FROM 
    pg_views
WHERE 
    schemaname IN ('timescaledb_information', 'timescaledb_experimental')
ORDER BY 
    schemaname, viewname;

\echo ''
\echo '-- ================================================================================'
\echo '-- TIMESCALEDB CATALOG TABLES'
\echo '-- ================================================================================'

-- Get catalog tables and their columns
SELECT 
    n.nspname AS schema_name,
    c.relname AS table_name,
    STRING_AGG(a.attname || ' ' || pg_catalog.format_type(a.atttypid, a.atttypmod), 
               ', ' ORDER BY a.attnum) AS columns
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_attribute a ON c.oid = a.attrelid
WHERE 
    n.nspname IN ('_timescaledb_catalog', '_timescaledb_internal')
    AND c.relkind = 'r'
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY 
    n.nspname, c.relname
ORDER BY 
    n.nspname, c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- TIMESCALEDB EXTENSION DETAILS'
\echo '-- ================================================================================'

-- Get extension details
SELECT 
    e.extname,
    e.extversion,
    e.extrelocatable,
    n.nspname AS schema_name
FROM 
    pg_extension e
    JOIN pg_namespace n ON e.extnamespace = n.oid
WHERE 
    e.extname = 'timescaledb'
ORDER BY 
    e.extname;
