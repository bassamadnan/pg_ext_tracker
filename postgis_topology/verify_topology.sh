#!/bin/bash
# Script to test PostGIS Topology monitoring using ANALYZE to force statistics updates

# Save the current directory
SCRIPT_DIR=$(pwd)

# Create directory for test results
mkdir -p topology_analyze_tests

# Create the ANALYZE-based topology test queries
cat > topology_analyze_test.sql << 'EOF'
\echo '-- ================================================================================'
\echo '-- POSTGIS TOPOLOGY WITH ANALYZE MONITORING TEST'
\echo '-- ================================================================================'

-- Ensure PostGIS and Topology extensions are installed
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

\echo '-- ================================================================================'
\echo '-- CREATE TEST TOPOLOGIES WITH DATA'
\echo '-- ================================================================================'

-- Create multiple topologies for testing
\echo 'Creating test topologies...'
DO $$
DECLARE
    topo1_id integer;
    topo2_id integer;
    topo3_id integer;
BEGIN
    -- Create topology 1: city_network
    SELECT topology.CreateTopology('city_network', 4326, 0.001) INTO topo1_id;
    RAISE NOTICE 'Created city_network topology with ID: %', topo1_id;
    
    -- Add data to city_network
    PERFORM topology.ST_AddIsoNode('city_network', NULL, ST_GeomFromText('POINT(0 0)', 4326));
    PERFORM topology.ST_AddIsoNode('city_network', NULL, ST_GeomFromText('POINT(1 0)', 4326));
    PERFORM topology.ST_AddIsoNode('city_network', NULL, ST_GeomFromText('POINT(0 1)', 4326));
    PERFORM topology.ST_AddIsoNode('city_network', NULL, ST_GeomFromText('POINT(1 1)', 4326));
    
    -- Add edges to city_network  
    PERFORM topology.ST_AddEdgeNewFaces('city_network', 1, 2, ST_GeomFromText('LINESTRING(0 0, 1 0)', 4326));
    PERFORM topology.ST_AddEdgeNewFaces('city_network', 2, 4, ST_GeomFromText('LINESTRING(1 0, 1 1)', 4326));
    PERFORM topology.ST_AddEdgeNewFaces('city_network', 4, 3, ST_GeomFromText('LINESTRING(1 1, 0 1)', 4326));
    
    -- Create topology 2: road_system
    SELECT topology.CreateTopology('road_system', 3857, 0.01) INTO topo2_id;
    RAISE NOTICE 'Created road_system topology with ID: %', topo2_id;
    
    -- Add data to road_system
    PERFORM topology.ST_AddIsoNode('road_system', NULL, ST_GeomFromText('POINT(100 100)', 3857));
    PERFORM topology.ST_AddIsoNode('road_system', NULL, ST_GeomFromText('POINT(200 100)', 3857));
    
    -- Add edge to road_system
    PERFORM topology.ST_AddEdgeNewFaces('road_system', 1, 2, ST_GeomFromText('LINESTRING(100 100, 200 100)', 3857));
    
    -- Create topology 3: empty_topology (no data)
    SELECT topology.CreateTopology('empty_topology', 4269, 0.0001) INTO topo3_id;
    RAISE NOTICE 'Created empty_topology with ID: %', topo3_id;
    
    RAISE NOTICE 'All test topologies created successfully';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error creating topologies: %', SQLERRM;
END $$;

\echo '-- ================================================================================'
\echo '-- FORCE ANALYZE ON ALL TOPOLOGY TABLES'
\echo '-- ================================================================================'

\echo 'Running ANALYZE on all topology tables to update statistics...'
DO $$
DECLARE
    topo_name text;
BEGIN
    FOR topo_name IN SELECT name FROM topology.topology ORDER BY id LOOP
        EXECUTE format('ANALYZE %I.node', topo_name);
        EXECUTE format('ANALYZE %I.edge_data', topo_name);
        EXECUTE format('ANALYZE %I.face', topo_name);
        RAISE NOTICE 'Analyzed tables for topology: %', topo_name;
    END LOOP;
END $$;

\echo '-- ================================================================================'
\echo '-- TEST QUERIES AFTER ANALYZE'
\echo '-- ================================================================================'

\echo 'TEST 1: Basic Topology Information'
SELECT id, name, srid, precision, hasz FROM topology.topology ORDER BY id;

\echo 'TEST 2: Node Counts After ANALYZE'
\echo 'Query: Join topology info with pg_stat_user_tables for node counts'
SELECT 
    t.name as topology_name,
    t.srid,
    COALESCE(pst.n_live_tup, 0) as live_node_count,
    COALESCE(pst.n_tup_ins, 0) as inserted_nodes,
    COALESCE(pst.n_tup_upd, 0) as updated_nodes,
    COALESCE(pst.n_tup_del, 0) as deleted_nodes
FROM topology.topology t
LEFT JOIN pg_stat_user_tables pst ON pst.schemaname = t.name AND pst.relname = 'node'
ORDER BY t.id;

\echo 'TEST 3: Edge Counts After ANALYZE'
SELECT 
    t.name as topology_name,
    t.srid,
    COALESCE(pst.n_live_tup, 0) as live_edge_count,
    COALESCE(pst.n_tup_ins, 0) as inserted_edges
FROM topology.topology t
LEFT JOIN pg_stat_user_tables pst ON pst.schemaname = t.name AND pst.relname = 'edge_data'
ORDER BY t.id;

\echo 'TEST 4: Face Counts After ANALYZE'
SELECT 
    t.name as topology_name,
    t.srid,
    COALESCE(pst.n_live_tup, 0) as live_face_count,
    COALESCE(pst.n_tup_ins, 0) as inserted_faces
FROM topology.topology t
LEFT JOIN pg_stat_user_tables pst ON pst.schemaname = t.name AND pst.relname = 'face'
ORDER BY t.id;

\echo 'TEST 5: Combined Primitives Summary After ANALYZE'
SELECT 
    t.name as topology_name,
    t.srid,
    t.precision,
    COALESCE(nodes.n_live_tup, 0) as node_count,
    COALESCE(edges.n_live_tup, 0) as edge_count,
    COALESCE(faces.n_live_tup, 0) as face_count,
    COALESCE(nodes.n_live_tup, 0) + COALESCE(edges.n_live_tup, 0) + COALESCE(faces.n_live_tup, 0) as total_primitives
FROM topology.topology t
LEFT JOIN pg_stat_user_tables nodes ON nodes.schemaname = t.name AND nodes.relname = 'node'
LEFT JOIN pg_stat_user_tables edges ON edges.schemaname = t.name AND edges.relname = 'edge_data'
LEFT JOIN pg_stat_user_tables faces ON faces.schemaname = t.name AND faces.relname = 'face'
ORDER BY t.id;

\echo 'TEST 6: System-Wide Statistics After ANALYZE'
SELECT 
    COUNT(*) as total_topologies,
    COUNT(DISTINCT t.srid) as unique_srids,
    AVG(t.precision) as avg_precision,
    SUM(COALESCE(nodes.n_live_tup, 0)) as total_nodes,
    SUM(COALESCE(edges.n_live_tup, 0)) as total_edges,
    SUM(COALESCE(faces.n_live_tup, 0)) as total_faces
FROM topology.topology t
LEFT JOIN pg_stat_user_tables nodes ON nodes.schemaname = t.name AND nodes.relname = 'node'
LEFT JOIN pg_stat_user_tables edges ON edges.schemaname = t.name AND edges.relname = 'edge_data'
LEFT JOIN pg_stat_user_tables faces ON faces.schemaname = t.name AND faces.relname = 'face';

\echo 'TEST 7: Table Storage Information'
SELECT 
    t.name as topology_name,
    pg_size_pretty(
        COALESCE((SELECT pg_total_relation_size(t.name||'.node')), 0) +
        COALESCE((SELECT pg_total_relation_size(t.name||'.edge_data')), 0) +
        COALESCE((SELECT pg_total_relation_size(t.name||'.face')), 0)
    ) as total_topology_size,
    pg_size_pretty(COALESCE((SELECT pg_total_relation_size(t.name||'.node')), 0)) as node_table_size,
    pg_size_pretty(COALESCE((SELECT pg_total_relation_size(t.name||'.edge_data')), 0)) as edge_table_size,
    pg_size_pretty(COALESCE((SELECT pg_total_relation_size(t.name||'.face')), 0)) as face_table_size
FROM topology.topology t
ORDER BY t.id;

\echo 'TEST 8: SRID Distribution'
SELECT 
    t.srid,
    COUNT(*) as topology_count,
    SUM(COALESCE(nodes.n_live_tup, 0)) as total_nodes_for_srid,
    SUM(COALESCE(edges.n_live_tup, 0)) as total_edges_for_srid
FROM topology.topology t
LEFT JOIN pg_stat_user_tables nodes ON nodes.schemaname = t.name AND nodes.relname = 'node'
LEFT JOIN pg_stat_user_tables edges ON edges.schemaname = t.name AND edges.relname = 'edge_data'
GROUP BY t.srid
ORDER BY topology_count DESC;

\echo 'TEST 9: Topology Health and Activity'
SELECT 
    t.name as topology_name,
    t.srid,
    CASE WHEN nodes.relname IS NOT NULL THEN 'YES' ELSE 'NO' END as has_node_table,
    CASE WHEN edges.relname IS NOT NULL THEN 'YES' ELSE 'NO' END as has_edge_table,
    CASE WHEN faces.relname IS NOT NULL THEN 'YES' ELSE 'NO' END as has_face_table,
    COALESCE(nodes.n_live_tup, 0) as current_node_count,
    COALESCE(edges.n_live_tup, 0) as current_edge_count,
    CASE 
        WHEN COALESCE(nodes.n_live_tup, 0) + COALESCE(edges.n_live_tup, 0) = 0 THEN 'EMPTY'
        WHEN COALESCE(nodes.n_live_tup, 0) > 0 AND COALESCE(edges.n_live_tup, 0) = 0 THEN 'NODES_ONLY'
        WHEN COALESCE(nodes.n_live_tup, 0) > 0 AND COALESCE(edges.n_live_tup, 0) > 0 THEN 'ACTIVE'
        ELSE 'UNKNOWN'
    END as topology_status
FROM topology.topology t
LEFT JOIN pg_stat_user_tables nodes ON nodes.schemaname = t.name AND nodes.relname = 'node'
LEFT JOIN pg_stat_user_tables edges ON edges.schemaname = t.name AND edges.relname = 'edge_data'
LEFT JOIN pg_stat_user_tables faces ON faces.schemaname = t.name AND faces.relname = 'face'
ORDER BY t.id;

\echo 'TEST 10: Verification - Direct Count Comparison'
\echo 'This shows what the counts should be (for verification):'
DO $$
DECLARE
    topo_name text;
    node_count integer;
    edge_count integer;
    face_count integer;
BEGIN
    FOR topo_name IN SELECT name FROM topology.topology ORDER BY id LOOP
        EXECUTE format('SELECT COUNT(*) FROM %I.node', topo_name) INTO node_count;
        EXECUTE format('SELECT COUNT(*) FROM %I.edge_data', topo_name) INTO edge_count;
        EXECUTE format('SELECT COUNT(*) FROM %I.face', topo_name) INTO face_count;
        
        RAISE NOTICE 'VERIFICATION - % | Nodes: %, Edges: %, Faces: %', 
                     topo_name, node_count, edge_count, face_count;
    END LOOP;
END $$;

\echo '-- ================================================================================'
\echo '-- CLEANUP TEST DATA'
\echo '-- ================================================================================'

\echo 'Cleaning up test topologies...'
DO $$
DECLARE
    topo_name text;
BEGIN
    FOR topo_name IN SELECT name FROM topology.topology ORDER BY id LOOP
        BEGIN
            PERFORM topology.DropTopology(topo_name);
            RAISE NOTICE 'Dropped topology: %', topo_name;
        EXCEPTION
            WHEN OTHERS THEN
                RAISE NOTICE 'Error dropping topology %: %', topo_name, SQLERRM;
        END;
    END LOOP;
END $$;

\echo 'Topology ANALYZE-based monitoring test complete!'
EOF

echo "Created ANALYZE-based topology test script"

# Test on PostgreSQL 17
echo ""
echo "========================================================================"
echo "Testing PostGIS Topology with ANALYZE approach on PostgreSQL 17"
echo "========================================================================"

CONTAINER_NAME="topology_analyze_test_pg17"

# Start PostGIS container
echo "Starting PostGIS container..."
docker run --name $CONTAINER_NAME -e POSTGRES_PASSWORD=password -d postgis/postgis:17-3.4

# Wait for PostgreSQL to start
echo "Waiting for PostgreSQL to start..."
sleep 15

# Run ANALYZE-based topology tests
echo "Running ANALYZE-based topology monitoring tests..."
docker cp topology_analyze_test.sql $CONTAINER_NAME:/tmp/
docker exec $CONTAINER_NAME bash -c "psql -U postgres -f /tmp/topology_analyze_test.sql" > topology_analyze_tests/analyze_test_results.out 2>&1

# Check results
echo "Test completed. Analyzing results..."
if grep -q "ERROR" topology_analyze_tests/analyze_test_results.out; then
    echo "❌ ERRORS found in test results"
    grep "ERROR" topology_analyze_tests/analyze_test_results.out | head -3
else
    echo "✅ No SQL errors found"
fi

# Stop and remove container
docker stop $CONTAINER_NAME >/dev/null 2>&1
docker rm $CONTAINER_NAME >/dev/null 2>&1

echo ""
echo "========================================================================"
echo "ANALYZE Test Results Summary"
echo "========================================================================"

# Show key results comparing before/after ANALYZE
echo "=== Node Counts After ANALYZE ==="
grep -A 8 "TEST 2:" topology_analyze_tests/analyze_test_results.out

echo ""
echo "=== Combined Primitives Summary ==="
grep -A 8 "TEST 5:" topology_analyze_tests/analyze_test_results.out

echo ""
echo "=== System-Wide Statistics ==="
grep -A 5 "TEST 6:" topology_analyze_tests/analyze_test_results.out

echo ""
echo "=== Verification Comparison ==="
echo "Direct counts (what it should be):"
grep "VERIFICATION" topology_analyze_tests/analyze_test_results.out

echo ""
echo "=== Complete Results ==="
echo "View full test output: cat topology_analyze_tests/analyze_test_results.out"
echo "Clean up: rm -rf topology_analyze_tests/ topology_analyze_test.sql"
echo ""
echo "This test shows if ANALYZE fixes the statistics issue!"
echo "Done!"