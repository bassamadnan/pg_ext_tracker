\echo '-- PostgreSQL and Extension Version Information'
SELECT version();
SELECT name, default_version, installed_version 
FROM pg_available_extensions 
WHERE name = 'pg_stat_statements';
\echo ''

-- formatting to check diff
\pset format unaligned
\pset tuples_only off
\pset footer off

\echo '-- ================================================================================'
\echo '-- EXTENSION VIEW COLUMN INFORMATION'
\echo '-- ================================================================================'

-- Get all views from the extension
SELECT 
    c.relname AS view_name,
    STRING_AGG(a.attname, ', ' ORDER BY a.attnum) AS columns
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_attribute a ON c.oid = a.attrelid
WHERE 
    n.nspname = 'public' 
    AND c.relkind = 'v'
    AND c.relname LIKE 'pg\_stat\_statements%'
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY 
    c.relname
ORDER BY 
    c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- EXTENSION FUNCTION INFORMATION'
\echo '-- ================================================================================'

-- Get all functions from the extension
SELECT 
    p.proname AS function_name,
    pg_get_function_arguments(p.oid) AS function_args,
    t.typname AS return_type
FROM 
    pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    JOIN pg_type t ON p.prorettype = t.oid
WHERE 
    n.nspname = 'public'
    AND p.proname LIKE 'pg\_stat\_statements%'
ORDER BY 
    p.proname;

\echo ''
\echo '-- ================================================================================'
\echo '-- EXTENSION VIEW DEFINITIONS'
\echo '-- ================================================================================'

-- Get view definitions
\pset fieldsep '|\n'
SELECT 
    c.relname AS view_name,
    pg_get_viewdef(c.oid, true) AS definition
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE 
    n.nspname = 'public'
    AND c.relkind = 'v'
    AND c.relname LIKE 'pg\_stat\_statements%'
ORDER BY 
    c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- EXTENSION TABLES AND COLUMNS'
\echo '-- ================================================================================'

-- Get tables and their columns
SELECT 
    c.relname AS table_name,
    STRING_AGG(a.attname || ' ' || pg_catalog.format_type(a.atttypid, a.atttypmod), 
               ', ' ORDER BY a.attnum) AS columns
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_attribute a ON c.oid = a.attrelid
WHERE 
    n.nspname = 'public' 
    AND c.relkind = 'r'
    AND c.relname LIKE 'pg\_stat\_statements%'
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY 
    c.relname
ORDER BY 
    c.relname;
