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
