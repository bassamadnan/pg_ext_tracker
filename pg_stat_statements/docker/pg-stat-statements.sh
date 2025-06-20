#!/bin/bash
# Script to test pg_stat_statements extension differences between versions using Docker

# Save the current directory
SCRIPT_DIR=$(pwd)

# Create directory for output files
mkdir -p pg_ext_diffs

# Create the SQL file for extension analysis
cat > pg_ext_extractor.sql << 'EOF'
\echo '-- PostgreSQL and Extension Version Information'
SELECT version();
SELECT name, default_version, installed_version 
FROM pg_available_extensions 
WHERE name = 'pg_stat_statements';
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
    AND c.relname LIKE 'pg\_stat\_statements%'
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
    AND p.proname LIKE 'pg\_stat\_statements%'
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
    AND c.relname LIKE 'pg\_stat\_statements%'
ORDER BY 
    c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- EXTENSION TABLES AND COLUMNS'
\echo '-- ================================================================================'

-- Get tables and their columns
SELECT 
    c.relname AS table_name,
    STRING_AGG(a.attname || ' ' || pg_catalog.format_type(a.atttypid, a.atttypmod), 
               ', ' ORDER BY a.attnum) AS columns
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_attribute a ON c.oid = a.attrelid
WHERE 
    n.nspname = 'public' 
    AND c.relkind = 'r'
    AND c.relname LIKE 'pg\_stat\_statements%'
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY 
    c.relname
ORDER BY 
    c.relname;
EOF

echo "Created SQL extraction script"

# Define PostgreSQL version (we'll use PG 15 for this example)
PG_VERSION="17"

# Define pg_stat_statements extension versions to test
# Note: These are the available versions that can be installed
EXT_VERSIONS=("1.7" "1.8" "1.9" "1.10" "1.11")

# Pull Docker image for PostgreSQL
echo "Pulling Docker image for PostgreSQL $PG_VERSION..."
docker pull postgres:$PG_VERSION

# For each extension version
for version in "${EXT_VERSIONS[@]}"; do
    echo "Testing pg_stat_statements version $version..."
    
    # Start PostgreSQL container
    CONTAINER_NAME="pg_ext_test_${version//./}"
    echo "Starting PostgreSQL container: $CONTAINER_NAME..."
    docker run --name $CONTAINER_NAME -e POSTGRES_PASSWORD=password -d postgres:$PG_VERSION
    
    # Wait for PostgreSQL to start
    echo "Waiting for PostgreSQL to start..."
    sleep 10
    
    # Create setup script to install the specific extension version
    cat > pg_ext_setup.sql << EOF
-- Enable the extension
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
-- Create the extension with specific version
CREATE EXTENSION pg_stat_statements VERSION '$version';
-- Verify installation
SELECT name, default_version, installed_version FROM pg_available_extensions WHERE name = 'pg_stat_statements';
EOF
    
    # Copy setup script to container and execute
    docker cp pg_ext_setup.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/pg_ext_setup.sql"
    
    # Restart PostgreSQL to apply shared_preload_libraries change
    docker restart $CONTAINER_NAME
    sleep 10
    
    # Run the extraction script
    echo "Running extraction script for pg_stat_statements $version..."
    docker cp pg_ext_extractor.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/pg_ext_extractor.sql" > pg_ext_diffs/pg_stat_statements_${version}.out
    
    # Stop and remove container
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
done

# Generate diffs between consecutive versions
echo "Generating diffs between consecutive versions..."
for i in $(seq 0 $((${#EXT_VERSIONS[@]}-2))); do
    current=${EXT_VERSIONS[$i]}
    next=${EXT_VERSIONS[$((i+1))]}
    echo "Comparing pg_stat_statements $current vs $next..."
    diff -u pg_ext_diffs/pg_stat_statements_${current}.out pg_ext_diffs/pg_stat_statements_${next}.out > pg_ext_diffs/pg_stat_statements_${current}_to_${next}_diff.patch
done

echo "Extension analysis complete!"
echo "Diff files are available in the pg_ext_diffs directory:"
ls -l pg_ext_diffs/

# Provide a summary of findings
echo ""
echo "==== Summary of Changes Between Versions ===="
for diff_file in pg_ext_diffs/*_diff.patch; do
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
echo "To check a specific diff, use: cat pg_ext_diffs/pg_stat_statements_1.9_to_1.10_diff.patch"
echo "To see all output files: ls -la pg_ext_diffs/"
echo ""
echo "Done!"