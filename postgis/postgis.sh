#!/bin/bash
# Script to check default PostGIS versions and extract schemas across PostgreSQL versions

# Save the current directory
SCRIPT_DIR=$(pwd)

# Create directory for output files
mkdir -p postgis_extracts

# Define PostgreSQL versions to test
PG_VERSIONS=("13" "14" "15" "16" "17")

echo "=== Phase 1: Checking default PostGIS versions across PostgreSQL versions ==="

# First, check what PostGIS versions are available by default
for pg_version in "${PG_VERSIONS[@]}"; do
    echo "Checking default PostGIS version for PostgreSQL $pg_version..."
    
    CONTAINER_NAME="postgis_check_pg${pg_version}"
    
    # Use the official PostGIS image which has PostGIS pre-installed
    echo "Starting PostGIS container for PG $pg_version..."
    docker run --name $CONTAINER_NAME -e POSTGRES_PASSWORD=password -d postgis/postgis:${pg_version}-3.4
    
    # Wait for PostgreSQL to start
    sleep 10
    
    # Check available PostGIS versions
    echo "Checking available PostGIS extensions..."
    docker exec $CONTAINER_NAME psql -U postgres -c "SELECT name, default_version, installed_version FROM pg_available_extensions WHERE name LIKE 'postgis%' ORDER BY name;" > postgis_extracts/postgis_versions_pg${pg_version}.txt
    
    # Also get the actual PostgreSQL version for reference
    docker exec $CONTAINER_NAME psql -U postgres -c "SELECT version();" >> postgis_extracts/postgis_versions_pg${pg_version}.txt
    
    # Stop and remove container
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
    
    echo "Results saved to postgis_extracts/postgis_versions_pg${pg_version}.txt"
done

echo ""
echo "=== Default PostGIS versions summary ==="
for pg_version in "${PG_VERSIONS[@]}"; do
    echo "PostgreSQL $pg_version:"
    grep "default_version" postgis_extracts/postgis_versions_pg${pg_version}.txt | head -1
done

echo ""
echo "=== Phase 2: Extracting PostGIS schemas ==="

# Create the SQL file for PostGIS schema extraction
cat > postgis_extractor.sql << 'EOF'
\echo '-- PostgreSQL and PostGIS Version Information'
SELECT version();
SELECT name, default_version, installed_version FROM pg_available_extensions WHERE name LIKE 'postgis%' ORDER BY name;
\echo ''

-- Create PostGIS extension if not exists
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;
CREATE EXTENSION IF NOT EXISTS postgis_raster;

-- formatting to check diff
\pset format unaligned
\pset tuples_only off
\pset footer off

\echo '-- ================================================================================'
\echo '-- POSTGIS VIEW COLUMN INFORMATION'
\echo '-- ================================================================================'

-- Get all PostGIS-related views
SELECT 
    n.nspname AS schema_name,
    c.relname AS view_name,
    STRING_AGG(a.attname, ', ' ORDER BY a.attnum) AS columns
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_attribute a ON c.oid = a.attrelid
WHERE 
    n.nspname IN ('public', 'topology')
    AND c.relkind = 'v'
    AND (
        c.relname LIKE '%geometry%' OR
        c.relname LIKE '%geography%' OR
        c.relname LIKE '%spatial%' OR
        c.relname LIKE '%topology%' OR
        c.relname LIKE '%raster%' OR
        c.relname LIKE 'st_%'
    )
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY 
    n.nspname, c.relname
ORDER BY 
    n.nspname, c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- POSTGIS FUNCTION INFORMATION'
\echo '-- ================================================================================'

-- Get all PostGIS functions (limited to avoid overwhelming output)
SELECT 
    n.nspname AS schema_name,
    p.proname AS function_name,
    pg_get_function_arguments(p.oid) AS function_args,
    t.typname AS return_type
FROM 
    pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    JOIN pg_type t ON p.prorettype = t.oid
WHERE 
    n.nspname IN ('public', 'topology')
    AND (
        p.proname LIKE 'st_%' OR
        p.proname LIKE '%geometry%' OR
        p.proname LIKE '%geography%' OR
        p.proname LIKE '%topology%' OR
        p.proname LIKE '%raster%'
    )
    AND p.proname NOT LIKE '%operator%'  -- Exclude operator functions
ORDER BY 
    n.nspname, p.proname
LIMIT 100;  -- Limit to first 100 functions to keep output manageable

\echo ''
\echo '-- ================================================================================'
\echo '-- POSTGIS DATA TYPES'
\echo '-- ================================================================================'

-- Get PostGIS-specific data types
SELECT 
    n.nspname AS schema_name,
    t.typname AS type_name,
    t.typtype AS type_kind,
    CASE 
        WHEN t.typtype = 'b' THEN 'base type'
        WHEN t.typtype = 'c' THEN 'composite type'
        WHEN t.typtype = 'd' THEN 'domain'
        WHEN t.typtype = 'e' THEN 'enum'
        ELSE 'other'
    END AS type_description
FROM 
    pg_type t
    JOIN pg_namespace n ON t.typnamespace = n.oid
WHERE 
    n.nspname IN ('public', 'topology')
    AND (
        t.typname LIKE '%geometry%' OR
        t.typname LIKE '%geography%' OR
        t.typname LIKE '%raster%' OR
        t.typname LIKE '%topology%' OR
        t.typname LIKE 'box%' OR
        t.typname = 'spheroid' OR
        t.typname = 'proj4text'
    )
ORDER BY 
    n.nspname, t.typname;

\echo ''
\echo '-- ================================================================================'
\echo '-- POSTGIS SYSTEM TABLES'
\echo '-- ================================================================================'

-- Get PostGIS system tables and their columns
SELECT 
    n.nspname AS schema_name,
    c.relname AS table_name,
    STRING_AGG(a.attname || ' ' || pg_catalog.format_type(a.atttypid, a.atttypmod), 
               ', ' ORDER BY a.attnum) AS columns
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_attribute a ON c.oid = a.attrelid
WHERE 
    n.nspname IN ('public', 'topology')
    AND c.relkind = 'r'
    AND (
        c.relname LIKE '%geometry%' OR
        c.relname LIKE '%geography%' OR
        c.relname LIKE '%spatial%' OR
        c.relname LIKE '%topology%' OR
        c.relname LIKE '%raster%'
    )
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY 
    n.nspname, c.relname
ORDER BY 
    n.nspname, c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- POSTGIS EXTENSION DETAILS'
\echo '-- ================================================================================'

-- Get extension details
SELECT 
    e.extname,
    e.extversion,
    e.extrelocatable,
    n.nspname AS schema_name
FROM 
    pg_extension e
    JOIN pg_namespace n ON e.extnamespace = n.oid
WHERE 
    e.extname LIKE 'postgis%'
ORDER BY 
    e.extname;

\echo ''
\echo '-- ================================================================================'
\echo '-- SPATIAL REFERENCE SYSTEMS SAMPLE'
\echo '-- ================================================================================'

-- Get a sample of spatial reference systems (if table exists)
SELECT COUNT(*) as total_srs FROM spatial_ref_sys;
SELECT srid, auth_name, auth_srid, srtext FROM spatial_ref_sys LIMIT 5;
EOF

echo "Created SQL extraction script for PostGIS"

# Extract PostGIS schemas for each PostgreSQL version
for pg_version in "${PG_VERSIONS[@]}"; do
    echo "Extracting PostGIS schema for PostgreSQL $pg_version..."
    
    CONTAINER_NAME="postgis_extract_pg${pg_version}"
    
    # Start PostGIS container
    echo "Starting PostGIS container for PG $pg_version..."
    docker run --name $CONTAINER_NAME -e POSTGRES_PASSWORD=password -d postgis/postgis:${pg_version}-3.4
    
    # Wait for PostgreSQL to start
    echo "Waiting for PostgreSQL to start..."
    sleep 15
    
    # Run the extraction script
    echo "Running extraction script for PostgreSQL $pg_version..."
    docker cp postgis_extractor.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/postgis_extractor.sql" > postgis_extracts/postgis_schema_pg${pg_version}.out
    
    # Stop and remove container
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
    
    echo "Schema extracted to postgis_extracts/postgis_schema_pg${pg_version}.out"
done

# Generate diffs between consecutive PostgreSQL versions
echo ""
echo "=== Phase 3: Generating diffs between consecutive versions ==="
for i in $(seq 0 $((${#PG_VERSIONS[@]}-2))); do
    current=${PG_VERSIONS[$i]}
    next=${PG_VERSIONS[$((i+1))]}
    echo "Comparing PostgreSQL $current vs $next PostGIS schemas..."
    diff -u postgis_extracts/postgis_schema_pg${current}.out postgis_extracts/postgis_schema_pg${next}.out > postgis_extracts/postgis_pg${current}_to_pg${next}_diff.patch
done

echo ""
echo "PostGIS analysis complete!"
echo "Files generated:"
ls -la postgis_extracts/

# Provide a summary of findings
echo ""
echo "=== Summary of Default PostGIS Versions ==="
for pg_version in "${PG_VERSIONS[@]}"; do
    echo "PostgreSQL $pg_version:"
    if [ -f "postgis_extracts/postgis_versions_pg${pg_version}.txt" ]; then
        grep -A 1 "name.*default_version" postgis_extracts/postgis_versions_pg${pg_version}.txt | grep postgis | head -1
    fi
done

echo ""
echo "=== Summary of Schema Changes Between Versions ==="
for diff_file in postgis_extracts/*_diff.patch; do
    if [ -s "$diff_file" ]; then
        echo "Changes found in $(basename $diff_file):"
        echo "  Added lines: $(grep -c "^+" "$diff_file")"
        echo "  Removed lines: $(grep -c "^-" "$diff_file")"
        echo ""
    else
        echo "No changes found in $(basename $diff_file)"
    fi
done

echo ""
echo "Additional commands:"
echo "To check a specific diff: cat postgis_extracts/postgis_pg16_to_pg17_diff.patch"
echo "To see all PostGIS functions: grep -A 1 'FUNCTION INFORMATION' postgis_extracts/postgis_schema_pg17.out"
echo "To see PostGIS types: grep -A 10 'DATA TYPES' postgis_extracts/postgis_schema_pg17.out"
echo ""
echo "PostGIS Version Strategy:"
echo "Using official PostGIS Docker images to capture:"
echo "├── Default PostGIS versions across PostgreSQL releases"
echo "├── Schema evolution (functions, types, views)"
echo "└── API changes between PostgreSQL versions"
echo ""
echo "Clean up:"
echo "rm -rf postgis_extracts/ postgis_extractor.sql"
echo ""
echo "Done!"