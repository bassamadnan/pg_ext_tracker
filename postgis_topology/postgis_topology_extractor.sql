\echo '-- PostgreSQL and PostGIS Topology Version Information'
SELECT version();
SELECT extname, extversion FROM pg_extension WHERE extname LIKE '%topology%' OR extname = 'postgis';
\echo ''

-- Check if topology extension is available and installed
\echo 'PostGIS Topology Extension Status:'
SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'postgis_topology') as topology_installed;

-- Only proceed if topology extension is installed
\echo 'Installing PostGIS Topology extension if not present...'
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Verify installation
SELECT extname, extversion FROM pg_extension WHERE extname = 'postgis_topology';

-- formatting to check diff
\pset format unaligned
\pset tuples_only off
\pset footer off

\echo '-- ================================================================================'
\echo '-- TOPOLOGY SCHEMA INFORMATION'
\echo '-- ================================================================================'

-- List all schemas related to topology
\echo 'Topology Related Schemas:'
SELECT nspname as schema_name
FROM pg_namespace 
WHERE nspname LIKE '%topology%' OR nspname = 'topology'
ORDER BY nspname;

\echo '-- ================================================================================'
\echo '-- TOPOLOGY VIEW COLUMN INFORMATION'
\echo '-- ================================================================================'

-- Get all topology-related views from topology schema
SELECT 
    n.nspname AS schema_name,
    c.relname AS view_name,
    STRING_AGG(a.attname, ', ' ORDER BY a.attnum) AS columns
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_attribute a ON c.oid = a.attrelid
WHERE 
    n.nspname = 'topology'
    AND c.relkind = 'v'
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY 
    n.nspname, c.relname
ORDER BY 
    n.nspname, c.relname;

\echo '-- ================================================================================'
\echo '-- TOPOLOGY TABLE INFORMATION'
\echo '-- ================================================================================'

-- Get all topology-related tables from topology schema
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
    n.nspname = 'topology'
    AND c.relkind = 'r'
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY 
    n.nspname, c.relname
ORDER BY 
    n.nspname, c.relname;

\echo '-- ================================================================================'
\echo '-- TOPOLOGY FUNCTION INFORMATION'
\echo '-- ================================================================================'

-- Get all topology-related functions
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
    n.nspname = 'topology'
    OR (n.nspname = 'public' AND (
        p.proname LIKE '%topology%' OR
        p.proname LIKE 'addtopogeometry%' OR
        p.proname LIKE 'createtopology%' OR
        p.proname LIKE 'droptopology%' OR
        p.proname LIKE 'st_createtopo%' OR
        p.proname LIKE 'st_inittopo%' OR
        p.proname LIKE 'st_addiso%' OR
        p.proname LIKE 'validatetopology%'
    ))
ORDER BY 
    n.nspname, p.proname;

\echo '-- ================================================================================'
\echo '-- TOPOLOGY DATA TYPES'
\echo '-- ================================================================================'

-- Get topology-specific data types
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
    n.nspname = 'topology'
    OR (n.nspname = 'public' AND (
        t.typname LIKE '%topology%' OR
        t.typname LIKE '%topogeometry%' OR
        t.typname = 'validatetopology_returntype'
    ))
ORDER BY 
    n.nspname, t.typname;

\echo '-- ================================================================================'
\echo '-- TOPOLOGY VIEW DEFINITIONS'
\echo '-- ================================================================================'

-- Get view definitions for topology views
\pset fieldsep '|\n'
SELECT 
    n.nspname AS schema_name,
    c.relname AS view_name,
    pg_get_viewdef(c.oid, true) AS definition
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE 
    n.nspname = 'topology'
    AND c.relkind = 'v'
ORDER BY 
    n.nspname, c.relname;

\echo '-- ================================================================================'
\echo '-- TOPOLOGY SYSTEM CATALOG INFORMATION'
\echo '-- ================================================================================'

-- Check if topology catalog tables exist and get basic info
\pset fieldsep ' | '
\pset format aligned

\echo 'Topology Catalog Tables:'
SELECT 
    schemaname,
    tablename,
    tableowner
FROM pg_tables 
WHERE schemaname = 'topology'
ORDER BY tablename;

\echo 'Topology Views:'
SELECT 
    schemaname,
    viewname,
    viewowner
FROM pg_views 
WHERE schemaname = 'topology'
ORDER BY viewname;

\echo '-- ================================================================================'
\echo '-- TOPOLOGY EXTENSION DETAILS'
\echo '-- ================================================================================'

-- Get topology extension details
SELECT 
    e.extname,
    e.extversion,
    e.extrelocatable,
    n.nspname AS schema_name,
    e.extconfig as config_tables,
    e.extcondition as conditions
FROM 
    pg_extension e
    JOIN pg_namespace n ON e.extnamespace = n.oid
WHERE 
    e.extname = 'postgis_topology'
ORDER BY 
    e.extname;

\echo '-- ================================================================================'
\echo '-- TOPOLOGY SAMPLE DATA (if any topologies exist)'
\echo '-- ================================================================================'

-- Check if any topologies are defined
\echo 'Existing Topologies:'
DO $$
BEGIN
    IF EXISTS(SELECT 1 FROM information_schema.tables WHERE table_schema = 'topology' AND table_name = 'topology') THEN
        PERFORM COUNT(*) FROM topology.topology;
        RAISE NOTICE 'Topology catalog table exists and accessible';
    ELSE
        RAISE NOTICE 'No topology catalog table found or not accessible';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error accessing topology catalog: %', SQLERRM;
END $$;

-- Try to query topology catalog if it exists
SELECT 
    id,
    name,
    srid,
    precision,
    hasz
FROM topology.topology
LIMIT 5;

\echo 'Done with topology extraction.'
