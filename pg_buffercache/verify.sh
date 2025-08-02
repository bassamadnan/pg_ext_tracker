#!/bin/bash
# Script to test pg_buffercache metrics compatibility across PostgreSQL versions

# Save the current directory
SCRIPT_DIR=$(pwd)

# Create directory for test results
mkdir -p pg_buffercache_feature_tests

# Create the universal compatibility test
cat > universal_buffercache_test.sql << 'EOF'
\echo '-- ================================================================================'
\echo '-- UNIVERSAL PG_BUFFERCACHE COMPATIBILITY TEST'
\echo '-- ================================================================================'

-- Basic version and extension info
\echo 'PostgreSQL and pg_buffercache Extension Information:'
SELECT version();
SELECT 
  extname,
  extversion,
  extrelocatable,
  extnamespace::regnamespace as schema_name
FROM pg_extension 
WHERE extname = 'pg_buffercache';

-- Check if pg_buffercache view is available (should work on all versions)
\echo 'Basic pg_buffercache view availability:'
SELECT EXISTS(
  SELECT 1 FROM information_schema.tables 
  WHERE table_schema = 'public' 
  AND table_name = 'pg_buffercache'
) as pg_buffercache_view_available;

-- Check available functions (version-specific)
\echo 'Available pg_buffercache functions:'
SELECT 
  p.proname as function_name,
  pg_get_function_arguments(p.oid) as function_args
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname LIKE 'pg\_buffercache%'
ORDER BY p.proname;
EOF

# Create version-specific feature tests based on our proposed metrics
cat > buffercache_metrics_tests.sql << 'EOF'
\echo '-- ================================================================================'
\echo '-- PG_BUFFERCACHE METRICS COMPATIBILITY TESTS'
\echo '-- ================================================================================'

-- Generate some activity to populate buffer cache
CREATE TABLE IF NOT EXISTS test_table (id int, data text);
INSERT INTO test_table SELECT generate_series(1,1000), 'test data ' || generate_series(1,1000);
SELECT COUNT(*) FROM test_table; -- Force some buffer activity

-- Test 1: Basic buffer utilization (should work on all versions 1.3+)
\echo 'TEST 1: Basic Buffer Utilization (All versions)'
\echo 'Testing basic buffer cache utilization metrics...'
DO $$
DECLARE
  total_buffers bigint;
  used_buffers bigint;
  dirty_buffers bigint;
  utilization_pct numeric;
BEGIN
  SELECT 
    COUNT(*),
    COUNT(*) FILTER (WHERE relfilenode IS NOT NULL),
    COUNT(*) FILTER (WHERE isdirty = true)
  INTO total_buffers, used_buffers, dirty_buffers
  FROM pg_buffercache;
  
  IF total_buffers > 0 THEN
    utilization_pct := ROUND((used_buffers::numeric / total_buffers::numeric) * 100, 2);
    RAISE NOTICE 'PASS: Buffer utilization - Total: %, Used: %, Dirty: %, Utilization: %', 
      total_buffers, used_buffers, dirty_buffers, utilization_pct || '%';
  ELSE
    RAISE NOTICE 'FAIL: No buffers found in pg_buffercache';
  END IF;
END $$;

-- Test 2: Top cached relations (should work on all versions 1.3+)
\echo 'TEST 2: Top Cached Relations (All versions)'
\echo 'Testing top cached relations metrics...'
DO $$
DECLARE
  relation_count int;
BEGIN
  SELECT COUNT(*) INTO relation_count
  FROM (
    SELECT 
      c.relname,
      COUNT(*) as buffer_count
    FROM pg_buffercache b
    JOIN pg_class c ON b.relfilenode = pg_relation_filenode(c.oid)
    WHERE b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
      AND b.relfilenode IS NOT NULL
    GROUP BY c.relname
    ORDER BY buffer_count DESC
    LIMIT 10
  ) top_relations;
  
  IF relation_count > 0 THEN
    RAISE NOTICE 'PASS: Top cached relations - Found % relations in cache', relation_count;
  ELSE
    RAISE NOTICE 'SKIP: No relations found in cache (empty buffer cache)';
  END IF;
END $$;

-- Test 3: Cache hit effectiveness using usage_count (should work on all versions 1.3+)
\echo 'TEST 3: Cache Hit Effectiveness (All versions)'
\echo 'Testing cache effectiveness based on usage_count...'
DO $$
DECLARE
  avg_usage_count numeric;
  high_usage_buffers bigint;
BEGIN
  SELECT 
    ROUND(AVG(usagecount), 2),
    COUNT(*) FILTER (WHERE usagecount >= 3)
  INTO avg_usage_count, high_usage_buffers
  FROM pg_buffercache
  WHERE relfilenode IS NOT NULL;
  
  IF avg_usage_count IS NOT NULL THEN
    RAISE NOTICE 'PASS: Cache effectiveness - Avg usage count: %, High usage buffers: %', 
      avg_usage_count, high_usage_buffers;
  ELSE
    RAISE NOTICE 'SKIP: No cached data to analyze usage patterns';
  END IF;
END $$;

-- Test 4: Buffer cache pressure indicators (should work on all versions 1.3+)
\echo 'TEST 4: Buffer Cache Pressure (All versions)'
\echo 'Testing cache pressure indicators...'
DO $$
DECLARE
  total_buffers bigint;
  used_buffers bigint;
  dirty_buffers bigint;
  pressure_level text;
BEGIN
  SELECT 
    COUNT(*),
    COUNT(*) FILTER (WHERE relfilenode IS NOT NULL),
    COUNT(*) FILTER (WHERE isdirty = true)
  INTO total_buffers, used_buffers, dirty_buffers
  FROM pg_buffercache;
  
  -- Simple pressure calculation
  IF (used_buffers::numeric / total_buffers::numeric) > 0.9 THEN
    pressure_level := 'HIGH';
  ELSIF (used_buffers::numeric / total_buffers::numeric) > 0.7 THEN
    pressure_level := 'MEDIUM';
  ELSE
    pressure_level := 'LOW';
  END IF;
  
  RAISE NOTICE 'PASS: Cache pressure - Level: %, Dirty ratio: %', 
    pressure_level, 
    ROUND((dirty_buffers::numeric / NULLIF(used_buffers, 0)::numeric) * 100, 2) || '%';
END $$;

-- Test 5: Enhanced summary functions (available from version 1.4+ / PG 16+)
\echo 'TEST 5: Enhanced Summary Functions (PG 16+ / Version 1.4+)'
\echo 'Testing pg_buffercache_summary and pg_buffercache_usage_counts...'
DO $$
BEGIN
  -- Test pg_buffercache_summary function
  IF EXISTS(
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'pg_buffercache_summary'
  ) THEN
    RAISE NOTICE 'PASS: pg_buffercache_summary function available';
    PERFORM buffers_used, buffers_unused, buffers_dirty, buffers_pinned, usagecount_avg
    FROM pg_buffercache_summary();
    RAISE NOTICE 'PASS: pg_buffercache_summary function executed successfully';
  ELSE
    RAISE NOTICE 'SKIP: pg_buffercache_summary not available (expected in pre-1.4/PG16)';
  END IF;
  
  -- Test pg_buffercache_usage_counts function
  IF EXISTS(
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'pg_buffercache_usage_counts'
  ) THEN
    RAISE NOTICE 'PASS: pg_buffercache_usage_counts function available';
    PERFORM usage_count, buffers, dirty, pinned
    FROM pg_buffercache_usage_counts();
    RAISE NOTICE 'PASS: pg_buffercache_usage_counts function executed successfully';
  ELSE
    RAISE NOTICE 'SKIP: pg_buffercache_usage_counts not available (expected in pre-1.4/PG16)';
  END IF;
END $$;

-- Test 6: Buffer eviction function (available from version 1.5+ / PG 17+)
\echo 'TEST 6: Buffer Eviction Function (PG 17+ / Version 1.5+)'
\echo 'Testing pg_buffercache_evict function...'
DO $$
BEGIN
  IF EXISTS(
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'pg_buffercache_evict'
  ) THEN
    RAISE NOTICE 'PASS: pg_buffercache_evict function available';
    -- Note: We don't actually call evict as it modifies buffer cache
    RAISE NOTICE 'PASS: pg_buffercache_evict function found (not executed for safety)';
  ELSE
    RAISE NOTICE 'SKIP: pg_buffercache_evict not available (expected in pre-1.5/PG17)';
  END IF;
END $$;

-- Test 7: Object type distribution (should work on all versions 1.3+)
\echo 'TEST 7: Object Type Distribution (All versions)'
\echo 'Testing buffer distribution by object type...'
DO $$
DECLARE
  table_buffers bigint;
  index_buffers bigint;
  toast_buffers bigint;
BEGIN
  -- This is a simplified test - in reality we'd need to join with pg_class
  SELECT 
    COUNT(*) FILTER (WHERE relfilenode IS NOT NULL),
    COUNT(*) FILTER (WHERE relfilenode IS NOT NULL AND relforknumber = 0), -- main fork
    COUNT(*) FILTER (WHERE relfilenode IS NOT NULL AND relforknumber != 0)  -- other forks
  INTO table_buffers, index_buffers, toast_buffers
  FROM pg_buffercache;
  
  RAISE NOTICE 'PASS: Object distribution - Total objects: %, Main fork: %, Other forks: %', 
    table_buffers, index_buffers, toast_buffers;
END $$;

-- Test 8: Sample actual metric queries (what pgexporter would use)
\echo 'TEST 8: Sample pgexporter-style Queries (All versions)'
\echo 'Testing actual metric queries that pgexporter would use...'

-- Buffer utilization percentage
\echo 'Buffer Utilization Query:'
SELECT 
  COUNT(*) as total_buffers,
  COUNT(*) FILTER (WHERE relfilenode IS NOT NULL) as used_buffers,
  ROUND(
    (COUNT(*) FILTER (WHERE relfilenode IS NOT NULL)::numeric / COUNT(*)::numeric) * 100, 2
  ) as utilization_pct
FROM pg_buffercache;

-- Dirty buffer percentage  
\echo 'Dirty Buffer Percentage Query:'
SELECT 
  COUNT(*) FILTER (WHERE isdirty = true) as dirty_buffers,
  COUNT(*) FILTER (WHERE relfilenode IS NOT NULL) as used_buffers,
  ROUND(
    (COUNT(*) FILTER (WHERE isdirty = true)::numeric / 
     NULLIF(COUNT(*) FILTER (WHERE relfilenode IS NOT NULL), 0)::numeric) * 100, 2
  ) as dirty_pct
FROM pg_buffercache;

-- Top 5 cached relations
\echo 'Top Cached Relations Query:'
SELECT 
  COALESCE(c.relname, 'unknown') as relation_name,
  COUNT(*) as buffer_count,
  ROUND((COUNT(*)::numeric / SUM(COUNT(*)) OVER ()) * 100, 2) as cache_pct
FROM pg_buffercache b
LEFT JOIN pg_class c ON (
  b.relfilenode = pg_relation_filenode(c.oid) 
  AND b.reldatabase = (SELECT oid FROM pg_database WHERE datname = current_database())
)
WHERE b.relfilenode IS NOT NULL
GROUP BY c.relname
ORDER BY buffer_count DESC
LIMIT 5;

-- Cleanup test table
DROP TABLE IF EXISTS test_table;

\echo 'All metric compatibility tests completed!'
EOF

echo "Created pg_buffercache feature compatibility test scripts"

# Define PostgreSQL versions to test (13-17)
PG_VERSIONS=("13" "14" "15" "16" "17")

# For each PostgreSQL version
for pg_version in "${PG_VERSIONS[@]}"; do
    echo ""
    echo "========================================================================"
    echo "Testing pg_buffercache metrics for PostgreSQL $pg_version"
    echo "========================================================================"
    
    # Pull Docker image
    echo "Pulling Docker image for PostgreSQL $pg_version..."
    docker pull postgres:$pg_version
    
    # Start PostgreSQL container
    CONTAINER_NAME="pg_buffercache_metrics_test_${pg_version}"
    echo "Starting PostgreSQL container: $CONTAINER_NAME..."
    docker run --name $CONTAINER_NAME -e POSTGRES_PASSWORD=password -d postgres:$pg_version
    
    # Wait for PostgreSQL to start
    echo "Waiting for PostgreSQL to start..."
    sleep 10
    
    # Install pg_buffercache extension
    echo "Installing pg_buffercache extension..."
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -c 'CREATE EXTENSION pg_buffercache;'"
    
    # Run universal compatibility tests
    echo "Running universal compatibility tests..."
    docker cp universal_buffercache_test.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/universal_buffercache_test.sql" > pg_buffercache_feature_tests/universal_pg${pg_version}.out 2>&1
    
    # Run metrics-specific feature tests
    echo "Running metrics compatibility tests..."
    docker cp buffercache_metrics_tests.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/buffercache_metrics_tests.sql" > pg_buffercache_feature_tests/metrics_pg${pg_version}.out 2>&1
    
    # Stop and remove container
    docker stop $CONTAINER_NAME >/dev/null 2>&1
    docker rm $CONTAINER_NAME >/dev/null 2>&1
    
    echo "Metrics tests completed for PostgreSQL $pg_version"
done

echo ""
echo "========================================================================"
echo "pg_buffercache metrics compatibility testing complete!"
echo "========================================================================"
echo "Results are available in the pg_buffercache_feature_tests directory:"
ls -l pg_buffercache_feature_tests/

echo ""
echo "Summary commands:"
echo "- View universal compatibility: cat pg_buffercache_feature_tests/universal_pg*.out"
echo "- View metrics test results: cat pg_buffercache_feature_tests/metrics_pg*.out"
echo "- Search for PASS/SKIP/FAIL: grep -H 'PASS\\|SKIP\\|FAIL' pg_buffercache_feature_tests/metrics_pg*.out"
echo ""
echo "Expected results by version:"
echo "- PG 13-15 (v1.3): Basic metrics should PASS, enhanced functions should SKIP"
echo "- PG 16 (v1.4): All metrics should PASS, evict function should SKIP"  
echo "- PG 17 (v1.5): All metrics and functions should PASS"
echo ""
echo "Each test shows:"
echo "- PASS: Metric works as expected"
echo "- SKIP: Feature not available (expected for version)" 
echo "- FAIL: Metric should work but doesn't (needs investigation)"

# Clean up temporary files
rm -f universal_buffercache_test.sql buffercache_metrics_tests.sql