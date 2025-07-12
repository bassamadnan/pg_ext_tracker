#!/bin/bash
# Script to extract TimescaleDB views and functions using Docker
# Covers TimescaleDB evolution from PostgreSQL 13 to 17 with exact version numbers

# Save the current directory
SCRIPT_DIR=$(pwd)

# Create directory for output files
mkdir -p timescale_extracts

# Create the SQL file for TimescaleDB analysis
cat > timescale_extractor.sql << 'EOF'
\echo '-- PostgreSQL and TimescaleDB Version Information'
SELECT version();
SELECT extname, extversion FROM pg_extension WHERE extname = 'timescaledb';
\echo ''

-- formatting to check diff
\pset format unaligned
\pset tuples_only off
\pset footer off

\echo '-- ================================================================================'
\echo '-- TIMESCALEDB VIEW COLUMN INFORMATION'
\echo '-- ================================================================================'

-- Get all TimescaleDB views from various schemas
SELECT 
    n.nspname AS schema_name,
    c.relname AS view_name,
    STRING_AGG(a.attname, ', ' ORDER BY a.attnum) AS columns
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    JOIN pg_attribute a ON c.oid = a.attrelid
WHERE 
    n.nspname IN ('timescaledb_information', 'timescaledb_experimental', '_timescaledb_catalog', '_timescaledb_internal', 'public')
    AND c.relkind = 'v'
    AND a.attnum > 0
    AND NOT a.attisdropped
    AND (
        c.relname LIKE '%timescale%' OR
        c.relname LIKE '%hypertable%' OR
        c.relname LIKE '%chunk%' OR
        c.relname LIKE '%dimension%' OR
        c.relname LIKE '%compression%' OR
        c.relname LIKE '%continuous_aggregate%' OR
        c.relname LIKE '%job%' OR
        c.relname LIKE '%policy%' OR
        n.nspname LIKE '%timescaledb%'
    )
GROUP BY 
    n.nspname, c.relname
ORDER BY 
    n.nspname, c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- TIMESCALEDB FUNCTION INFORMATION'
\echo '-- ================================================================================'

-- Get all TimescaleDB functions
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
    n.nspname IN ('timescaledb_information', 'timescaledb_experimental', '_timescaledb_catalog', '_timescaledb_internal', 'public')
    AND (
        p.proname LIKE '%timescale%' OR
        p.proname LIKE '%hypertable%' OR
        p.proname LIKE '%chunk%' OR
        p.proname LIKE '%dimension%' OR
        p.proname LIKE '%compression%' OR
        p.proname LIKE '%continuous_aggregate%' OR
        p.proname LIKE '%job%' OR
        p.proname LIKE '%policy%' OR
        n.nspname LIKE '%timescaledb%'
    )
ORDER BY 
    n.nspname, p.proname;

\echo ''
\echo '-- ================================================================================'
\echo '-- TIMESCALEDB VIEW DEFINITIONS'
\echo '-- ================================================================================'

-- Get view definitions
\pset fieldsep '|\n'
SELECT 
    n.nspname AS schema_name,
    c.relname AS view_name,
    pg_get_viewdef(c.oid, true) AS definition
FROM 
    pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
WHERE 
    n.nspname IN ('timescaledb_information', 'timescaledb_experimental', '_timescaledb_catalog', '_timescaledb_internal', 'public')
    AND c.relkind = 'v'
    AND (
        c.relname LIKE '%timescale%' OR
        c.relname LIKE '%hypertable%' OR
        c.relname LIKE '%chunk%' OR
        c.relname LIKE '%dimension%' OR
        c.relname LIKE '%compression%' OR
        c.relname LIKE '%continuous_aggregate%' OR
        c.relname LIKE '%job%' OR
        c.relname LIKE '%policy%' OR
        n.nspname LIKE '%timescaledb%'
    )
ORDER BY 
    n.nspname, c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- TIMESCALEDB INFORMATION SCHEMA VIEWS'
\echo '-- ================================================================================'

-- Get specific TimescaleDB information schema views
SELECT 
    schemaname,
    viewname,
    viewowner,
    definition
FROM 
    pg_views
WHERE 
    schemaname IN ('timescaledb_information', 'timescaledb_experimental')
ORDER BY 
    schemaname, viewname;

\echo ''
\echo '-- ================================================================================'
\echo '-- TIMESCALEDB CATALOG TABLES'
\echo '-- ================================================================================'

-- Get catalog tables and their columns
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
    n.nspname IN ('_timescaledb_catalog', '_timescaledb_internal')
    AND c.relkind = 'r'
    AND a.attnum > 0
    AND NOT a.attisdropped
GROUP BY 
    n.nspname, c.relname
ORDER BY 
    n.nspname, c.relname;

\echo ''
\echo '-- ================================================================================'
\echo '-- TIMESCALEDB EXTENSION DETAILS'
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
    e.extname = 'timescaledb'
ORDER BY 
    e.extname;
EOF

echo "Created SQL extraction script for TimescaleDB"

# Define TimescaleDB versions using .0 releases for consistency
# This captures feature evolution at minor version boundaries
TIMESCALE_VERSIONS=(
    # PostgreSQL 13 era
    "2.10.0-pg13"    # First stable 2.10 series
    "2.11.0-pg13"    # 2.11 series features
    "2.12.0-pg13"    # 2.12 series features  
    "2.13.0-pg13"    # 2.13 series features (PG13 deprecation announced)
    "2.14.0-pg13"    # 2.14 series features
    "2.15.0-pg13"    # 2.15 series features (final PG13 support)
    
    # Transition era (no more PG13)
    "2.16.0-pg14"    # 2.16 series features (first without PG13)
    "2.17.0-pg15"    # 2.17 series features
    "2.18.0-pg16"    # 2.18 series features
    
    # Current era  
    "2.19.0-pg16"    # 2.19 series features (last PG14 support)
    "2.20.0-pg17"    # 2.20 series features (first without PG14)
)

# For each TimescaleDB version
for version in "${TIMESCALE_VERSIONS[@]}"; do
    echo "Testing TimescaleDB version $version..."
    
    # Start TimescaleDB container
    CONTAINER_NAME="timescale_test_${version//[-.]/_}"
    echo "Starting TimescaleDB container: $CONTAINER_NAME..."
    docker run --name $CONTAINER_NAME -e POSTGRES_PASSWORD=password -d timescale/timescaledb:$version
    
    # Wait for PostgreSQL to start
    echo "Waiting for TimescaleDB to start..."
    sleep 15
    
    # Create setup script to ensure TimescaleDB is properly loaded
    cat > timescale_setup.sql << EOF
-- Verify TimescaleDB is loaded
SELECT extname, extversion FROM pg_extension WHERE extname = 'timescaledb';
-- Show available TimescaleDB functions
SELECT count(*) as timescale_functions FROM pg_proc p 
JOIN pg_namespace n ON p.pronamespace = n.oid 
WHERE n.nspname LIKE '%timescaledb%' OR p.proname LIKE '%timescale%';
EOF
    
    # Copy setup script to container and execute
    docker cp timescale_setup.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/timescale_setup.sql"
    
    # Run the extraction script
    echo "Running extraction script for TimescaleDB $version..."
    docker cp timescale_extractor.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/timescale_extractor.sql" > timescale_extracts/timescaledb_${version//[-.]/_}.out
    
    # Stop and remove container
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
done

# Generate diffs between consecutive versions
echo "Generating diffs between consecutive versions..."
for i in $(seq 0 $((${#TIMESCALE_VERSIONS[@]}-2))); do
    current=${TIMESCALE_VERSIONS[$i]//[-.]/_}
    next=${TIMESCALE_VERSIONS[$((i+1))]//[-.]/_}
    current_version=${TIMESCALE_VERSIONS[$i]}
    next_version=${TIMESCALE_VERSIONS[$((i+1))]}
    echo "Comparing TimescaleDB $current_version vs $next_version..."
    diff -u timescale_extracts/timescaledb_${current}.out timescale_extracts/timescaledb_${next}.out > timescale_extracts/timescaledb_${current}_to_${next}_diff.patch
done

echo "TimescaleDB analysis complete!"
echo "Extract files are available in the timescale_extracts directory:"
ls -l timescale_extracts/

# Provide a summary of findings
echo ""
echo "==== Summary of Changes Between Versions ===="
for diff_file in timescale_extracts/*_diff.patch; do
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
echo "Additional commands:"
echo "To check a specific diff: cat timescale_extracts/timescaledb_2_19_0_pg16_to_2_20_0_pg17_diff.patch"
echo "To see all output files: ls -la timescale_extracts/"
echo "To see just view definitions: grep -A 10 'VIEW DEFINITIONS' timescale_extracts/timescaledb_2_20_0_pg17.out"
echo ""
echo "TimescaleDB Version Strategy:"
echo "Using .0 releases to capture feature evolution at minor version boundaries"
echo "├── 2.10.0 → 2.15.0: PostgreSQL 13 era feature evolution"
echo "├── 2.16.0 → 2.18.0: Transition era (PG13 dropped, PG16 added)"
echo "└── 2.19.0 → 2.20.0: Current era (PG14 dropped, PG17 stable)"
echo ""
echo "Key Milestones:"
echo "- PG13 support ended: TimescaleDB 2.16.0"
echo "- PG14 support ended: TimescaleDB 2.20.0" 
echo "- Each .0 release introduces new features/schemas"
echo "- Patch releases (.1, .2, .3) are mostly bug fixes"
echo ""
echo "Done!"