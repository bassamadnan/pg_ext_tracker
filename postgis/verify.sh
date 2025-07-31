#!/bin/bash
# Script to test PostGIS CORE monitoring queries compatibility across PostgreSQL versions
# Focus on basic PostGIS extension only (no topology, no raster)

# Save the current directory
SCRIPT_DIR=$(pwd)

# Create directory for test results
mkdir -p postgis_core_tests

# Create the core PostGIS monitoring test
cat > postgis_core_test.sql << 'EOF'
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
EOF

# Create version-specific PostGIS core function tests
cat > postgis_core_function_tests.sql << 'EOF'
\echo '-- ================================================================================'
\echo '-- POSTGIS CORE FUNCTION TESTS'
\echo '-- ================================================================================'

-- Test 1: Basic geometry functions (should work on all versions)
\echo 'TEST 1: Basic Geometry Functions'
\echo 'Testing basic geometry creation and measurement...'
DO $$
DECLARE
  test_geom geometry;
  test_area numeric;
BEGIN
  -- Create a simple polygon
  test_geom := ST_GeomFromText('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 4326);
  test_area := ST_Area(test_geom);
  
  IF test_area > 0 THEN
    RAISE NOTICE 'PASS: Basic geometry functions work (area: %)', test_area;
  ELSE
    RAISE NOTICE 'FAIL: Basic geometry functions failed';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'FAIL: Basic geometry functions failed with error: %', SQLERRM;
END $$;

-- Test 2: Geography functions (should work on all modern versions)
\echo 'TEST 2: Geography Functions'
\echo 'Testing geography calculations...'
DO $$
DECLARE
  test_geog geography;
  test_distance numeric;
BEGIN
  -- Create geography points
  test_geog := ST_GeogFromText('POINT(-122.4194 37.7749)'); -- San Francisco
  test_distance := ST_Distance(test_geog, ST_GeogFromText('POINT(-74.0060 40.7128)')); -- New York
  
  IF test_distance > 0 THEN
    RAISE NOTICE 'PASS: Geography functions work (distance: % meters)', round(test_distance);
  ELSE
    RAISE NOTICE 'FAIL: Geography functions failed';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'FAIL: Geography functions failed with error: %', SQLERRM;
END $$;

-- Test 3: Spatial indexing support
\echo 'TEST 3: Spatial Index Support'
\echo 'Testing GIST index creation...'
DO $$
BEGIN
  -- Create a test table with geometry column
  DROP TABLE IF EXISTS test_spatial_table;
  CREATE TEMP TABLE test_spatial_table (
    id serial PRIMARY KEY,
    geom geometry(POINT, 4326)
  );
  
  -- Create spatial index
  CREATE INDEX idx_test_spatial_geom ON test_spatial_table USING GIST (geom);
  
  RAISE NOTICE 'PASS: Spatial index creation successful';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'FAIL: Spatial index creation failed with error: %', SQLERRM;
END $$;

-- Test 4: Geometry validation functions
\echo 'TEST 4: Geometry Validation'
\echo 'Testing geometry validation functions...'
DO $$
DECLARE
  valid_geom geometry;
BEGIN
  valid_geom := ST_GeomFromText('POLYGON((0 0, 1 0, 1 1, 0 1, 0 0))', 4326);
  
  IF ST_IsValid(valid_geom) THEN
    RAISE NOTICE 'PASS: Geometry validation functions work';
  ELSE
    RAISE NOTICE 'FAIL: Valid geometry reported as invalid';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'FAIL: Geometry validation failed with error: %', SQLERRM;
END $$;

-- Test 5: PostGIS system table access
\echo 'TEST 5: System Tables Access'
\echo 'Testing access to PostGIS system tables...'
DO $$
DECLARE
  srs_count integer;
BEGIN
  SELECT COUNT(*) INTO srs_count FROM spatial_ref_sys WHERE srid = 4326;
  
  IF srs_count > 0 THEN
    RAISE NOTICE 'PASS: System tables accessible (WGS84 found)';
  ELSE
    RAISE NOTICE 'WARN: WGS84 not found in spatial_ref_sys';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'FAIL: System tables access failed with error: %', SQLERRM;
END $$;

-- Test 6: Measurement functions for monitoring
\echo 'TEST 6: Measurement Functions for Monitoring'
\echo 'Testing functions useful for spatial data monitoring...'
DO $$
DECLARE
  test_geom geometry;
  bbox_area numeric;
  geom_length numeric;
BEGIN
  test_geom := ST_GeomFromText('LINESTRING(0 0, 1 0, 1 1)', 4326);
  bbox_area := ST_Area(ST_Envelope(test_geom));
  geom_length := ST_Length(test_geom);
  
  IF bbox_area >= 0 AND geom_length > 0 THEN
    RAISE NOTICE 'PASS: Measurement functions work (length: %, bbox_area: %)', geom_length, bbox_area;
  ELSE
    RAISE NOTICE 'FAIL: Measurement functions returned unexpected values';
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'FAIL: Measurement functions failed with error: %', SQLERRM;
END $$;

-- Test 7: PostGIS Extension Health Check
\echo 'TEST 7: Extension Health Check'
\echo 'Testing PostGIS extension installation and health...'
DO $$
DECLARE
  ext_count integer;
  func_count integer;
BEGIN
  -- Check if extension is properly installed
  SELECT COUNT(*) INTO ext_count FROM pg_extension WHERE extname = 'postgis';
  
  -- Check if core functions are available
  SELECT COUNT(*) INTO func_count 
  FROM pg_proc p 
  JOIN pg_namespace n ON p.pronamespace = n.oid 
  WHERE p.proname LIKE 'st_%' AND n.nspname = 'public';
  
  IF ext_count > 0 AND func_count > 100 THEN
    RAISE NOTICE 'PASS: PostGIS extension healthy (% functions available)', func_count;
  ELSE
    RAISE NOTICE 'WARN: PostGIS extension issues (ext: %, functions: %)', ext_count, func_count;
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'FAIL: Extension health check failed with error: %', SQLERRM;
END $$;
EOF

echo "Created PostGIS core monitoring test scripts"

# Define PostgreSQL versions to test (using PostGIS Docker images)
PG_VERSIONS=("13" "14" "15" "16" "17")

# For each PostgreSQL version
for pg_version in "${PG_VERSIONS[@]}"; do
    echo ""
    echo "========================================================================"
    echo "Testing PostGIS CORE monitoring queries for PostgreSQL $pg_version"
    echo "========================================================================"
    
    # Start PostGIS container
    CONTAINER_NAME="postgis_core_test_pg${pg_version}"
    echo "Starting PostGIS container: $CONTAINER_NAME..."
    docker run --name $CONTAINER_NAME -e POSTGRES_PASSWORD=password -d postgis/postgis:${pg_version}-3.4
    
    # Wait for PostgreSQL to start
    echo "Waiting for PostgreSQL to start..."
    sleep 15
    
    # Run core monitoring compatibility tests
    echo "Running PostGIS core monitoring tests..."
    docker cp postgis_core_test.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/postgis_core_test.sql" > postgis_core_tests/core_monitoring_pg${pg_version}.out 2>&1
    
    # Run core function tests
    echo "Running PostGIS core function tests..."
    docker cp postgis_core_function_tests.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/postgis_core_function_tests.sql" > postgis_core_tests/core_functions_pg${pg_version}.out 2>&1
    
    # Stop and remove container
    docker stop $CONTAINER_NAME >/dev/null 2>&1
    docker rm $CONTAINER_NAME >/dev/null 2>&1
    
    echo "PostGIS core tests completed for PostgreSQL $pg_version"
done

echo ""
echo "========================================================================"
echo "PostGIS CORE monitoring compatibility testing complete!"
echo "========================================================================"
echo "Results are available in the postgis_core_tests directory:"
ls -l postgis_core_tests/

echo ""
echo "Summary commands:"
echo "- View core monitoring queries: cat postgis_core_tests/core_monitoring_*.out"
echo "- View function tests: cat postgis_core_tests/core_functions_*.out"
echo "- Search for PASS/SKIP/FAIL: grep -H 'PASS\\|SKIP\\|FAIL' postgis_core_tests/core_functions_*.out"
echo ""
echo "Key PostGIS CORE monitoring metrics:"
echo "✓ Extension version and status"
echo "✓ Geometry/geography table counts"
echo "✓ SRID usage statistics"
echo "✓ Spatial index counts and details"
echo "✓ System table accessibility"
echo "✓ Core spatial function availability"
echo ""
echo "These are the essential queries for postgres_exporter PostGIS monitoring:"
echo "1. SELECT COUNT(*) FROM geometry_columns;"
echo "2. SELECT COUNT(*) FROM geography_columns;"
echo "3. SELECT COUNT(*) FROM spatial_ref_sys;"
echo "4. SELECT COUNT(*) FROM pg_indexes WHERE indexdef LIKE '%gist%';"
echo "5. SELECT postgis_version();"
echo ""
echo "Clean up:"
echo "rm -rf postgis_core_tests/ postgis_core_test.sql postgis_core_function_tests.sql"
echo ""
echo "Done!"