\echo '-- ================================================================================'
\echo '-- POSTGIS CORE MONITORING COMPATIBILITY TEST'
\echo '-- ================================================================================'

-- Basic version and extension info
\echo 'PostGIS Core Extension Information:'
SELECT 
  extname,
  extversion,
  extrelocatable,
  extnamespace::regnamespace as schema_name
FROM pg_extension 
WHERE extname = 'postgis'
ORDER BY extname;

-- PostGIS version details (for monitoring dashboards)
\echo 'PostGIS Version Details:'
SELECT postgis_version() as postgis_version;
SELECT postgis_lib_version() as postgis_lib_version;

\echo '-- ================================================================================'
\echo '-- SPATIAL TABLE MONITORING QUERIES'
\echo '-- ================================================================================'

-- Count of tables with geometry columns (key metric for PostGIS monitoring)
\echo 'Tables with Geometry Columns:'
SELECT COUNT(*) as tables_with_geometry
FROM geometry_columns;

-- Count of tables with geography columns  
\echo 'Tables with Geography Columns:'
SELECT COUNT(*) as tables_with_geography
FROM geography_columns;

-- Spatial reference systems count (monitoring SRID usage)
\echo 'Spatial Reference Systems Count:'
SELECT COUNT(*) as total_srs FROM spatial_ref_sys;

-- Most commonly used SRIDs (useful for performance monitoring)
\echo 'Most Common SRIDs in Geometry Columns:'
SELECT 
  srid,
  COUNT(*) as usage_count
FROM geometry_columns 
GROUP BY srid 
ORDER BY usage_count DESC 
LIMIT 10;

\echo '-- ================================================================================'
\echo '-- POSTGIS PERFORMANCE MONITORING QUERIES'  
\echo '-- ================================================================================'

-- Geometry column statistics (for index usage monitoring)
\echo 'Geometry Column Details:'
SELECT 
  f_table_schema,
  f_table_name,
  f_geometry_column,
  coord_dimension,
  srid,
  type as geometry_type
FROM geometry_columns
ORDER BY f_table_schema, f_table_name
LIMIT 20;

-- Check for spatial indexes (critical for PostGIS performance)
\echo 'Spatial Indexes Check:'
SELECT 
  schemaname,
  tablename,
  indexname,
  indexdef
FROM pg_indexes 
WHERE indexdef LIKE '%gist%' 
  AND (indexdef LIKE '%geometry%' OR indexdef LIKE '%geography%')
ORDER BY schemaname, tablename
LIMIT 10;

-- Count spatial indexes for monitoring
\echo 'Spatial Index Count:'
SELECT COUNT(*) as spatial_index_count
FROM pg_indexes 
WHERE indexdef LIKE '%gist%' 
  AND (indexdef LIKE '%geometry%' OR indexdef LIKE '%geography%');
