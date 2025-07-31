\echo '-- ================================================================================'
\echo '-- POSTGIS RASTER WORKING QUERIES TEST'
\echo '-- ================================================================================'

-- Ensure PostGIS and Raster extensions are installed
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_raster;

-- Check extension status
\echo 'Extension Status:'
SELECT extname, extversion FROM pg_extension WHERE extname IN ('postgis', 'postgis_raster');

\echo '-- ================================================================================'
\echo '-- TESTING WORKING RASTER MONITORING QUERIES'
\echo '-- ================================================================================'

\echo 'TEST 1: Raster Table Count (Core Metric)'
\echo 'Query: SELECT COUNT(*) as raster_table_count FROM raster_columns;'
SELECT COUNT(*) as raster_table_count FROM raster_columns;

\echo 'TEST 2: Raster Columns Basic Info'
\echo 'Query: Basic raster metadata'
SELECT 
    r_table_schema, 
    r_table_name, 
    r_raster_column, 
    srid, 
    num_bands
FROM raster_columns 
ORDER BY r_table_schema, r_table_name
LIMIT 20;

\echo 'TEST 3: SRID Distribution'
\echo 'Query: Spatial reference systems used'
SELECT 
    srid, 
    COUNT(*) as raster_count 
FROM raster_columns 
GROUP BY srid 
ORDER BY raster_count DESC;

\echo 'TEST 4: Band Count Statistics'
\echo 'Query: Number of bands per raster table'
SELECT 
    num_bands, 
    COUNT(*) as table_count 
FROM raster_columns 
GROUP BY num_bands 
ORDER BY num_bands;

\echo 'TEST 5: Pixel Type Analysis'
\echo 'Query: Pixel data types in use'
SELECT 
    unnest(pixel_types) as pixel_type, 
    COUNT(*) as usage_count 
FROM raster_columns 
GROUP BY unnest(pixel_types) 
ORDER BY usage_count DESC;

\echo 'TEST 6: NoData Value Statistics'
\echo 'Query: NoData value distribution'
SELECT 
    unnest(nodata_values) as nodata_value, 
    COUNT(*) as usage_count 
FROM raster_columns 
WHERE nodata_values IS NOT NULL
GROUP BY unnest(nodata_values) 
ORDER BY usage_count DESC
LIMIT 10;

\echo 'TEST 7: Raster Overview Count'
\echo 'Query: Number of raster overviews/pyramids'
SELECT COUNT(*) as overview_count FROM raster_overviews;

\echo 'TEST 8: Overview Factor Distribution'
\echo 'Query: Overview pyramid factors'
SELECT 
    overview_factor, 
    COUNT(*) as overview_count 
FROM raster_overviews 
GROUP BY overview_factor 
ORDER BY overview_factor;

\echo 'TEST 9: Storage Type Distribution'
\echo 'Query: In-database vs out-of-database storage'
SELECT 
    CASE 
        WHEN out_db = '{t}' THEN 'Out-of-Database'
        WHEN out_db = '{f}' THEN 'In-Database'
        ELSE 'Mixed/Unknown'
    END as storage_type,
    COUNT(*) as table_count 
FROM raster_columns 
GROUP BY out_db;

\echo 'TEST 10: Raster Constraint Analysis'
\echo 'Query: Alignment and blocking constraints'
SELECT 
    same_alignment, 
    regular_blocking, 
    COUNT(*) as table_count 
FROM raster_columns 
GROUP BY same_alignment, regular_blocking;

\echo 'TEST 11: Schema-Level Summary'
\echo 'Query: Raster distribution across schemas'
SELECT 
    r_table_schema, 
    COUNT(*) as raster_table_count,
    COUNT(DISTINCT srid) as unique_srids,
    ROUND(AVG(num_bands), 2) as avg_bands
FROM raster_columns 
GROUP BY r_table_schema 
ORDER BY raster_table_count DESC;

\echo 'TEST 12: System-Wide Aggregates'
\echo 'Query: Overall raster statistics'
SELECT 
    COUNT(*) as total_raster_tables,
    COUNT(DISTINCT srid) as unique_srids,
    ROUND(AVG(num_bands), 2) as avg_bands_per_table,
    COUNT(DISTINCT r_table_schema) as schemas_with_rasters,
    COUNT(*) FILTER (WHERE out_db = '{f}') as in_database_tables,
    COUNT(*) FILTER (WHERE same_alignment = 't') as aligned_tables
FROM raster_columns;

\echo 'TEST 13: Raster Scale Analysis'
\echo 'Query: Raster resolution/scale statistics'
SELECT 
    ROUND(scale_x::numeric, 6) as scale_x,
    ROUND(scale_y::numeric, 6) as scale_y,
    COUNT(*) as table_count
FROM raster_columns 
WHERE scale_x IS NOT NULL AND scale_y IS NOT NULL
GROUP BY ROUND(scale_x::numeric, 6), ROUND(scale_y::numeric, 6)
ORDER BY table_count DESC
LIMIT 10;

\echo 'TEST 14: Block Size Distribution'
\echo 'Query: Raster tiling/blocking sizes'
SELECT 
    blocksize_x,
    blocksize_y,
    COUNT(*) as table_count
FROM raster_columns 
WHERE blocksize_x IS NOT NULL AND blocksize_y IS NOT NULL
GROUP BY blocksize_x, blocksize_y
ORDER BY table_count DESC
LIMIT 10;

\echo 'TEST 15: Coordinate Functions Test'
\echo 'Query: Test core raster coordinate functions'
DO $$
DECLARE
    test_raster raster;
    world_x double precision;
    world_y double precision;
    pixel_x integer;
    pixel_y integer;
    raster_width integer;
    raster_height integer;
    raster_srid integer;
BEGIN
    -- Create a simple test raster
    test_raster := ST_MakeEmptyRaster(100, 100, 0, 0, 1, 1, 0, 0, 4326);
    
    -- Test property functions
    raster_width := ST_Width(test_raster);
    raster_height := ST_Height(test_raster);
    raster_srid := ST_SRID(test_raster);
    
    -- Test coordinate functions
    world_x := ST_RasterToWorldCoordX(test_raster, 1, 1);
    world_y := ST_RasterToWorldCoordY(test_raster, 1, 1);
    pixel_x := ST_WorldToRasterCoordX(test_raster, 0, 0);
    pixel_y := ST_WorldToRasterCoordY(test_raster, 0, 0);
    
    IF raster_width = 100 AND raster_height = 100 AND raster_srid = 4326 AND
       world_x IS NOT NULL AND world_y IS NOT NULL AND 
       pixel_x IS NOT NULL AND pixel_y IS NOT NULL THEN
        RAISE NOTICE 'PASS: All core raster functions work correctly';
        RAISE NOTICE 'Details - Width: %, Height: %, SRID: %', raster_width, raster_height, raster_srid;
        RAISE NOTICE 'Coordinate test - World: (%, %), Pixel: (%, %)', world_x, world_y, pixel_x, pixel_y;
    ELSE
        RAISE NOTICE 'FAIL: Some raster functions returned unexpected values';
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Raster functions failed with error: %', SQLERRM;
END $$;

\echo 'TEST 16: Raster Views Accessibility'
\echo 'Query: Verify all key raster views are accessible'
DO $$
BEGIN
    -- Test raster_columns view
    PERFORM COUNT(*) FROM raster_columns;
    RAISE NOTICE 'PASS: raster_columns view is accessible';
    
    -- Test raster_overviews view  
    PERFORM COUNT(*) FROM raster_overviews;
    RAISE NOTICE 'PASS: raster_overviews view is accessible';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Raster views accessibility test failed: %', SQLERRM;
END $$;

\echo '-- ================================================================================'
\echo '-- SUMMARY OF WORKING QUERIES'
\echo '-- ================================================================================'

\echo 'Summary: All tested queries completed'
\echo 'These queries are suitable for pgexporter raster monitoring:'
\echo '1. Raster table count (raster_columns)'
\echo '2. SRID distribution analysis'
\echo '3. Band count statistics'
\echo '4. Pixel type and NoData analysis'
\echo '5. Storage type distribution (in-db vs out-db)'
\echo '6. Overview/pyramid information'
\echo '7. Schema-level raster distribution'
\echo '8. System-wide aggregation metrics'
\echo '9. Constraint compliance statistics'
\echo '10. Core raster function availability'

\echo 'PostGIS Raster working queries test complete!'
