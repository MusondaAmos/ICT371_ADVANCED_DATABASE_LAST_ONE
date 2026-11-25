CREATE SCHEMA IF NOT EXISTS q8_fleet;
SET search_path TO q8_fleet, public;
CREATE TABLE vehicles(vehicle_id SERIAL PRIMARY KEY,registration VARCHAR(30) UNIQUE NOT NULL,
 current_odometer NUMERIC(12,2) NOT NULL CHECK(current_odometer>=0),
 last_service_odometer NUMERIC(12,2) NOT NULL CHECK(last_service_odometer>=0 AND last_service_odometer<=current_odometer));
CREATE TABLE trips(trip_id SERIAL PRIMARY KEY,vehicle_id INT REFERENCES vehicles,trip_on DATE NOT NULL,
 start_odometer NUMERIC(12,2) NOT NULL,end_odometer NUMERIC(12,2) NOT NULL,CHECK(end_odometer>start_odometer));
CREATE TABLE service_alerts(vehicle_id INT PRIMARY KEY REFERENCES vehicles,km_since_service NUMERIC(12,2),flagged_on DATE);
CREATE OR REPLACE FUNCTION fn_service_due(p_vehicle_id INT) RETURNS BOOLEAN LANGUAGE plpgsql AS $$
DECLARE v_km NUMERIC;
BEGIN SELECT current_odometer-last_service_odometer INTO v_km FROM vehicles WHERE vehicle_id=p_vehicle_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown vehicle'; END IF; RETURN v_km>=5000; END $$;
CREATE OR REPLACE PROCEDURE pr_record_trip(p_vehicle_id INT,p_trip_on DATE,p_start NUMERIC,p_end NUMERIC)
LANGUAGE plpgsql AS $$
BEGIN IF NOT EXISTS(SELECT 1 FROM vehicles WHERE vehicle_id=p_vehicle_id) THEN RAISE EXCEPTION 'Unknown vehicle'; END IF;
 IF p_end<=p_start THEN RAISE EXCEPTION 'End odometer must be greater'; END IF;
 INSERT INTO trips(vehicle_id,trip_on,start_odometer,end_odometer) VALUES(p_vehicle_id,p_trip_on,p_start,p_end); END $$;
CREATE OR REPLACE FUNCTION trg_trip_fn() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_current NUMERIC;
BEGIN SELECT current_odometer INTO v_current FROM vehicles WHERE vehicle_id=NEW.vehicle_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown vehicle'; END IF;
 IF NEW.start_odometer<>v_current THEN RAISE EXCEPTION 'Trip must start at current odometer (%)',v_current; END IF;
 IF NEW.end_odometer<=NEW.start_odometer THEN RAISE EXCEPTION 'Invalid trip mileage'; END IF;
 UPDATE vehicles SET current_odometer=NEW.end_odometer WHERE vehicle_id=NEW.vehicle_id; RETURN NEW; END $$;
CREATE TRIGGER trg_trip_update_odometer BEFORE INSERT ON trips FOR EACH ROW EXECUTE FUNCTION trg_trip_fn();
CREATE VIEW v_service_due AS SELECT registration,current_odometer-last_service_odometer AS km_since_service
FROM vehicles WHERE current_odometer-last_service_odometer>=5000;
CREATE INDEX idx_trips_vehicle_trip_on ON trips(vehicle_id,trip_on);
-- EXPLAIN SELECT * FROM trips WHERE vehicle_id=1 AND trip_on BETWEEN DATE '2026-11-01' AND DATE '2026-11-30';
CREATE OR REPLACE PROCEDURE pr_refresh_service_alerts() LANGUAGE plpgsql AS $$
BEGIN INSERT INTO service_alerts(vehicle_id,km_since_service,flagged_on)
 SELECT vehicle_id,current_odometer-last_service_odometer,CURRENT_DATE FROM vehicles
 WHERE current_odometer-last_service_odometer>=5000
 ON CONFLICT(vehicle_id) DO UPDATE SET km_since_service=EXCLUDED.km_since_service,flagged_on=EXCLUDED.flagged_on;
 DELETE FROM service_alerts WHERE vehicle_id IN(SELECT vehicle_id FROM vehicles WHERE current_odometer-last_service_odometer<5000); END $$;
INSERT INTO vehicles(registration,current_odometer,last_service_odometer) VALUES('ABC001',10000,5000),('ABC002',3000,0),('ABC003',7000,4000);
CALL pr_record_trip(1,CURRENT_DATE,10000,10500); CALL pr_record_trip(2,CURRENT_DATE,3000,3200);
CALL pr_record_trip(3,CURRENT_DATE,7000,7500); CALL pr_record_trip(1,CURRENT_DATE,10500,11000);
CALL pr_record_trip(2,CURRENT_DATE,3200,3400); CALL pr_record_trip(3,CURRENT_DATE,7500,8000);
SELECT * FROM v_service_due; CALL pr_refresh_service_alerts(); SELECT * FROM service_alerts;