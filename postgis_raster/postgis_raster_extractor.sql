\echo '-- PostgreSQL and PostGIS Raster Version Information'
SELECT version();
SELECT extname, extversion FROM pg_extension WHERE extname LIKE '%raster%' OR extname = 'postgis';
\echo ''

-- Check if raster extension is available and installed
\echo 'PostGIS Raster Extension Status:'
SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = 'postgis_raster') as raster_installed;

-- Only proceed if raster extension is available, try to install
\echo 'Installing PostGIS Raster extension if not present...'
CREATE EXTENSION IF NOT EXISTS postgis_raster;

-- Verify installation
SELECT extname, extversion FROM pg_extension WHERE extname = 'postgis_raster';

-- formatting to check diff
\pset format unaligned
\pset tuples_only off
\pset footer off

\echo '-- ================================================================================'
\echo '-- RASTER VIEW COLUMN INFORMATION'
\echo '-- ================================================================================'

-- Get all raster-related views from public schema
SELECT 
    n.nspname AS schema_name,
    c.relname AS view_name,
    STRING_AGG(a.attname, ', ' ORDER BY a.attnum) AS columns
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_attribute a ON c.oid = a.attrelid
WHERE 
    n.nspname = 'public'
    AND c.relkind = 'v'
    AND (
        c.relname LIKE '%raster%' OR
        c.relname = 'raster_columns' OR
        c.relname = 'raster_overviews'
    )
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY 
    n.nspname, c.relname
ORDER BY 
    n.nspname, c.relname;

\echo '-- ================================================================================'
\echo '-- RASTER TABLE INFORMATION'
\echo '-- ================================================================================'

-- Get all raster-related tables from public schema
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
    n.nspname = 'public'
    AND c.relkind = 'r'
    AND (
        c.relname LIKE '%raster%'
    )
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY 
    n.nspname, c.relname
ORDER BY 
    n.nspname, c.relname;

\echo '-- ================================================================================'
\echo '-- RASTER FUNCTION INFORMATION'
\echo '-- ================================================================================'

-- Get all raster-related functions (limited to avoid overwhelming output)
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
    n.nspname = 'public'
    AND (
        p.proname LIKE 'st_%raster%' OR
        p.proname LIKE 'st_make%raster%' OR
        p.proname LIKE 'st_addrasterconstraints%' OR
        p.proname LIKE 'st_droprasterconstraints%' OR
        p.proname LIKE 'st_raster%' OR
        p.proname LIKE '%_raster' OR
        p.proname IN ('st_band', 'st_numbands', 'st_hasnoband', 'st_bandnodatavalue',
                      'st_setbandnodatavalue', 'st_bandisnodata', 'st_bandpath',
                      'st_bandfilesize', 'st_bandfiletimestamp', 'st_pixelwidth',
                      'st_pixelheight', 'st_upperleftx', 'st_upperlefty',
                      'st_width', 'st_height', 'st_scalex', 'st_scaley',
                      'st_skewx', 'st_skewy', 'st_srid', 'st_rotation')
    )
ORDER BY 
    n.nspname, p.proname
LIMIT 100;

\echo '-- ================================================================================'
\echo '-- RASTER DATA TYPES'
\echo '-- ================================================================================'

-- Get raster-specific data types
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
    n.nspname = 'public'
    AND (
        t.typname = 'raster' OR
        t.typname LIKE '%raster%' OR
        t.typname = 'rastbandarg' OR
        t.typname = 'reclassarg' OR
        t.typname = 'unionarg' OR
        t.typname LIKE 'addbandarg%'
    )
ORDER BY 
    n.nspname, t.typname;

\echo '-- ================================================================================'
\echo '-- RASTER VIEW DEFINITIONS'
\echo '-- ================================================================================'

-- Get view definitions for raster views
\pset fieldsep '|\n'
SELECT 
    n.nspname AS schema_name,
    c.relname AS view_name,
    pg_get_viewdef(c.oid, true) AS definition
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE 
    n.nspname = 'public'
    AND c.relkind = 'v'
    AND (
        c.relname LIKE '%raster%' OR
        c.relname = 'raster_columns' OR
        c.relname = 'raster_overviews'
    )
ORDER BY 
    n.nspname, c.relname;

\echo '-- ================================================================================'
\echo '-- RASTER SYSTEM CATALOG INFORMATION'
\echo '-- ================================================================================'

-- Check if raster catalog views exist and get basic info
\pset fieldsep ' | '
\pset format aligned

\echo 'Raster Catalog Views:'
SELECT 
    schemaname,
    viewname,
    viewowner
FROM pg_views 
WHERE schemaname = 'public' 
  AND (viewname LIKE '%raster%' OR viewname = 'raster_columns' OR viewname = 'raster_overviews')
ORDER BY viewname;

\echo '-- ================================================================================'
\echo '-- RASTER EXTENSION DETAILS'
\echo '-- ================================================================================'

-- Get raster extension details
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
    e.extname = 'postgis_raster'
ORDER BY 
    e.extname;

\echo '-- ================================================================================'
\echo '-- RASTER SAMPLE DATA (if any raster tables exist)'
\echo '-- ================================================================================'

-- Check if raster_columns view is accessible
\echo 'Raster Columns Information:'
DO $$
BEGIN
    IF EXISTS(SELECT 1 FROM information_schema.views WHERE table_schema = 'public' AND table_name = 'raster_columns') THEN
        PERFORM COUNT(*) FROM raster_columns;
        RAISE NOTICE 'Raster columns view exists and accessible';
    ELSE
        RAISE NOTICE 'No raster_columns view found or not accessible';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error accessing raster_columns view: %', SQLERRM;
END $$;

-- Try to query raster_columns if it exists
SELECT 
    r_table_catalog,
    r_table_schema,
    r_table_name,
    r_raster_column,
    srid,
    scale_x,
    scale_y,
    blocksize_x,
    blocksize_y,
    same_alignment,
    regular_blocking,
    num_bands,
    pixel_types,
    nodata_values,
    out_db,
    extent
FROM raster_columns
LIMIT 5;

-- Check if raster_overviews view exists
\echo 'Raster Overviews Information:'
DO $$
BEGIN
    IF EXISTS(SELECT 1 FROM information_schema.views WHERE table_schema = 'public' AND table_name = 'raster_overviews') THEN
        PERFORM COUNT(*) FROM raster_overviews;
        RAISE NOTICE 'Raster overviews view exists and accessible';
    ELSE
        RAISE NOTICE 'No raster_overviews view found';
    END IF;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error accessing raster_overviews view: %', SQLERRM;
END $$;

-- Try to query raster_overviews if it exists
SELECT 
    o_table_catalog,
    o_table_schema,
    o_table_name,
    o_raster_column,
    r_table_catalog,
    r_table_schema,
    r_table_name,
    r_raster_column,
    overview_factor
FROM raster_overviews
LIMIT 5;

\echo 'Done with raster extraction.'
