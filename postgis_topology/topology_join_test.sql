\echo '-- ================================================================================'
\echo '-- POSTGIS TOPOLOGY JOIN-BASED MONITORING TEST'
\echo '-- ================================================================================'

-- Ensure PostGIS and Topology extensions are installed
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS postgis_topology;

\echo '-- ================================================================================'
\echo '-- CREATE MULTIPLE TEST TOPOLOGIES WITH DATA'
\echo '-- ================================================================================'

-- Create multiple topologies for comprehensive testing
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
    
    -- Create topology 3: empty_topology (just the structure, no data)
    SELECT topology.CreateTopology('empty_topology', 4269, 0.0001) INTO topo3_id;
    RAISE NOTICE 'Created empty_topology with ID: %', topo3_id;
    
    RAISE NOTICE 'All test topologies created successfully';
    
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Error creating topologies: %', SQLERRM;
END $$;

\echo '-- ================================================================================'
\echo '-- TEST JOIN-BASED QUERIES'
\echo '-- ================================================================================'

\echo 'TEST 1: Basic Topology Information'
\echo 'Query: Direct from topology.topology table'
SELECT id, name, srid, precision, hasz FROM topology.topology ORDER BY id;

\echo 'TEST 2: Node Counts Using System Catalogs'
\echo 'Query: Join topology info with pg_stat_user_tables for node counts'
SELECT 
    t.name as topology_name,
    t.srid,
    COALESCE(pst.n_tup_ins + pst.n_tup_upd - pst.n_tup_del, 0) as estimated_node_count,
    COALESCE(pst.n_live_tup, 0) as live_node_count
FROM topology.topology t
LEFT JOIN pg_stat_user_tables pst ON pst.schemaname = t.name AND pst.relname = 'node'
ORDER BY t.id;

\echo 'TEST 3: Edge Counts Using System Catalogs'
\echo 'Query: Join topology info with pg_stat_user_tables for edge counts'
SELECT 
    t.name as topology_name,
    t.srid,
    COALESCE(pst.n_live_tup, 0) as live_edge_count
FROM topology.topology t
LEFT JOIN pg_stat_user_tables pst ON pst.schemaname = t.name AND pst.relname = 'edge_data'
ORDER BY t.id;

\echo 'TEST 4: Face Counts Using System Catalogs'
\echo 'Query: Join topology info with pg_stat_user_tables for face counts'
SELECT 
    t.name as topology_name,
    t.srid,
    COALESCE(pst.n_live_tup, 0) as live_face_count
FROM topology.topology t
LEFT JOIN pg_stat_user_tables pst ON pst.schemaname = t.name AND pst.relname = 'face'
ORDER BY t.id;

\echo 'TEST 5: Combined Primitives Summary'
\echo 'Query: All primitives in one query using multiple joins'
SELECT 
    t.name as topology_name,
    t.srid,t.precision,
    COALESCE(nodes.n_live_tup, 0) as node_count,
    COALESCE(edges.n_live_tup, 0) as edge_count,
    COALESCE(faces.n_live_tup, 0) as face_count
FROM topology.topology t
LEFT JOIN pg_stat_user_tables nodes ON nodes.schemaname = t.name AND nodes.relname = 'node'
LEFT JOIN pg_stat_user_tables edges ON edges.schemaname = t.name AND edges.relname = 'edge_data'  
LEFT JOIN pg_stat_user_tables faces ON faces.schemaname = t.name AND faces.relname = 'face'
ORDER BY t.id;

\echo 'TEST 6: Table Size Information'
\echo 'Query: Storage usage per topology using pg_class'
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

\echo 'TEST 7: System-Wide Topology Statistics'
\echo 'Query: Aggregated stats across all topologies'
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

\echo 'TEST 8: Topology Health Check'
\echo 'Query: Check for topologies with missing tables'
SELECT 
    t.name as topology_name,
    CASE WHEN nodes.relname IS NOT NULL THEN 'YES' ELSE 'NO' END as has_node_table,
    CASE WHEN edges.relname IS NOT NULL THEN 'YES' ELSE 'NO' END as has_edge_table,
    CASE WHEN faces.relname IS NOT NULL THEN 'YES' ELSE 'NO' END as has_face_table
FROM topology.topology t
LEFT JOIN pg_stat_user_tables nodes ON nodes.schemaname = t.name AND nodes.relname = 'node'
LEFT JOIN pg_stat_user_tables edges ON edges.schemaname = t.name AND edges.relname = 'edge_data'
LEFT JOIN pg_stat_user_tables faces ON faces.schemaname = t.name AND faces.relname = 'face'
ORDER BY t.id;

\echo 'TEST 9: Layer Information with Topology Details'
\echo 'Query: Join layers with topology information'
SELECT 
    t.name as topology_name,
    l.layer_id,
    l.feature_type,
    CASE 
        WHEN l.feature_type = 1 THEN 'Point'
        WHEN l.feature_type = 2 THEN 'Line' 
        WHEN l.feature_type = 3 THEN 'Polygon'
        WHEN l.feature_type = 4 THEN 'Collection'
        ELSE 'Unknown'
    END as feature_type_name,
    l.level
FROM topology.topology t
LEFT JOIN topology.layer l ON l.topology_id = t.id
ORDER BY t.id, l.layer_id;

\echo 'TEST 10: Direct Table Access Verification'
\echo 'Query: Verify we can actually access the topology tables directly'
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
        
        RAISE NOTICE 'Topology % - Nodes: %, Edges: %, Faces: %', 
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

\echo 'Topology JOIN-based monitoring test complete!'
