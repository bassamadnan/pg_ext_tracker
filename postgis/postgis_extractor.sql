\echo '-- PostgreSQL and PostGIS Version Information'
SELECT version();
SELECT name, default_version, installed_version FROM pg_available_extensions WHERE name LIKE 'postgis%' ORDER BY name;
\echo ''

-- Create PostGIS extension if not exists
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
CREATE EXTENSION IF NOT EXISTS postgis_raster;

-- formatting to check diff
\pset format unaligned
\pset tuples_only off
\pset footer off

\echo '-- ================================================================================'
\echo '-- POSTGIS VIEW COLUMN INFORMATION'
\echo '-- ================================================================================'

-- Get all PostGIS-related views
SELECT 
    n.nspname AS schema_name,
    c.relname AS view_name,
    STRING_AGG(a.attname, ', ' ORDER BY a.attnum) AS columns
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_attribute a ON c.oid = a.attrelid
WHERE 
    n.nspname IN ('public', 'topology')
    AND c.relkind = 'v'
    AND (
        c.relname LIKE '%geometry%' OR
        c.relname LIKE '%geography%' OR
        c.relname LIKE '%spatial%' OR
        c.relname LIKE '%topology%' OR
        c.relname LIKE '%raster%' OR
        c.relname LIKE 'st_%'
    )
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY 
    n.nspname, c.relname
ORDER BY 
    n.nspname, c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- POSTGIS FUNCTION INFORMATION'
\echo '-- ================================================================================'

-- Get all PostGIS functions (limited to avoid overwhelming output)
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
    n.nspname IN ('public', 'topology')
    AND (
        p.proname LIKE 'st_%' OR
        p.proname LIKE '%geometry%' OR
        p.proname LIKE '%geography%' OR
        p.proname LIKE '%topology%' OR
        p.proname LIKE '%raster%'
    )
    AND p.proname NOT LIKE '%operator%'  -- Exclude operator functions
ORDER BY 
    n.nspname, p.proname
LIMIT 100;  -- Limit to first 100 functions to keep output manageable

\echo ''
\echo '-- ================================================================================'
\echo '-- POSTGIS DATA TYPES'
\echo '-- ================================================================================'

-- Get PostGIS-specific data types
SELECT 
    n.nspname AS schema_name,
    t.typname AS type_name,
    t.typtype AS type_kind,
    CASE 
        WHEN t.typtype = 'b' THEN 'base type'
        WHEN t.typtype = 'c' THEN 'composite type'
        WHEN t.typtype = 'd' THEN 'domain'
        WHEN t.typtype = 'e' THEN 'enum'
        ELSE 'other'
    END AS type_description
FROM 
    pg_type t
    JOIN pg_namespace n ON t.typnamespace = n.oid
WHERE 
    n.nspname IN ('public', 'topology')
    AND (
        t.typname LIKE '%geometry%' OR
        t.typname LIKE '%geography%' OR
        t.typname LIKE '%raster%' OR
        t.typname LIKE '%topology%' OR
        t.typname LIKE 'box%' OR
        t.typname = 'spheroid' OR
        t.typname = 'proj4text'
    )
ORDER BY 
    n.nspname, t.typname;

\echo ''
\echo '-- ================================================================================'
\echo '-- POSTGIS SYSTEM TABLES'
\echo '-- ================================================================================'

-- Get PostGIS system tables and their columns
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
    n.nspname IN ('public', 'topology')
    AND c.relkind = 'r'
    AND (
        c.relname LIKE '%geometry%' OR
        c.relname LIKE '%geography%' OR
        c.relname LIKE '%spatial%' OR
        c.relname LIKE '%topology%' OR
        c.relname LIKE '%raster%'
    )
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY 
    n.nspname, c.relname
ORDER BY 
    n.nspname, c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- POSTGIS EXTENSION DETAILS'
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
    e.extname LIKE 'postgis%'
ORDER BY 
    e.extname;

\echo ''
\echo '-- ================================================================================'
\echo '-- SPATIAL REFERENCE SYSTEMS SAMPLE'
\echo '-- ================================================================================'

-- Get a sample of spatial reference systems (if table exists)
SELECT COUNT(*) as total_srs FROM spatial_ref_sys;
SELECT srid, auth_name, auth_srid, srtext FROM spatial_ref_sys LIMIT 5;
