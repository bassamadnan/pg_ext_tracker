#!/bin/bash
# Script to test TimescaleDB feature compatibility across versions

# Save the current directory
SCRIPT_DIR=$(pwd)

# Create directory for test results
mkdir -p timescale_feature_tests

# Create the universal compatibility test (works on all versions)
cat > universal_test.sql << 'EOF'
\echo '-- ================================================================================'
\echo '-- UNIVERSAL COMPATIBILITY TEST'
\echo '-- ================================================================================'

-- Basic version and extension info
\echo 'TimescaleDB Extension Information:'
SELECT 
  extname,
  extversion,
  extrelocatable,
  extnamespace::regnamespace as schema_name
FROM pg_extension 
WHERE extname = 'timescaledb';

-- Check available information schema views
\echo 'Available TimescaleDB Information Views:'
SELECT 
  schemaname,
  viewname
FROM pg_views 
WHERE schemaname = 'timescaledb_information'
ORDER BY viewname;

-- Basic hypertable count (should work on all versions)
\echo 'Basic Hypertable Count:'
SELECT COUNT(*) as total_hypertables
FROM timescaledb_information.hypertables;

-- Basic job count (should work on all versions)  
\echo 'Basic Job Count:'
SELECT COUNT(*) as total_jobs
FROM timescaledb_information.job_stats;

-- Check which version-specific views are available
\echo 'Version-specific view availability:'
SELECT 
  'job_history' as view_name,
  EXISTS(
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'timescaledb_information' 
    AND table_name = 'job_history'
  ) as available
UNION ALL
SELECT 
  'data_nodes' as view_name,
  EXISTS(
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'timescaledb_information' 
    AND table_name = 'data_nodes'
  ) as available
UNION ALL
SELECT 
  'hypertable_columnstore_settings' as view_name,
  EXISTS(
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'timescaledb_information' 
    AND table_name = 'hypertable_columnstore_settings'
  ) as available;

-- Check if chunk_creation_time column exists (2.13.0+)
\echo 'Chunk creation time availability:'
SELECT EXISTS(
  SELECT 1 FROM information_schema.columns 
  WHERE table_schema = 'timescaledb_information' 
    AND table_name = 'chunks'
    AND column_name = 'chunk_creation_time'
) as chunk_creation_time_available;

-- Check if primary_dimension columns exist (2.20.0+)
\echo 'Primary dimension info availability:'
SELECT EXISTS(
  SELECT 1 FROM information_schema.columns 
  WHERE table_schema = 'timescaledb_information' 
    AND table_name = 'hypertables'
    AND column_name = 'primary_dimension'
) as primary_dimension_available;

-- Check if is_distributed column exists (removed in 2.14.0)
\echo 'Distributed features availability:'
SELECT EXISTS(
  SELECT 1 FROM information_schema.columns 
  WHERE table_schema = 'timescaledb_information' 
    AND table_name = 'hypertables'
    AND column_name = 'is_distributed'
) as distributed_features_available;
EOF

# Create version-specific feature tests
cat > version_specific_tests.sql << 'EOF'
\echo '-- ================================================================================'
\echo '-- VERSION-SPECIFIC FEATURE TESTS'
\echo '-- ================================================================================'

-- Test 1: Distributed features (available until 2.14.0)
\echo 'TEST 1: Distributed Features (Pre-2.14.0)'
\echo 'Testing if distributed hypertable features are available...'
DO $$
BEGIN
  IF EXISTS(
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'timescaledb_information' 
      AND table_name = 'hypertables'
      AND column_name = 'is_distributed'
  ) THEN
    RAISE NOTICE 'PASS: Distributed features available';
    PERFORM COUNT(*) FILTER (WHERE is_distributed = true) FROM timescaledb_information.hypertables;
  ELSE
    RAISE NOTICE 'SKIP: Distributed features not available (expected in 2.14.0+)';
  END IF;
END $$;

-- Test 2: Chunk creation time (available from 2.13.0+)
\echo 'TEST 2: Chunk Creation Time (2.13.0+)'
\echo 'Testing if chunk_creation_time is available...'
DO $$
BEGIN
  IF EXISTS(
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'timescaledb_information' 
      AND table_name = 'chunks'
      AND column_name = 'chunk_creation_time'
  ) THEN
    RAISE NOTICE 'PASS: Chunk creation time available';
    PERFORM AVG(EXTRACT(EPOCH FROM (CURRENT_TIMESTAMP - chunk_creation_time))/86400) FROM timescaledb_information.chunks;
  ELSE
    RAISE NOTICE 'SKIP: Chunk creation time not available (expected in pre-2.13.0)';
  END IF;
END $$;

-- Test 3: Job history (available from 2.15.0+)
\echo 'TEST 3: Job History (2.15.0+)'
\echo 'Testing if job_history view is available...'
DO $$
BEGIN
  IF EXISTS(
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'timescaledb_information' 
      AND table_name = 'job_history'
  ) THEN
    RAISE NOTICE 'PASS: Job history available';
    PERFORM COUNT(*) FROM timescaledb_information.job_history;
  ELSE
    RAISE NOTICE 'SKIP: Job history not available (expected in pre-2.15.0)';
  END IF;
END $$;

-- Test 4: Data nodes (removed in 2.14.0)
\echo 'TEST 4: Data Nodes (Pre-2.14.0)'
\echo 'Testing if data_nodes view is available...'
DO $$
BEGIN
  IF EXISTS(
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'timescaledb_information' 
      AND table_name = 'data_nodes'
  ) THEN
    RAISE NOTICE 'PASS: Data nodes available';
    PERFORM COUNT(*) FROM timescaledb_information.data_nodes;
  ELSE
    RAISE NOTICE 'SKIP: Data nodes not available (expected in 2.14.0+)';
  END IF;
END $$;

-- Test 5: Columnstore settings (available from 2.18.0+)
\echo 'TEST 5: Columnstore Settings (2.18.0+)'
\echo 'Testing if columnstore settings are available...'
DO $$
BEGIN
  IF EXISTS(
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = 'timescaledb_information' 
      AND table_name = 'hypertable_columnstore_settings'
  ) THEN
    RAISE NOTICE 'PASS: Columnstore settings available';
    PERFORM COUNT(*) FROM timescaledb_information.hypertable_columnstore_settings;
  ELSE
    RAISE NOTICE 'SKIP: Columnstore settings not available (expected in pre-2.18.0)';
  END IF;
END $$;

-- Test 6: Primary dimension info (available from 2.20.0+)
\echo 'TEST 6: Primary Dimension Info (2.20.0+)'
\echo 'Testing if primary_dimension info is available...'
DO $$
BEGIN
  IF EXISTS(
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'timescaledb_information' 
      AND table_name = 'hypertables'
      AND column_name = 'primary_dimension'
  ) THEN
    RAISE NOTICE 'PASS: Primary dimension info available';
    PERFORM COUNT(DISTINCT primary_dimension_type) FROM timescaledb_information.hypertables;
  ELSE
    RAISE NOTICE 'SKIP: Primary dimension info not available (expected in pre-2.20.0)';
  END IF;
END $$;

-- Test 7: SQL error codes in job_errors (available from 2.15.0+)
\echo 'TEST 7: SQL Error Codes in Job Errors (2.15.0+)'
\echo 'Testing if sqlerrcode is available in job_errors...'
DO $$
BEGIN
  IF EXISTS(
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'timescaledb_information' 
      AND table_name = 'job_errors'
      AND column_name = 'sqlerrcode'
  ) THEN
    RAISE NOTICE 'PASS: SQL error codes available in job_errors';
  ELSE
    RAISE NOTICE 'SKIP: SQL error codes not available in job_errors (expected in pre-2.15.0)';
  END IF;
END $$;
EOF

echo "Created feature compatibility test scripts"

# Define TimescaleDB versions to test
TIMESCALE_VERSIONS=(
    "2.15.3-pg13"    # PostgreSQL 13 final version
    "2.19.3-pg14"    # PostgreSQL 14 final version
    "2.20.3-pg15"    # PostgreSQL 15 current
    "2.20.3-pg16"    # PostgreSQL 16 current
    "2.20.3-pg17"    # PostgreSQL 17 current
)

# For each TimescaleDB version
for version in "${TIMESCALE_VERSIONS[@]}"; do
    echo ""
    echo "========================================================================"
    echo "Testing TimescaleDB features for version $version"
    echo "========================================================================"
    
    # Start TimescaleDB container
    CONTAINER_NAME="timescale_feature_test_${version//[-.]/_}"
    echo "Starting TimescaleDB container: $CONTAINER_NAME..."
    docker run --name $CONTAINER_NAME -e POSTGRES_PASSWORD=password -d timescale/timescaledb:$version
    
    # Wait for PostgreSQL to start
    echo "Waiting for TimescaleDB to start..."
    sleep 15
    
    # Run universal compatibility tests
    echo "Running universal compatibility tests..."
    docker cp universal_test.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/universal_test.sql" > timescale_feature_tests/universal_${version//[-.]/_}.out 2>&1
    
    # Run version-specific feature tests
    echo "Running version-specific feature tests..."
    docker cp version_specific_tests.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/version_specific_tests.sql" > timescale_feature_tests/features_${version//[-.]/_}.out 2>&1
    
    # Stop and remove container
    docker stop $CONTAINER_NAME >/dev/null 2>&1
    docker rm $CONTAINER_NAME >/dev/null 2>&1
    
    echo "Feature tests completed for $version"
done

echo ""
echo "========================================================================"
echo "Feature compatibility testing complete!"
echo "========================================================================"
echo "Results are available in the timescale_feature_tests directory:"
ls -l timescale_feature_tests/

echo ""
echo "Summary commands:"
echo "- View universal compatibility: cat timescale_feature_tests/universal_*.out"
echo "- View feature-specific results: cat timescale_feature_tests/features_*.out"
echo "- Search for PASS/SKIP/FAIL: grep -H 'PASS\\|SKIP\\|FAIL' timescale_feature_tests/features_*.out"
echo ""
echo "Each test shows:"
echo "- PASS: Feature works as expected"
echo "- SKIP: Feature not available (expected for version)" 
echo "- FAIL: Feature should work but doesn't (potential issue)"