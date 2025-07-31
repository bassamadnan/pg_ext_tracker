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
