#!/bin/bash
# Script to extract pgvector schema information across PostgreSQL versions
# Tests default pgvector versions on each PostgreSQL release

# Save the current directory
SCRIPT_DIR=$(pwd)

# Create directory for output files
mkdir -p pgvector_extracts

# Create the SQL file for pgvector analysis
cat > pgvector_extractor.sql << 'EOF'
\echo '-- PostgreSQL and pgvector Version Information'
SELECT version();
SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';
\echo ''

-- formatting to check diff
\pset format unaligned
\pset tuples_only off
\pset footer off

\echo '-- ================================================================================'
\echo '-- PGVECTOR EXTENSION INFORMATION'
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
    e.extname = 'vector'
ORDER BY 
    e.extname;

\echo ''
\echo '-- ================================================================================'
\echo '-- PGVECTOR DATA TYPES'
\echo '-- ================================================================================'

-- Get vector data types
SELECT 
    t.typname AS type_name,
    n.nspname AS schema_name,
    t.typtype AS type_type,
    t.typlen AS type_length,
    pg_catalog.obj_description(t.oid, 'pg_type') AS description
FROM 
    pg_type t
    JOIN pg_namespace n ON t.typnamespace = n.oid
WHERE 
    t.typname LIKE '%vector%' OR t.typname IN ('vector')
ORDER BY 
    n.nspname, t.typname;

\echo ''
\echo '-- ================================================================================'
\echo '-- PGVECTOR OPERATORS'
\echo '-- ================================================================================'

-- Get vector operators
SELECT 
    o.oprname AS operator_name,
    lt.typname AS left_type,
    rt.typname AS right_type,
    restypename.typname AS result_type,
    n.nspname AS schema_name,
    pg_catalog.obj_description(o.oid, 'pg_operator') AS description
FROM 
    pg_operator o
    JOIN pg_namespace n ON o.oprnamespace = n.oid
    LEFT JOIN pg_type lt ON o.oprleft = lt.oid
    LEFT JOIN pg_type rt ON o.oprright = rt.oid
    LEFT JOIN pg_type restypename ON o.oprresult = restypename.oid
WHERE 
    (lt.typname LIKE '%vector%' OR rt.typname LIKE '%vector%' OR 
     o.oprname IN ('<->', '<=>', '<#>', '<+>', '<|>', '<?>', '<~>') OR
     o.oprcode::text LIKE '%vector%')
ORDER BY 
    n.nspname, o.oprname, lt.typname, rt.typname;

\echo ''
\echo '-- ================================================================================'
\echo '-- PGVECTOR OPERATOR CLASSES'
\echo '-- ================================================================================'

-- Get vector operator classes
SELECT 
    oc.opcname AS opclass_name,
    am.amname AS index_method,
    t.typname AS input_type,
    n.nspname AS schema_name,
    oc.opcdefault AS is_default
FROM 
    pg_opclass oc
    JOIN pg_am am ON oc.opcmethod = am.oid
    JOIN pg_type t ON oc.opcintype = t.oid
    JOIN pg_namespace n ON oc.opcnamespace = n.oid
WHERE 
    oc.opcname LIKE '%vector%' OR t.typname LIKE '%vector%'
ORDER BY 
    am.amname, oc.opcname;

\echo ''
\echo '-- ================================================================================'
\echo '-- PGVECTOR FUNCTIONS'
\echo '-- ================================================================================'

-- Get vector functions
SELECT 
    n.nspname AS schema_name,
    p.proname AS function_name,
    pg_get_function_arguments(p.oid) AS function_args,
    t.typname AS return_type,
    pg_catalog.obj_description(p.oid, 'pg_proc') AS description
FROM 
    pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    JOIN pg_type t ON p.prorettype = t.oid
WHERE 
    (p.proname LIKE '%vector%' OR 
     pg_get_function_arguments(p.oid) LIKE '%vector%' OR
     t.typname LIKE '%vector%' OR
     p.proname IN ('cosine_distance', 'inner_product', 'l1_distance', 'l2_distance'))
ORDER BY 
    n.nspname, p.proname;

\echo ''
\echo '-- ================================================================================'
\echo '-- PGVECTOR INDEX ACCESS METHODS'
\echo '-- ================================================================================'

-- Get access methods (HNSW, IVFFlat) - version compatible
SELECT 
    am.amname AS access_method,
    pg_catalog.obj_description(am.oid, 'pg_am') AS description
FROM 
    pg_am am
WHERE 
    am.amname IN ('hnsw', 'ivfflat') OR am.amname LIKE '%vector%'
ORDER BY 
    am.amname;

\echo ''
\echo '-- ================================================================================'
\echo '-- PGVECTOR SYSTEM CATALOG ENTRIES'
\echo '-- ================================================================================'

-- Check if vector columns exist in current database
SELECT 
    t.table_schema,
    t.table_name,
    c.column_name,
    c.data_type,
    c.udt_name
FROM 
    information_schema.tables t
    JOIN information_schema.columns c ON t.table_name = c.table_name AND t.table_schema = c.table_schema
WHERE 
    c.data_type = 'USER-DEFINED' AND c.udt_name LIKE '%vector%'
ORDER BY 
    t.table_schema, t.table_name, c.column_name;

\echo ''
\echo '-- ================================================================================'
\echo '-- PGVECTOR INDEXES IN CURRENT DATABASE'
\echo '-- ================================================================================'

-- Get vector indexes if any exist
SELECT 
    schemaname,
    tablename,
    indexname,
    indexdef
FROM 
    pg_indexes
WHERE 
    indexdef LIKE '%vector%' OR 
    indexdef LIKE '%hnsw%' OR 
    indexdef LIKE '%ivfflat%'
ORDER BY 
    schemaname, tablename, indexname;

\echo ''
\echo '-- ================================================================================'
\echo '-- PGVECTOR CONFIGURATION SETTINGS'
\echo '-- ================================================================================'

-- Get vector-related configuration settings if any
SELECT 
    name,
    setting,
    unit,
    category,
    short_desc,
    context
FROM 
    pg_settings
WHERE 
    name LIKE '%vector%' OR name LIKE '%hnsw%' OR name LIKE '%ivf%'
ORDER BY 
    name;

\echo ''
\echo '-- ================================================================================'
\echo '-- PGVECTOR AVAILABLE OPERATOR FAMILIES'
\echo '-- ================================================================================'

-- Get operator families for vector operations
SELECT 
    of.opfname AS family_name,
    am.amname AS access_method,
    n.nspname AS schema_name,
    t.typname AS input_type
FROM 
    pg_opfamily of
    JOIN pg_am am ON of.opfmethod = am.oid
    JOIN pg_namespace n ON of.opfnamespace = n.oid
    LEFT JOIN pg_opclass oc ON of.oid = oc.opcfamily
    LEFT JOIN pg_type t ON oc.opcintype = t.oid
WHERE 
    of.opfname LIKE '%vector%' OR 
    am.amname IN ('hnsw', 'ivfflat') OR
    t.typname LIKE '%vector%'
ORDER BY 
    am.amname, of.opfname;

\echo ''
\echo '-- ================================================================================'
\echo '-- PGVECTOR CAST INFORMATION'
\echo '-- ================================================================================'

-- Get cast information for vector types
SELECT 
    st.typname AS source_type,
    tt.typname AS target_type,
    c.castcontext AS cast_context,
    c.castmethod AS cast_method
FROM 
    pg_cast c
    JOIN pg_type st ON c.castsource = st.oid
    JOIN pg_type tt ON c.casttarget = tt.oid
WHERE 
    st.typname LIKE '%vector%' OR tt.typname LIKE '%vector%'
ORDER BY 
    st.typname, tt.typname;
EOF

echo "Created SQL extraction script for pgvector"

# Define PostgreSQL versions with pgvector
# Using standard postgres images and installing pgvector
POSTGRES_VERSIONS=(
    "13"
    "14" 
    "15"
    "16"
    "17"
)

# For each PostgreSQL version
for pg_version in "${POSTGRES_VERSIONS[@]}"; do
    echo "Testing PostgreSQL version $pg_version with pgvector..."
    
    # Start PostgreSQL container
    CONTAINER_NAME="pgvector_test_pg${pg_version}"
    echo "Starting PostgreSQL container: $CONTAINER_NAME..."
    
    # Use official postgres image
    docker run --name $CONTAINER_NAME -e POSTGRES_PASSWORD=password -d postgres:$pg_version
    
    # Wait for PostgreSQL to start
    echo "Waiting for PostgreSQL to start..."
    sleep 10
    
    # Install pgvector extension
    echo "Installing pgvector extension..."
    docker exec $CONTAINER_NAME bash -c "apt-get update && apt-get install -y postgresql-${pg_version}-pgvector"
    
    # Restart PostgreSQL to ensure extension is available
    docker restart $CONTAINER_NAME
    sleep 5
    
    # Create setup script to install pgvector
    cat > pgvector_setup.sql << EOF
-- Create pgvector extension
CREATE EXTENSION IF NOT EXISTS vector;

-- Verify pgvector is loaded
SELECT extname, extversion FROM pg_extension WHERE extname = 'vector';

-- Create a test table with vector column for comprehensive analysis
CREATE TABLE IF NOT EXISTS test_vectors (
    id SERIAL PRIMARY KEY,
    embedding vector(3)
);

-- Insert sample data
INSERT INTO test_vectors (embedding) VALUES ('[1,2,3]'), ('[4,5,6]');

-- Create test indexes
CREATE INDEX IF NOT EXISTS test_hnsw_idx ON test_vectors USING hnsw (embedding vector_cosine_ops);
CREATE INDEX IF NOT EXISTS test_ivfflat_idx ON test_vectors USING ivfflat (embedding vector_l2_ops);
EOF
    
    # Copy setup script to container and execute
    docker cp pgvector_setup.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/pgvector_setup.sql"
    
    # Run the extraction script
    echo "Running extraction script for PostgreSQL $pg_version with pgvector..."
    docker cp pgvector_extractor.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/pgvector_extractor.sql" > pgvector_extracts/pgvector_pg${pg_version}.out
    
    # Stop and remove container
    docker stop $CONTAINER_NAME
    docker rm $CONTAINER_NAME
done

# Generate diffs between consecutive versions
echo "Generating diffs between consecutive PostgreSQL versions..."
for i in $(seq 0 $((${#POSTGRES_VERSIONS[@]}-2))); do
    current_pg=${POSTGRES_VERSIONS[$i]}
    next_pg=${POSTGRES_VERSIONS[$((i+1))]}
    echo "Comparing PostgreSQL $current_pg vs $next_pg with pgvector..."
    diff -u pgvector_extracts/pgvector_pg${current_pg}.out pgvector_extracts/pgvector_pg${next_pg}.out > pgvector_extracts/pgvector_pg${current_pg}_to_pg${next_pg}_diff.patch
done

echo "pgvector analysis complete!"
echo "Extract files are available in the pgvector_extracts directory:"
ls -l pgvector_extracts/

# Provide a summary of findings
echo ""
echo "==== Summary of Changes Between PostgreSQL Versions ===="
for diff_file in pgvector_extracts/*_diff.patch; do
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
echo "To check a specific diff: cat pgvector_extracts/pgvector_pg16_to_pg17_diff.patch"
echo "To see all output files: ls -la pgvector_extracts/"
echo "To see operators: grep -A 10 'PGVECTOR OPERATORS' pgvector_extracts/pgvector_pg17.out"
echo ""
echo "pgvector Testing Strategy:"
echo "Using latest pgvector version available for each PostgreSQL version"
echo "├── PG13: pgvector compatibility baseline"
echo "├── PG14: Extended operator support"
echo "├── PG15: Enhanced index methods"
echo "├── PG16: Performance improvements"
echo "└── PG17: Latest features and optimizations"
echo ""
echo "Done!"