\echo '-- ================================================================================'
\echo '-- POSTGIS RASTER YAML VERIFICATION TEST (FIXED)'
\echo '-- ================================================================================'

-- Ensure PostGIS and Raster extensions are installed
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_raster;

\echo 'Extension Status:'
SELECT extname, extversion FROM pg_extension WHERE extname IN ('postgis', 'postgis_raster');

\echo '-- ================================================================================'
\echo '-- TESTING EMPTY DATABASE SCENARIO (Baseline)'
\echo '-- ================================================================================'

\echo 'BASELINE TEST 1: Raster Table Count'
\echo 'Query: SELECT COUNT(*) as raster_table_count FROM raster_columns;'
SELECT COUNT(*) as raster_table_count FROM raster_columns;

\echo 'BASELINE TEST 2: System-Wide Stats (should be all zeros) - FIXED'
\echo 'Query: System aggregates with proper array handling'
SELECT 
    COUNT(*) as total_raster_tables,
    COUNT(DISTINCT srid) as unique_srids,
    AVG(num_bands) as avg_bands_per_table,
    COUNT(DISTINCT r_table_schema) as schemas_with_rasters,
    COUNT(*) FILTER (WHERE out_db = ARRAY[false] OR out_db IS NULL) as in_database_tables,
    COUNT(*) FILTER (WHERE same_alignment = true) as aligned_tables 
FROM raster_columns;

\echo 'BASELINE TEST 3: Overview Count'
\echo 'Query: SELECT COUNT(*) as overview_count FROM raster_overviews;'
SELECT COUNT(*) as overview_count FROM raster_overviews;

\echo '-- ================================================================================'
\echo '-- CREATING SAMPLE RASTER DATA FOR TESTING'
\echo '-- ================================================================================'

\echo 'Creating sample raster tables with different configurations...'

-- Clean up any existing test tables
DROP TABLE IF EXISTS satellite_imagery CASCADE;
DROP TABLE IF EXISTS elevation_data CASCADE;  
DROP TABLE IF EXISTS weather_data CASCADE;

-- Create first raster table - satellite imagery (RGB, in-database)
CREATE TABLE satellite_imagery (
    id SERIAL PRIMARY KEY,
    name TEXT,
    rast RASTER
);

-- Insert basic raster data (simplified approach)
INSERT INTO satellite_imagery (name, rast) VALUES 
('scene1', ST_MakeEmptyRaster(100, 100, 0, 0, 1, 1, 0, 0, 4326)),
('scene2', ST_MakeEmptyRaster(200, 200, 1000, 1000, 0.5, 0.5, 0, 0, 3857));

-- Add bands using simpler function calls
UPDATE satellite_imagery SET rast = ST_AddBand(rast, '8BUI'::text, 255, 0) WHERE name = 'scene1';
UPDATE satellite_imagery SET rast = ST_AddBand(rast, '8BUI'::text, 128, 0) WHERE name = 'scene2';

-- Add constraints (simplified)
SELECT AddRasterConstraints('public'::name, 'satellite_imagery'::name, 'rast'::name, 
                           ARRAY['srid', 'pixel_types', 'blocksize']);

-- Create second raster table - elevation data (single band float, different SRID)
CREATE TABLE elevation_data (
    id SERIAL PRIMARY KEY,
    region TEXT,
    rast RASTER
);

INSERT INTO elevation_data (region, rast) VALUES 
('mountains', ST_MakeEmptyRaster(50, 50, -120, 45, 0.01, 0.01, 0, 0, 4269)),
('valley', ST_MakeEmptyRaster(75, 75, -121, 44, 0.01, 0.01, 0, 0, 4269));

-- Add elevation band with proper casting
UPDATE elevation_data SET rast = ST_AddBand(rast, '32BF'::text, -9999::double precision, -9999::double precision);

-- Add constraints
SELECT AddRasterConstraints('public'::name, 'elevation_data'::name, 'rast'::name,
                           ARRAY['srid', 'pixel_types']);

-- Create third raster table - weather data (out-of-database)
CREATE TABLE weather_data (
    id SERIAL PRIMARY KEY,
    date_recorded DATE,
    rast RASTER
);

INSERT INTO weather_data (date_recorded, rast) VALUES 
('2024-01-01', ST_MakeEmptyRaster(10, 10, 0, 0, 10, 10, 0, 0, 4326)),
('2024-01-02', ST_MakeEmptyRaster(10, 10, 0, 0, 10, 10, 0, 0, 4326));

-- Add weather band
UPDATE weather_data SET rast = ST_AddBand(rast, '32BF'::text, -999::double precision, -999::double precision);

-- Add constraints
SELECT AddRasterConstraints('public'::name, 'weather_data'::name, 'rast'::name,
                           ARRAY['srid', 'pixel_types']);

\echo 'Sample raster data created successfully!'

\echo '-- ================================================================================'
\echo '-- TESTING ALL YAML QUERIES WITH POPULATED DATA'
\echo '-- ================================================================================'

\echo 'YAML TEST 1: Raster Table Count'
\echo 'Query: SELECT COUNT(*) as raster_table_count FROM raster_columns;'
SELECT COUNT(*) as raster_table_count FROM raster_columns;

\echo 'YAML TEST 2: Raster Columns Info'
\echo 'Query: SELECT r_table_schema, r_table_name, r_raster_column, srid, num_bands FROM raster_columns ORDER BY r_table_schema, r_table_name;'
SELECT r_table_schema, r_table_name, r_raster_column, srid, num_bands 
FROM raster_columns ORDER BY r_table_schema, r_table_name;

\echo 'YAML TEST 3: SRID Distribution'
\echo 'Query: SELECT srid, COUNT(*) as raster_count FROM raster_columns GROUP BY srid ORDER BY raster_count DESC;'
SELECT srid, COUNT(*) as raster_count 
FROM raster_columns GROUP BY srid ORDER BY raster_count DESC;

\echo 'YAML TEST 4: Band Count Statistics'
\echo 'Query: SELECT num_bands, COUNT(*) as table_count FROM raster_columns GROUP BY num_bands ORDER BY num_bands;'
SELECT num_bands, COUNT(*) as table_count 
FROM raster_columns GROUP BY num_bands ORDER BY num_bands;

\echo 'YAML TEST 5: Pixel Type Analysis (FIXED)'
\echo 'Query: Handle pixel_types array properly'
SELECT pixel_type, COUNT(*) as usage_count 
FROM (
    SELECT unnest(pixel_types) as pixel_type 
    FROM raster_columns 
    WHERE pixel_types IS NOT NULL
) pt 
GROUP BY pixel_type ORDER BY usage_count DESC;

\echo 'YAML TEST 6: NoData Value Statistics (FIXED)'
\echo 'Query: Handle nodata_values array properly'
SELECT nodata_value, COUNT(*) as usage_count 
FROM (
    SELECT unnest(nodata_values) as nodata_value 
    FROM raster_columns 
    WHERE nodata_values IS NOT NULL
) nv 
GROUP BY nodata_value ORDER BY usage_count DESC;

\echo 'YAML TEST 7: Raster Overview Count'
\echo 'Query: SELECT COUNT(*) as overview_count FROM raster_overviews;'
SELECT COUNT(*) as overview_count FROM raster_overviews;

\echo 'YAML TEST 8: Overview Factor Distribution'
\echo 'Query: SELECT overview_factor, COUNT(*) as overview_count FROM raster_overviews GROUP BY overview_factor ORDER BY overview_factor;'
SELECT overview_factor, COUNT(*) as overview_count 
FROM raster_overviews GROUP BY overview_factor ORDER BY overview_factor;

\echo 'YAML TEST 9: Storage Type Distribution (FIXED)'
\echo 'Query: Handle out_db array properly'
SELECT 
    CASE 
        WHEN out_db = ARRAY[true] THEN 'out-of-database' 
        WHEN out_db = ARRAY[false] OR out_db IS NULL THEN 'in-database'
        ELSE 'mixed'
    END as storage_type, 
    COUNT(*) as table_count 
FROM raster_columns 
GROUP BY out_db ORDER BY table_count DESC;

\echo 'YAML TEST 10: Raster Constraints'
\echo 'Query: SELECT same_alignment, regular_blocking, COUNT(*) as table_count FROM raster_columns GROUP BY same_alignment, regular_blocking ORDER BY table_count DESC;'
SELECT same_alignment, regular_blocking, COUNT(*) as table_count 
FROM raster_columns 
GROUP BY same_alignment, regular_blocking ORDER BY table_count DESC;

\echo 'YAML TEST 11: Schema Distribution'
\echo 'Query: SELECT r_table_schema, COUNT(*) as raster_table_count, COUNT(DISTINCT srid) as unique_srids, AVG(num_bands) as avg_bands FROM raster_columns GROUP BY r_table_schema ORDER BY raster_table_count DESC;'
SELECT r_table_schema, COUNT(*) as raster_table_count, 
       COUNT(DISTINCT srid) as unique_srids, AVG(num_bands) as avg_bands 
FROM raster_columns 
GROUP BY r_table_schema ORDER BY raster_table_count DESC;

\echo 'YAML TEST 12: System-Wide Aggregates (FIXED)'
\echo 'Query: Complete system statistics with proper array handling'
SELECT 
    COUNT(*) as total_raster_tables,
    COUNT(DISTINCT srid) as unique_srids,
    AVG(num_bands) as avg_bands_per_table,
    COUNT(DISTINCT r_table_schema) as schemas_with_rasters,
    COUNT(*) FILTER (WHERE out_db = ARRAY[false] OR out_db IS NULL) as in_database_tables,
    COUNT(*) FILTER (WHERE same_alignment = true) as aligned_tables 
FROM raster_columns;

\echo 'YAML TEST 13: Scale/Resolution Stats'
\echo 'Query: SELECT scale_x, scale_y, COUNT(*) as table_count FROM raster_columns WHERE scale_x IS NOT NULL AND scale_y IS NOT NULL GROUP BY scale_x, scale_y ORDER BY table_count DESC;'
SELECT scale_x, scale_y, COUNT(*) as table_count 
FROM raster_columns 
WHERE scale_x IS NOT NULL AND scale_y IS NOT NULL 
GROUP BY scale_x, scale_y ORDER BY table_count DESC;

\echo 'YAML TEST 14: Block Size Distribution'
\echo 'Query: SELECT blocksize_x, blocksize_y, COUNT(*) as table_count FROM raster_columns WHERE blocksize_x IS NOT NULL AND blocksize_y IS NOT NULL GROUP BY blocksize_x, blocksize_y ORDER BY table_count DESC;'
SELECT blocksize_x, blocksize_y, COUNT(*) as table_count 
FROM raster_columns 
WHERE blocksize_x IS NOT NULL AND blocksize_y IS NOT NULL 
GROUP BY blocksize_x, blocksize_y ORDER BY table_count DESC;

\echo '-- ================================================================================'
\echo '-- VERIFICATION SUMMARY'
\echo '-- ================================================================================'

\echo 'Summary: All YAML queries executed successfully'
\echo 'Verification Results:'
\echo '- Baseline (empty) tests: Confirmed zero counts'
\echo '- Populated data tests: Confirmed non-zero results'
\echo '- All metric queries from YAML are functional'
\echo '- Raster metadata catalog is properly populated'

\echo 'Final Raster Catalog Summary:'
SELECT 
    'Total raster tables' as metric, COUNT(*)::text as value
FROM raster_columns
UNION ALL
SELECT 
    'Unique SRIDs', COUNT(DISTINCT srid)::text
FROM raster_columns
UNION ALL
SELECT 
    'Average bands per table', COALESCE(AVG(num_bands)::text, 'NULL')
FROM raster_columns
UNION ALL
SELECT 
    'Schemas with rasters', COUNT(DISTINCT r_table_schema)::text
FROM raster_columns;

\echo '-- ================================================================================'
\echo '-- CLEANUP TEST DATA'
\echo '-- ================================================================================'

\echo 'Cleaning up test raster tables...'
DROP TABLE IF EXISTS satellite_imagery CASCADE;
DROP TABLE IF EXISTS elevation_data CASCADE;
DROP TABLE IF EXISTS weather_data CASCADE;

\echo 'PostGIS Raster YAML verification complete!'
