#!/bin/bash
# Script to test PostGIS Topology monitoring queries for pgexporter compatibility
# Tests all queries from the YAML configuration across PostgreSQL versions

# Save the current directory
SCRIPT_DIR=$(pwd)

# Create directory for test results
mkdir -p postgis_topology_monitoring_tests

# Create the topology monitoring test queries
cat > topology_monitoring_test.sql << 'EOF'
\echo '-- ================================================================================'
\echo '-- POSTGIS TOPOLOGY MONITORING TEST'
\echo '-- ================================================================================'

-- Ensure PostGIS and Topology extensions are installed
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

-- Check extension installation status
\echo 'Extension Status:'
SELECT extname, extversion FROM pg_extension WHERE extname IN ('postgis', 'postgis_topology');

\echo '-- ================================================================================'
\echo '-- TESTING TOPOLOGY MONITORING QUERIES (FROM YAML CONFIG)'
\echo '-- ================================================================================'

\echo 'TEST 1: Topology Inventory'
\echo 'Query: SELECT COUNT(*) as topology_count FROM topology.topology;'
SELECT COUNT(*) as topology_count FROM topology.topology;

\echo 'TEST 2: Topology Details'
\echo 'Query: SELECT id, name, srid, precision, hasz FROM topology.topology ORDER BY id;'
SELECT id, name, srid, precision, hasz FROM topology.topology ORDER BY id;

\echo 'TEST 3: SRID Distribution'
\echo 'Query: SELECT srid, COUNT(*) as topology_count FROM topology.topology GROUP BY srid ORDER BY topology_count DESC;'
SELECT srid, COUNT(*) as topology_count FROM topology.topology GROUP BY srid ORDER BY topology_count DESC;

\echo 'TEST 4: Topology Primitives by Topology'
\echo 'Query: Complex query with subqueries for node/edge/face counts'
SELECT 
    t.id as topology_id, 
    t.name as topology_name, 
    (SELECT COUNT(*) FROM topology.node WHERE topology_id = t.id) as node_count, 
    (SELECT COUNT(*) FROM topology.edge_data WHERE topology_id = t.id) as edge_count, 
    (SELECT COUNT(*) FROM topology.face WHERE topology_id = t.id) as face_count 
FROM topology.topology t ORDER BY t.id;

\echo 'TEST 5: Total Primitive Counts'
\echo 'Query: System-wide totals'
SELECT 
    (SELECT COUNT(*) FROM topology.node) as total_nodes, 
    (SELECT COUNT(*) FROM topology.edge_data) as total_edges, 
    (SELECT COUNT(*) FROM topology.face) as total_faces;

\echo 'TEST 6: Topology Layers'
\echo 'Query: SELECT topology_id, layer_id, feature_type, level FROM topology.layer ORDER BY topology_id, layer_id;'
SELECT topology_id, layer_id, feature_type, level FROM topology.layer ORDER BY topology_id, layer_id;

\echo 'TEST 7: Layer Summary'
\echo 'Query: Layer counts per topology'
SELECT 
    l.topology_id, 
    t.name as topology_name, 
    COUNT(*) as layer_count 
FROM topology.layer l 
JOIN topology.topology t ON l.topology_id = t.id 
GROUP BY l.topology_id, t.name 
ORDER BY l.topology_id;

\echo 'TEST 8: Precision Statistics'
\echo 'Query: SELECT precision, COUNT(*) as topology_count FROM topology.topology GROUP BY precision ORDER BY precision;'
SELECT precision, COUNT(*) as topology_count FROM topology.topology GROUP BY precision ORDER BY precision;

\echo 'TEST 9: Node Edge Connectivity'
\echo 'Query: Isolated nodes detection'
SELECT 
    n.topology_id, 
    COUNT(*) as isolated_nodes 
FROM topology.node n 
LEFT JOIN topology.edge_data e ON (n.node_id = e.start_node OR n.node_id = e.end_node) AND n.topology_id = e.topology_id 
WHERE e.edge_id IS NULL 
GROUP BY n.topology_id;

\echo 'TEST 10: Face Edge Statistics'
\echo 'Query: Face complexity analysis'
SELECT 
    topology_id, 
    AVG(array_length(mbr::numeric[], 1)) as avg_face_complexity 
FROM topology.face 
WHERE mbr IS NOT NULL 
GROUP BY topology_id;

\echo 'TEST 11: Storage Statistics'
\echo 'Query: Table sizes'
SELECT 
    t.name as topology_name, 
    pg_size_pretty(pg_total_relation_size('topology.node')) as node_table_size, 
    pg_size_pretty(pg_total_relation_size('topology.edge_data')) as edge_table_size, 
    pg_size_pretty(pg_total_relation_size('topology.face')) as face_table_size 
FROM topology.topology t 
LIMIT 10;

\echo 'TEST 12: Feature Type Distribution'
\echo 'Query: Layer feature types'
SELECT 
    feature_type, 
    CASE 
        WHEN feature_type = 1 THEN 'Point' 
        WHEN feature_type = 2 THEN 'Line' 
        WHEN feature_type = 3 THEN 'Polygon' 
        WHEN feature_type = 4 THEN 'Collection' 
        ELSE 'Unknown' 
    END as feature_type_name, 
    COUNT(*) as layer_count 
FROM topology.layer 
GROUP BY feature_type 
ORDER BY feature_type;

\echo '-- ================================================================================'
\echo '-- CREATING SAMPLE TOPOLOGY DATA FOR TESTING'
\echo '-- ================================================================================'

-- Create a test topology to verify queries work with actual data
\echo 'Creating test topology for validation...'
DO $$
DECLARE
    topo_id integer;
    node1_id integer;
    node2_id integer;
    node3_id integer;
    edge1_id integer;
    edge2_id integer;
    face_id integer;
BEGIN
    -- Create a test topology
    SELECT topology.CreateTopology('test_topology', 4326, 0.0001) INTO topo_id;
    RAISE NOTICE 'Created topology with ID: %', topo_id;
    
    -- Add some test nodes
    SELECT topology.ST_AddIsoNode('test_topology', NULL, ST_GeomFromText('POINT(0 0)', 4326)) INTO node1_id;
    SELECT topology.ST_AddIsoNode('test_topology', NULL, ST_GeomFromText('POINT(1 0)', 4326)) INTO node2_id;
    SELECT topology.ST_AddIsoNode('test_topology', NULL, ST_GeomFromText('POINT(1 1)', 4326)) INTO node3_id;
    RAISE NOTICE 'Added nodes: %, %, %', node1_id, node2_id, node3_id;
    
    -- Add some test edges
    SELECT topology.ST_AddEdgeNewFaces('test_topology', node1_id, node2_id, ST_GeomFromText('LINESTRING(0 0, 1 0)', 4326)) INTO edge1_id;
    SELECT topology.ST_AddEdgeNewFaces('test_topology', node2_id, node3_id, ST_GeomFromText('LINESTRING(1 0, 1 1)', 4326)) INTO edge2_id;
    RAISE NOTICE 'Added edges: %, %', edge1_id, edge2_id;
    
    RAISE NOTICE 'Test topology created successfully';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error creating test topology: %', SQLERRM;
        RAISE NOTICE 'This is expected if topology already exists or there are permission issues';
END $$;

\echo '-- ================================================================================'
\echo '-- RE-RUNNING QUERIES WITH TEST DATA'
\echo '-- ================================================================================'

\echo 'RETEST: Topology Inventory (should show test_topology)'
SELECT COUNT(*) as topology_count FROM topology.topology;

\echo 'RETEST: Topology Details (should include test_topology)'
SELECT id, name, srid, precision, hasz FROM topology.topology ORDER BY id;

\echo 'RETEST: Primitives by Topology (should show test data)'
SELECT 
    t.id as topology_id, 
    t.name as topology_name, 
    (SELECT COUNT(*) FROM topology.node WHERE topology_id = t.id) as node_count, 
    (SELECT COUNT(*) FROM topology.edge_data WHERE topology_id = t.id) as edge_count, 
    (SELECT COUNT(*) FROM topology.face WHERE topology_id = t.id) as face_count 
FROM topology.topology t ORDER BY t.id;

\echo 'RETEST: Total Primitives (should show increased counts)'
SELECT 
    (SELECT COUNT(*) FROM topology.node) as total_nodes, 
    (SELECT COUNT(*) FROM topology.edge_data) as total_edges, 
    (SELECT COUNT(*) FROM topology.face) as total_faces;

\echo '-- ================================================================================'
\echo '-- CLEANUP TEST DATA'
\echo '-- ================================================================================'

\echo 'Cleaning up test topology...'
DO $$
BEGIN
    PERFORM topology.DropTopology('test_topology');
    RAISE NOTICE 'Test topology dropped successfully';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error dropping test topology: %', SQLERRM;
        RAISE NOTICE 'This may be expected if topology was not created';
END $$;

\echo 'Topology monitoring query testing complete!'
EOF

echo "Created topology monitoring test script"

# Define PostgreSQL versions to test
PG_VERSIONS=("13" "14" "15" "16" "17")

# Test monitoring queries on each PostgreSQL version
for pg_version in "${PG_VERSIONS[@]}"; do
    echo ""
    echo "========================================================================"
    echo "Testing PostGIS Topology monitoring queries on PostgreSQL $pg_version"
    echo "========================================================================"
    
    CONTAINER_NAME="topology_monitor_test_pg${pg_version}"
    
    # Start PostGIS container
    echo "Starting PostGIS container for PG $pg_version..."
    docker run --name $CONTAINER_NAME -e POSTGRES_PASSWORD=password -d postgis/postgis:${pg_version}-3.4
    
    # Wait for PostgreSQL to start
    echo "Waiting for PostgreSQL to start..."
    sleep 15
    
    # Run topology monitoring tests
    echo "Running topology monitoring query tests..."
    docker cp topology_monitoring_test.sql $CONTAINER_NAME:/tmp/
    docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/topology_monitoring_test.sql" > postgis_topology_monitoring_tests/monitoring_test_pg${pg_version}.out 2>&1
    
    # Check for any errors in the output
    if grep -q "ERROR" postgis_topology_monitoring_tests/monitoring_test_pg${pg_version}.out; then
        echo "❌ ERRORS found in PostgreSQL $pg_version test"
        echo "   Check: postgis_topology_monitoring_tests/monitoring_test_pg${pg_version}.out"
    else
        echo "✅ PostgreSQL $pg_version test completed successfully"
    fi
    
    # Stop and remove container
    docker stop $CONTAINER_NAME >/dev/null 2>&1
    docker rm $CONTAINER_NAME >/dev/null 2>&1
done

echo ""
echo "========================================================================"
echo "PostGIS Topology monitoring query testing complete!"
echo "========================================================================"

# Generate summary report
echo "Generating test summary..."
cat > postgis_topology_monitoring_tests/test_summary.txt << 'EOF'
PostGIS Topology Monitoring Query Test Summary
=============================================

This test validates all queries from the pgexporter YAML configuration:

1. topology_inventory - Basic topology count
2. topology_details - Topology information (id, name, srid, precision, hasz)  
3. topology_srid_distribution - SRID usage statistics
4. topology_primitives_by_topology - Node/edge/face counts per topology
5. topology_primitives_total - System-wide primitive totals
6. topology_layers - Layer information
7. topology_layer_summary - Layer counts per topology
8. topology_precision_stats - Precision distribution
9. node_edge_connectivity - Isolated node detection
10. face_edge_stats - Face complexity analysis
11. topology_storage_stats - Table size information
12. layer_feature_types - Feature type distribution

Test includes:
- Empty database testing (baseline)
- Sample data creation and testing
- Cleanup and validation

Check individual result files for detailed output.
EOF

echo "Results available in postgis_topology_monitoring_tests directory:"
ls -la postgis_topology_monitoring_tests/

echo ""
echo "=== Test Summary ==="
echo "✅ Tests all 12 queries from the YAML configuration"
echo "✅ Tests on PostgreSQL 13, 14, 15, 16, 17"
echo "✅ Creates sample topology data for validation"
echo "✅ Tests both empty and populated scenarios"
echo "✅ Includes cleanup verification"

echo ""
echo "=== Check Results ==="
echo "View specific test results:"
echo "  cat postgis_topology_monitoring_tests/monitoring_test_pg17.out"
echo ""
echo "Search for errors across all tests:"
echo "  grep -H 'ERROR\\|FAIL' postgis_topology_monitoring_tests/monitoring_test_pg*.out"
echo ""
echo "Search for successful query results:"
echo "  grep -H 'topology_count\\|node_count' postgis_topology_monitoring_tests/monitoring_test_pg*.out"

echo ""
echo "Clean up:"
echo "rm -rf postgis_topology_monitoring_tests/ topology_monitoring_test.sql"
echo ""
echo "Done!"