-- Verify TimescaleDB is loaded
SELECT extname, extversion FROM pg_extension WHERE extname = 'timescaledb';
-- Show available TimescaleDB functions
SELECT count(*) as timescale_functions FROM pg_proc p 
JOIN pg_namespace n ON p.pronamespace = n.oid 
WHERE n.nspname LIKE '%timescaledb%' OR p.proname LIKE '%timescale%';
