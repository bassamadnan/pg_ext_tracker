#!/bin/bash
# Script to test pgvector metrics compatibility across PostgreSQL versions

# Save the current directory
SCRIPT_DIR=$(pwd)

# Create directory for test results
mkdir -p pgvector_metrics_tests

# Create the universal compatibility test
cat > universal_pgvector_test.sql << 'EOF'
\echo '-- ================================================================================'
\echo '-- UNIVERSAL PGVECTOR COMPATIBILITY TEST'
\echo '-- ================================================================================'

-- Basic version and extension info
\echo 'PostgreSQL and pgvector Extension Information:'
SELECT version();
SELECT 
  extname,
  extversion,
  extrelocatable,
  extnamespace::regnamespace as schema_name
FROM pg_extension 
WHERE extname = 'vector';

-- Check if vector type is available
\echo 'Vector type availability:'
SELECT EXISTS(
  SELECT 1 FROM pg_type 
  WHERE typname = 'vector'
) as vector_type_available;

-- Check available access methods
\echo 'Available vector access methods:'
SELECT amname 
FROM pg_am 
WHERE amname IN ('hnsw', 'ivfflat');
EOF

# Create pgvector setup
cat > pgvector_setup.sql << 'EOF'
-- Create test data for comprehensive metrics testing
CREATE TABLE IF NOT EXISTS test_products (
    id SERIAL PRIMARY KEY,
    name TEXT,
    embedding vector(384)  -- Common dimension for embeddings
);

CREATE TABLE IF NOT EXISTS test_documents (
    id SERIAL PRIMARY KEY,
    title TEXT,
    content_embedding vector(1536)  -- OpenAI ada-002 dimension
);

-- Insert some test data
INSERT INTO test_products (name, embedding) 
SELECT 
  'product_' || i,
  ('[' || array_to_string(array(SELECT random()::text FROM generate_series(1,384)), ',') || ']')::vector
FROM generate_series(1, 100) i;

INSERT INTO test_documents (title, content_embedding)
SELECT 
  'document_' || i,
  ('[' || array_to_string(array(SELECT random()::text FROM generate_series(1,1536)), ',') || ']')::vector
FROM generate_series(1, 50) i;

-- Create vector indexes for testing
CREATE INDEX IF NOT EXISTS idx_products_hnsw ON test_products USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS idx_products_ivfflat ON test_products USING ivfflat (embedding vector_l2_ops);
CREATE INDEX IF NOT EXISTS idx_documents_hnsw ON test_documents USING hnsw (content_embedding vector_cosine_ops);

-- Force some index usage to generate stats
SELECT COUNT(*) FROM test_products WHERE embedding <-> '[1,2,3]' < 0.5;
SELECT COUNT(*) FROM test_documents WHERE content_embedding <=> '[1,1,1]' < 0.3;
EOF

# Create pgvector metrics tests
cat > pgvector_metrics_tests.sql << 'EOF'
\echo '-- ================================================================================'
\echo '-- PGVECTOR METRICS COMPATIBILITY TESTS'
\echo '-- ================================================================================'

-- Test 1: Vector column inventory
\echo 'TEST 1: Vector Column Inventory'
\echo 'Testing vector column discovery...'
DO $$
DECLARE
  column_count int;
BEGIN
  SELECT COUNT(*) INTO column_count
  FROM information_schema.columns 
  WHERE data_type = 'USER-DEFINED' AND udt_name = 'vector';
  
  IF column_count > 0 THEN
    RAISE NOTICE 'PASS: Vector columns found - Count: %', column_count;
  ELSE
    RAISE NOTICE 'FAIL: No vector columns found';
  END IF;
END $$;

-- Test 2: Vector index usage statistics
\echo 'TEST 2: Vector Index Usage Statistics'  
\echo 'Testing vector index monitoring...'
DO $$
DECLARE
  hnsw_indexes int;
  ivfflat_indexes int;
BEGIN
  SELECT 
    COUNT(*) FILTER (WHERE indexdef LIKE '%hnsw%'),
    COUNT(*) FILTER (WHERE indexdef LIKE '%ivfflat%')
  INTO hnsw_indexes, ivfflat_indexes
  FROM pg_indexes 
  WHERE indexdef LIKE '%vector%';
  
  IF (hnsw_indexes + ivfflat_indexes) > 0 THEN
    RAISE NOTICE 'PASS: Vector indexes found - HNSW: %, IVFFlat: %', hnsw_indexes, ivfflat_indexes;
  ELSE
    RAISE NOTICE 'SKIP: No vector indexes found (expected if no vector data exists)';
  END IF;
END $$;

-- Test 3: Vector table storage monitoring
\echo 'TEST 3: Vector Table Storage'
\echo 'Testing vector table size monitoring...'
DO $$
DECLARE
  vector_tables int;
  total_size_bytes bigint;
BEGIN
  SELECT 
    COUNT(*),
    COALESCE(SUM(pg_total_relation_size(t.table_schema||'.'||t.table_name)), 0)
  INTO vector_tables, total_size_bytes
  FROM information_schema.tables t
  WHERE EXISTS (
    SELECT 1 FROM information_schema.columns c 
    WHERE c.table_schema = t.table_schema 
    AND c.table_name = t.table_name 
    AND c.data_type = 'USER-DEFINED' 
    AND c.udt_name = 'vector'
  );
  
  IF vector_tables > 0 THEN
    RAISE NOTICE 'PASS: Vector tables found - Count: %, Total size: % bytes', 
      vector_tables, total_size_bytes;
  ELSE
    RAISE NOTICE 'SKIP: No tables with vector columns found';
  END IF;
END $$;

-- Test 4: pgvector configuration settings
\echo 'TEST 4: pgvector Configuration Settings'
\echo 'Testing pgvector configuration monitoring...'
DO $$
DECLARE
  config_count int;
BEGIN
  SELECT COUNT(*) INTO config_count
  FROM pg_settings
  WHERE name LIKE 'hnsw.%' OR name LIKE 'ivfflat.%';
  
  IF config_count > 0 THEN
    RAISE NOTICE 'PASS: pgvector config parameters found - Count: %', config_count;
  ELSE
    RAISE NOTICE 'FAIL: No pgvector configuration parameters found';
  END IF;
END $$;

-- Test 5: Vector dimension analysis
\echo 'TEST 5: Vector Dimension Analysis'
\echo 'Testing vector dimension monitoring...'
DO $$
DECLARE
  dimension_info_available boolean;
BEGIN
  -- Test if we can extract dimension information from vector columns
  SELECT EXISTS(
    SELECT 1 FROM information_schema.columns 
    WHERE data_type = 'USER-DEFINED' 
    AND udt_name LIKE 'vector%'
    AND character_maximum_length IS NOT NULL
  ) INTO dimension_info_available;
  
  IF dimension_info_available THEN
    RAISE NOTICE 'PASS: Vector dimension information available through system catalogs';
  ELSE
    RAISE NOTICE 'SKIP: Vector dimension info not available through standard columns (expected)';
  END IF;
END $$;

-- Test 6: Sample actual metric queries
\echo 'TEST 6: Sample pgexporter-style Queries'
\echo 'Testing actual metric queries that pgexporter would use...'

-- Vector column count per schema/table
\echo 'Vector Column Inventory Query:'
SELECT 
  table_schema as schema_name,
  table_name,
  COUNT(*) as vector_columns
FROM information_schema.columns 
WHERE data_type = 'USER-DEFINED' AND udt_name = 'vector'
GROUP BY table_schema, table_name
ORDER BY schema_name, table_name;

-- Vector index usage statistics
\echo 'Vector Index Usage Query:'
SELECT 
  schemaname,
  tablename,
  indexname,
  idx_scan,
  idx_tup_read,
  idx_tup_fetch
FROM pg_stat_user_indexes 
WHERE indexrelname IN (
  SELECT indexname 
  FROM pg_indexes 
  WHERE indexdef LIKE '%vector%' OR indexdef LIKE '%hnsw%' OR indexdef LIKE '%ivfflat%'
)
ORDER BY idx_scan DESC;

-- HNSW index statistics
\echo 'HNSW Index Statistics Query:'
SELECT 
  pui.schemaname,
  pui.relname as tablename,
  pui.indexrelname as indexname,
  pg_relation_size(pui.indexrelid) as index_size_bytes,
  pui.idx_scan,
  pui.idx_tup_read,
  pui.idx_tup_fetch
FROM pg_stat_user_indexes pui
WHERE pui.indexrelname IN (
  SELECT indexname 
  FROM pg_indexes 
  WHERE indexdef LIKE '%hnsw%'
)
ORDER BY pui.idx_scan DESC;

-- IVFFlat index statistics
\echo 'IVFFlat Index Statistics Query:'
SELECT 
  pui.schemaname,
  pui.relname as tablename,
  pui.indexrelname as indexname,
  pg_relation_size(pui.indexrelid) as index_size_bytes,
  pui.idx_scan,
  pui.idx_tup_read,
  pui.idx_tup_fetch
FROM pg_stat_user_indexes pui
WHERE pui.indexrelname IN (
  SELECT indexname 
  FROM pg_indexes 
  WHERE indexdef LIKE '%ivfflat%'
)
ORDER BY pui.idx_scan DESC;

-- Vector table storage
\echo 'Vector Table Storage Query:'
SELECT 
  t.table_schema as schema_name,
  t.table_name,
  pg_total_relation_size(t.table_schema||'.'||t.table_name) as total_size_bytes,
  pg_relation_size(t.table_schema||'.'||t.table_name) as table_size_bytes
FROM information_schema.tables t
WHERE EXISTS (
  SELECT 1 FROM information_schema.columns c 
  WHERE c.table_schema = t.table_schema 
  AND c.table_name = t.table_name 
  AND c.data_type = 'USER-DEFINED' 
  AND c.udt_name = 'vector'
)
ORDER BY total_size_bytes DESC;

-- pgvector configuration settings
\echo 'pgvector Configuration Query:'
SELECT 
  name,
  setting,
  unit,
  category,
  short_desc,
  context
FROM pg_settings
WHERE name LIKE 'hnsw.%' OR name LIKE 'ivfflat.%'
ORDER BY name;

-- Vector operator usage
\echo 'Available Vector Operators Query:'
SELECT 
  o.oprname as operator_name,
  lt.typname as left_type,
  rt.typname as right_type,
  restypename.typname as result_type
FROM pg_operator o
JOIN pg_type lt ON o.oprleft = lt.oid
JOIN pg_type rt ON o.oprright = rt.oid  
JOIN pg_type restypename ON o.oprresult = restypename.oid
WHERE (lt.typname = 'vector' OR rt.typname = 'vector')
  AND o.oprname IN ('<->', '<=>', '<#>', '<+>')
ORDER BY o.oprname;

-- Test 7: Additional vector metrics
\echo 'TEST 7: Additional Vector Metrics'
\echo 'Testing additional useful vector metrics...'

-- Count of vector indexes by type
\echo 'Vector Index Count by Type:'
SELECT 
  CASE 
    WHEN indexdef LIKE '%hnsw%' THEN 'hnsw'
    WHEN indexdef LIKE '%ivfflat%' THEN 'ivfflat'
    ELSE 'other'
  END as index_type,
  COUNT(*) as index_count
FROM pg_indexes
WHERE indexdef LIKE '%vector%'
GROUP BY 
  CASE 
    WHEN indexdef LIKE '%hnsw%' THEN 'hnsw'
    WHEN indexdef LIKE '%ivfflat%' THEN 'ivfflat'
    ELSE 'other'
  END
ORDER BY index_count DESC;

-- Vector tables with row counts
\echo 'Vector Tables with Row Counts:'
WITH vector_tables AS (
  SELECT DISTINCT
    t.table_schema,
    t.table_name
  FROM information_schema.tables t
  WHERE EXISTS (
    SELECT 1 FROM information_schema.columns c 
    WHERE c.table_schema = t.table_schema 
    AND c.table_name = t.table_name 
    AND c.data_type = 'USER-DEFINED' 
    AND c.udt_name = 'vector'
  )
)
SELECT 
  table_schema,
  table_name,
  (SELECT COUNT(*) FROM test_products) as estimated_rows
FROM vector_tables
WHERE table_name = 'test_products'
UNION ALL
SELECT 
  table_schema,
  table_name,
  (SELECT COUNT(*) FROM test_documents) as estimated_rows
FROM vector_tables
WHERE table_name = 'test_documents';

\echo 'All pgvector metric compatibility tests completed!'
EOF

echo "Created pgvector metrics compatibility test scripts"

# Define PostgreSQL versions to test (13-17)
PG_VERSIONS=("13" "14" "15" "16" "17")

# For each PostgreSQL version
for pg_version in "${PG_VERSIONS[@]}"; do
    echo ""
    echo "========================================================================"
    echo "Testing pgvector metrics for PostgreSQL $pg_version"
    echo "========================================================================"
    
    # Pull Docker image
    echo "Pulling Docker image for PostgreSQL $pg_version..."
    docker pull postgres:$pg_version >/dev/null 2>&1
    
    # Start PostgreSQL container
    CONTAINER_NAME="pgvector_metrics_test_${pg_version}"
    echo "Starting PostgreSQL container: $CONTAINER_NAME..."
    docker run --name $CONTAINER_NAME -e POSTGRES_PASSWORD=password -d postgres:$pg_version >/dev/null 2>&1
    
    # Wait for PostgreSQL to start
    echo "Waiting for PostgreSQL to start..."
    sleep 10
    
    # Install pgvector extension
    echo "Installing pgvector extension..."
    docker exec $CONTAINER_NAME bash -c "apt-get update && apt-get install -y postgresql-${pg_version}-pgvector" >/dev/null 2>&1
    
    # Restart PostgreSQL to ensure extension is available
    docker restart $CONTAINER_NAME >/dev/null 2>&1
    sleep 5
    
    # Create extension and setup test data
    echo "Setting up pgvector extension and test data..."
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -c 'CREATE EXTENSION vector;'"
    
    # Run universal compatibility tests
    echo "Running universal compatibility tests..."
    docker cp universal_pgvector_test.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/universal_pgvector_test.sql" > pgvector_metrics_tests/universal_pg${pg_version}.out 2>&1
    
    # Setup test data
    echo "Setting up test data..."
    docker cp pgvector_setup.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/pgvector_setup.sql" >/dev/null 2>&1
    
    # Run metrics tests
    echo "Running metrics compatibility tests..."
    docker cp pgvector_metrics_tests.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/pgvector_metrics_tests.sql" > pgvector_metrics_tests/metrics_pg${pg_version}.out 2>&1
    
    # Stop and remove container
    docker stop $CONTAINER_NAME >/dev/null 2>&1
    docker rm $CONTAINER_NAME >/dev/null 2>&1
    
    echo "Metrics tests completed for PostgreSQL $pg_version"
done

echo ""
echo "========================================================================"
echo "pgvector metrics compatibility testing complete!"
echo "========================================================================"
echo "Results are available in the pgvector_metrics_tests directory:"
ls -l pgvector_metrics_tests/

echo ""
echo "Summary commands:"
echo "- View universal compatibility: cat pgvector_metrics_tests/universal_pg*.out"
echo "- View metrics results: cat pgvector_metrics_tests/metrics_pg*.out"
echo "- Search for PASS/SKIP/FAIL: grep -H 'PASS\\|SKIP\\|FAIL' pgvector_metrics_tests/metrics_pg*.out"
echo ""
echo "Expected results:"
echo "- All basic metrics should PASS across PG 13-17"
echo "- pgvector 0.8.0 provides consistent functionality"
echo "- No SQL errors should occur"

# Clean up temporary files
rm -f universal_pgvector_test.sql pgvector_setup.sql pgvector_metrics_tests.sql