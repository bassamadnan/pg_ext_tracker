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
