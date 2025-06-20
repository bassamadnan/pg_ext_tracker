-- Enable the extension
ALTER SYSTEM SET shared_preload_libraries = 'pg_stat_statements';
-- Create the extension with specific version
CREATE EXTENSION pg_stat_statements VERSION '1.11';
-- Verify installation
SELECT name, default_version, installed_version FROM pg_available_extensions WHERE name = 'pg_stat_statements';
