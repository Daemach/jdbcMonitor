CREATE DATABASE IF NOT EXISTS jdbcmonitor_test;
USE jdbcmonitor_test;

DROP TABLE IF EXISTS monitor_test;

CREATE TABLE monitor_test (
    id INT AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(255) NOT NULL,
    value VARCHAR(500) NULL,
    active TINYINT(1) NOT NULL DEFAULT 1,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

INSERT INTO monitor_test (name, value) VALUES
    ('alpha', 'one'),
    ('bravo', 'two'),
    ('charlie', 'three'),
    ('delta', NULL),
    ('echo', 'five');
