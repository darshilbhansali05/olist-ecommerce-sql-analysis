-- ============================================================
-- PHASE 1: ENVIRONMENT SETUP
-- Project: Olist E-Commerce SQL Analysis
-- Purpose: Create the working database and enable fast CSV
--          imports via LOAD DATA LOCAL INFILE.
-- ============================================================

-- 1. Create a dedicated schema/database for this project.
--    Keeping it isolated from other databases on the server
--    makes cleanup and grading/review easier.
CREATE DATABASE olist_ecommerce;

-- 2. Check whether local_infile is currently enabled on this server.
--    local_infile must be ON for LOAD DATA LOCAL INFILE to work
--    (this is the command Phase 3 uses to bulk-import the CSVs).
--    Expected output before the fix: Value = OFF
SHOW VARIABLES LIKE 'local_infile';

-- 3. Enable local_infile for the current server session.
--    NOTE: This setting is NOT permanent — it resets when the
--    MySQL server restarts. For a permanent fix, add the line
--    below to your my.cnf / my.ini config file under [mysqld]:
--        local_infile = 1
--    You will also need to enable "Allow LOAD DATA LOCAL INFILE"
--    in MySQL Workbench's connection settings (Advanced tab)
--    for the client side to permit it too — both server AND
--    client must agree, or you'll get Error 3948.
SET GLOBAL local_infile = 1;

-- ============================================================
-- End of Phase 1.
-- Next: switch to Phase 2 to create the table schema.
-- ============================================================
