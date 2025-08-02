#!/bin/bash
# Script to test pg_buffercache extension differences between PostgreSQL versions using Docker

# Save the current directory
SCRIPT_DIR=$(pwd)

# Create directory for output files
mkdir -p pg_buffercache_diffs

# Create the SQL file for extension analysis
cat > pg_buffercache_extractor.sql << 'EOF'
\echo '-- PostgreSQL and Extension Version Information'
SELECT version();
SELECT name, default_version, installed_version 
FROM pg_available_extensions 
WHERE name = 'pg_buffercache';
\echo ''

-- formatting to check diff
\pset format unaligned
\pset tuples_only off
\pset footer off

\echo '-- ================================================================================'
\echo '-- EXTENSION VIEW COLUMN INFORMATION'
\echo '-- ================================================================================'

-- Get all views from the extension
SELECT 
    c.relname AS view_name,
    STRING_AGG(a.attname, ', ' ORDER BY a.attnum) AS columns
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_attribute a ON c.oid = a.attrelid
WHERE 
    n.nspname = 'public' 
    AND c.relkind = 'v'
    AND c.relname LIKE 'pg\_buffercache%'
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY 
    c.relname
ORDER BY 
    c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- EXTENSION FUNCTION INFORMATION'
\echo '-- ================================================================================'

-- Get all functions from the extension
SELECT 
    p.proname AS function_name,
    pg_get_function_arguments(p.oid) AS function_args,
    t.typname AS return_type
FROM 
    pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    JOIN pg_type t ON p.prorettype = t.oid
WHERE 
    n.nspname = 'public'
    AND p.proname LIKE 'pg\_buffercache%'
ORDER BY 
    p.proname;

\echo ''
\echo '-- ================================================================================'
\echo '-- EXTENSION VIEW DEFINITIONS'
\echo '-- ================================================================================'

-- Get view definitions
\pset fieldsep '|\n'
SELECT 
    c.relname AS view_name,
    pg_get_viewdef(c.oid, true) AS definition
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE 
    n.nspname = 'public'
    AND c.relkind = 'v'
    AND c.relname LIKE 'pg\_buffercache%'
ORDER BY 
    c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- EXTENSION COLUMN DETAILS'
\echo '-- ================================================================================'

-- Get detailed column information with data types
SELECT 
    c.relname AS view_name,
    a.attname AS column_name,
    pg_catalog.format_type(a.atttypid, a.atttypmod) AS data_type,
    a.attnum AS column_position,
    CASE WHEN a.attnotnull THEN 'NOT NULL' ELSE 'NULL' END AS nullable
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_attribute a ON c.oid = a.attrelid
WHERE 
    n.nspname = 'public' 
    AND c.relkind = 'v'
    AND c.relname LIKE 'pg\_buffercache%'
    AND a.attnum > 0
    AND NOT a.attisdropped
ORDER BY 
    c.relname, a.attnum;

\echo ''
\echo '-- ================================================================================'
\echo '-- EXTENSION SAMPLE DATA STRUCTURE'
\echo '-- ================================================================================'

-- Sample a few rows to see actual data structure (limit to avoid large output)
SELECT * FROM pg_buffercache LIMIT 5;

\echo ''
\echo '-- ================================================================================'
\echo '-- EXTENSION METADATA'
\echo '-- ================================================================================'

-- Get extension metadata
SELECT 
    e.extname,
    e.extversion,
    n.nspname AS schema,
    e.extrelocatable,
    e.extowner::regrole AS owner
FROM pg_extension e
JOIN pg_namespace n ON e.extnamespace = n.oid
WHERE e.extname = 'pg_buffercache';
EOF

echo "Created SQL extraction script for pg_buffercache"

# Define PostgreSQL versions to test (13-17)
PG_VERSIONS=("13" "14" "15" "16" "17")

# For each PostgreSQL version
for pg_version in "${PG_VERSIONS[@]}"; do
    echo "Testing pg_buffercache on PostgreSQL $pg_version..."
    
    # Pull Docker image for PostgreSQL
    echo "Pulling Docker image for PostgreSQL $pg_version..."
    docker pull postgres:$pg_version
    
    # Start PostgreSQL container
    CONTAINER_NAME="pg_buffercache_test_${pg_version}"
    echo "Starting PostgreSQL container: $CONTAINER_NAME..."
    docker run --name $CONTAINER_NAME -e POSTGRES_PASSWORD=password -d postgres:$pg_version
    
    # Wait for PostgreSQL to start
    echo "Waiting for PostgreSQL to start..."
    sleep 10
    
    # Create setup script to install the extension with default version
    cat > pg_buffercache_setup.sql << EOF
-- Create the extension with default version
CREATE EXTENSION pg_buffercache;
-- Verify installation
SELECT name, default_version, installed_version FROM pg_available_extensions WHERE name = 'pg_buffercache';
EOF
    
    # Copy setup script to container and execute
    docker cp pg_buffercache_setup.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/pg_buffercache_setup.sql"
    
    # Run the extraction script
    echo "Running extraction script for pg_buffercache on PostgreSQL $pg_version..."
    docker cp pg_buffercache_extractor.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/pg_buffercache_extractor.sql" > pg_buffercache_diffs/pg_buffercache_pg${pg_version}.out
    
    # Stop and remove container
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
    
    # Clean up temporary files
    rm -f pg_buffercache_setup.sql
done

# Generate diffs between consecutive PostgreSQL versions
echo "Generating diffs between consecutive PostgreSQL versions..."
for i in $(seq 0 $((${#PG_VERSIONS[@]}-2))); do
    current=${PG_VERSIONS[$i]}
    next=${PG_VERSIONS[$((i+1))]}
    echo "Comparing pg_buffercache on PostgreSQL $current vs $next..."
    diff -u pg_buffercache_diffs/pg_buffercache_pg${current}.out pg_buffercache_diffs/pg_buffercache_pg${next}.out > pg_buffercache_diffs/pg_buffercache_pg${current}_to_pg${next}_diff.patch
done

echo "pg_buffercache analysis complete!"
echo "Diff files are available in the pg_buffercache_diffs directory:"
ls -l pg_buffercache_diffs/

# Provide a summary of findings
echo ""
echo "==== Summary of Changes Between PostgreSQL Versions ===="
for diff_file in pg_buffercache_diffs/*_diff.patch; do
    if [ -s "$diff_file" ]; then
        echo "Changes found in $diff_file:"
        grep -A 2 "^+" "$diff_file" | grep -v "^@@" | head -n 10
        echo "..."
        echo ""
    else
        echo "No changes found in $diff_file"
    fi
done

echo ""
echo "To check a specific diff, use: cat pg_buffercache_diffs/pg_buffercache_pg13_to_pg14_diff.patch"
echo "To see all output files: ls -la pg_buffercache_diffs/"
echo ""
echo "Individual version outputs available as:"
for pg_version in "${PG_VERSIONS[@]}"; do
    echo "  - PostgreSQL $pg_version: pg_buffercache_diffs/pg_buffercache_pg${pg_version}.out"
done
echo ""
echo "Done!"

# Clean up temporary files
rm -f pg_buffercache_extractor.sql