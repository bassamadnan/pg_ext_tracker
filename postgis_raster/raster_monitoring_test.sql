\echo '-- ================================================================================'
\echo '-- POSTGIS RASTER MONITORING TEST'
\echo '-- ================================================================================'

-- Ensure PostGIS and Raster extensions are installed
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_raster;

-- Check extension installation status
\echo 'Extension Status:'
SELECT extname, extversion FROM pg_extension WHERE extname IN ('postgis', 'postgis_raster');

\echo '-- ================================================================================'
\echo '-- TESTING RASTER MONITORING QUERIES (EMPTY DATABASE SCENARIO)'
\echo '-- ================================================================================'

\echo 'TEST 1: Raster Tables Count'
\echo 'Query: SELECT COUNT(*) as raster_table_count FROM raster_columns;'
SELECT COUNT(*) as raster_table_count FROM raster_columns;

\echo 'TEST 2: Raster Columns Details'
\echo 'Query: Basic raster columns information'
SELECT 
    r_table_schema, 
    r_table_name, 
    r_raster_column, 
    srid, 
    num_bands, 
    pixel_types, 
    nodata_values,
    out_db
FROM raster_columns 
ORDER BY r_table_schema, r_table_name
LIMIT 10;

\echo 'TEST 3: Raster SRID Distribution'
\echo 'Query: Distribution of SRIDs in raster data'
SELECT 
    srid, 
    COUNT(*) as raster_count 
FROM raster_columns 
GROUP BY srid 
ORDER BY raster_count DESC
LIMIT 10;

\echo 'TEST 4: Raster Band Statistics'
\echo 'Query: Band count distribution'
SELECT 
    num_bands, 
    COUNT(*) as table_count 
FROM raster_columns 
GROUP BY num_bands 
ORDER BY num_bands;

\echo 'TEST 5: Raster Pixel Type Distribution'
\echo 'Query: Pixel type usage statistics'
SELECT 
    unnest(pixel_types) as pixel_type, 
    COUNT(*) as usage_count 
FROM raster_columns 
GROUP BY unnest(pixel_types) 
ORDER BY usage_count DESC
LIMIT 10;

\echo 'TEST 6: Raster Overview Information'
\echo 'Query: Raster overviews and pyramid information'
SELECT 
    r_table_schema, 
    r_table_name, 
    r_raster_column, 
    overview_factor 
FROM raster_overviews 
ORDER BY r_table_schema, r_table_name, overview_factor
LIMIT 10;

\echo 'TEST 7: Out-of-Database Raster Statistics'
\echo 'Query: In-database vs out-of-database raster distribution'
SELECT 
    out_db, 
    COUNT(*) as raster_count 
FROM raster_columns 
GROUP BY out_db;

\echo 'TEST 8: Raster Constraint Statistics'
\echo 'Query: Raster constraint compliance'
SELECT 
    same_alignment, 
    regular_blocking, 
    COUNT(*) as table_count 
FROM raster_columns 
GROUP BY same_alignment, regular_blocking;

\echo 'TEST 9: Raster Storage Summary'
\echo 'Query: Overall raster storage statistics'
SELECT 
    COUNT(*) as total_raster_tables,
    COUNT(DISTINCT srid) as unique_srids,
    AVG(num_bands) as avg_bands_per_table,
    COUNT(*) FILTER (WHERE out_db = '{t}') as out_db_tables,
    COUNT(*) FILTER (WHERE same_alignment = 't') as aligned_tables
FROM raster_columns;

\echo 'TEST 10: Schema-level Raster Distribution'
\echo 'Query: Raster tables per schema'
SELECT 
    r_table_schema, 
    COUNT(*) as raster_table_count,
    COUNT(DISTINCT srid) as unique_srids,
    AVG(num_bands) as avg_bands
FROM raster_columns 
GROUP BY r_table_schema 
ORDER BY raster_table_count DESC;

\echo '-- ================================================================================'
\echo '-- CREATING SAMPLE RASTER DATA FOR TESTING'
\echo '-- ================================================================================'

-- Create sample raster tables for testing
\echo 'Creating sample raster data for validation...'
DO $$
BEGIN
    -- Create a test table with raster column
    CREATE TABLE IF NOT EXISTS test_raster_table (
        id serial PRIMARY KEY,
        name text,
        rast raster
    );
    
    -- Insert some sample raster data
    INSERT INTO test_raster_table (name, rast) VALUES 
    (
        'test_raster_1',
        ST_MakeEmptyRaster(100, 100, 0, 0, 1, 1, 0, 0, 4326)
    ),
    (
        'test_raster_2', 
        ST_MakeEmptyRaster(200, 150, 10, 10, 0.5, 0.5, 0, 0, 3857)
    );
    
    -- Add raster constraints
    PERFORM AddRasterConstraints('public', 'test_raster_table', 'rast');
    
    RAISE NOTICE 'Sample raster data created successfully';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error creating sample raster data: %', SQLERRM;
END $$;

-- Create another test table with different characteristics
DO $$
BEGIN
    CREATE TABLE IF NOT EXISTS elevation_data (
        id serial PRIMARY KEY,
        region text,
        elevation raster
    );
    
    -- Insert rasters with multiple bands
    INSERT INTO elevation_data (region, elevation) VALUES 
    (
        'mountain_area',
        ST_AddBand(ST_MakeEmptyRaster(50, 50, 100, 200, 2, 2, 0, 0, 4326), '32BF'::text, 0, 0)
    );
    
    -- Add constraints
    PERFORM AddRasterConstraints('public', 'elevation_data', 'elevation');
    
    RAISE NOTICE 'Elevation raster data created successfully';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error creating elevation data: %', SQLERRM;
END $$;

\echo '-- ================================================================================'
\echo '-- RE-RUNNING QUERIES WITH SAMPLE DATA'
\echo '-- ================================================================================'

\echo 'RETEST 1: Raster Tables Count (should show sample tables)'
SELECT COUNT(*) as raster_table_count FROM raster_columns;

\echo 'RETEST 2: Raster Columns Details (should include sample data)'
SELECT 
    r_table_schema, 
    r_table_name, 
    r_raster_column, 
    srid, 
    num_bands, 
    pixel_types, 
    nodata_values,
    out_db
FROM raster_columns 
ORDER BY r_table_schema, r_table_name;

\echo 'RETEST 3: SRID Distribution (should show 4326 and 3857)'
SELECT 
    srid, 
    COUNT(*) as raster_count 
FROM raster_columns 
GROUP BY srid 
ORDER BY raster_count DESC;

\echo 'RETEST 4: Band Statistics (should show different band counts)'
SELECT 
    num_bands, 
    COUNT(*) as table_count 
FROM raster_columns 
GROUP BY num_bands 
ORDER BY num_bands;

\echo 'RETEST 5: Pixel Type Distribution'
SELECT 
    unnest(pixel_types) as pixel_type, 
    COUNT(*) as usage_count 
FROM raster_columns 
GROUP BY unnest(pixel_types) 
ORDER BY usage_count DESC;

\echo 'RETEST 6: Storage Summary (should show sample data statistics)'
SELECT 
    COUNT(*) as total_raster_tables,
    COUNT(DISTINCT srid) as unique_srids,
    AVG(num_bands) as avg_bands_per_table,
    COUNT(*) FILTER (WHERE out_db = '{f}') as in_db_tables,
    COUNT(*) FILTER (WHERE same_alignment = 't') as aligned_tables
FROM raster_columns;

\echo '-- ================================================================================'
\echo '-- RASTER FUNCTION AVAILABILITY TESTS'
\echo '-- ================================================================================'

\echo 'TEST: Core Raster Functions'
\echo 'Testing basic raster creation and property functions...'
DO $$
DECLARE
    test_raster raster;
    raster_width integer;
    raster_height integer;
    raster_srid integer;
    band_count integer;
BEGIN
    -- Create a test raster
    test_raster := ST_MakeEmptyRaster(10, 10, 0, 0, 1, 1, 0, 0, 4326);
    test_raster := ST_AddBand(test_raster, '8BUI', 255, 0);
    
    -- Test property functions
    raster_width := ST_Width(test_raster);
    raster_height := ST_Height(test_raster);
    raster_srid := ST_SRID(test_raster);
    band_count := ST_NumBands(test_raster);
    
    IF raster_width = 10 AND raster_height = 10 AND raster_srid = 4326 AND band_count = 1 THEN
        RAISE NOTICE 'PASS: Core raster functions work (w:%, h:%, srid:%, bands:%)', 
                     raster_width, raster_height, raster_srid, band_count;
    ELSE
        RAISE NOTICE 'FAIL: Core raster functions returned unexpected values';
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Core raster functions failed with error: %', SQLERRM;
END $$;

\echo 'TEST: Raster Coordinate Functions'
\echo 'Testing raster coordinate transformation functions...'
DO $$
DECLARE
    test_raster raster;
    world_x double precision;
    world_y double precision;
    pixel_x integer;
    pixel_y integer;
BEGIN
    test_raster := ST_MakeEmptyRaster(100, 100, 0, 0, 1, 1, 0, 0, 4326);
    
    -- Test coordinate transformations
    world_x := ST_RasterToWorldCoordX(test_raster, 1, 1);
    world_y := ST_RasterToWorldCoordY(test_raster, 1, 1);
    pixel_x := ST_WorldToRasterCoordX(test_raster, 0, 0);
    pixel_y := ST_WorldToRasterCoordY(test_raster, 0, 0);
    
    IF world_x IS NOT NULL AND world_y IS NOT NULL AND pixel_x IS NOT NULL AND pixel_y IS NOT NULL THEN
        RAISE NOTICE 'PASS: Coordinate transformation functions work';
    ELSE
        RAISE NOTICE 'FAIL: Coordinate transformation functions returned NULL values';
    END IF;
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'FAIL: Coordinate transformation functions failed: %', SQLERRM;
END $$;

\echo '-- ================================================================================'
\echo '-- CLEANUP TEST DATA'
\echo '-- ================================================================================'

\echo 'Cleaning up test raster tables...'
DO $$
BEGIN
    DROP TABLE IF EXISTS test_raster_table CASCADE;
    DROP TABLE IF EXISTS elevation_data CASCADE;
    RAISE NOTICE 'Test raster tables dropped successfully';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error dropping test tables: %', SQLERRM;
END $$;

\echo 'PostGIS Raster monitoring test complete!'
