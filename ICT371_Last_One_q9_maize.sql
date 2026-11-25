CREATE SCHEMA IF NOT EXISTS q9_maize;
SET search_path TO q9_maize, public;
CREATE TABLE farmers(farmer_id SERIAL PRIMARY KEY,farmer_number VARCHAR(30) UNIQUE,full_name VARCHAR(100) NOT NULL);
CREATE TABLE deliveries(delivery_id SERIAL PRIMARY KEY,farmer_id INT REFERENCES farmers,grade CHAR(1) NOT NULL,
 weight_kg NUMERIC(12,2) NOT NULL,unit_rate NUMERIC(10,2) NOT NULL,total_value NUMERIC(12,2) NOT NULL,
 delivered_on DATE NOT NULL,is_paid BOOLEAN NOT NULL DEFAULT FALSE);
CREATE TABLE daily_purchases(purchase_date DATE PRIMARY KEY,total_weight NUMERIC(12,2),total_value NUMERIC(12,2));
CREATE OR REPLACE FUNCTION fn_maize_rate(p_grade CHAR) RETURNS NUMERIC LANGUAGE plpgsql AS $$
BEGIN IF p_grade IS NULL THEN RAISE EXCEPTION 'Grade required'; END IF;
 CASE UPPER(p_grade) WHEN 'A' THEN RETURN 5; WHEN 'B' THEN RETURN 4; WHEN 'C' THEN RETURN 3;
 ELSE RAISE EXCEPTION 'Unsupported grade'; END CASE; END $$;
CREATE OR REPLACE PROCEDURE pr_receive_delivery(p_farmer_id INT,p_grade CHAR,p_weight NUMERIC,p_date DATE)
LANGUAGE plpgsql AS $$
BEGIN IF NOT EXISTS(SELECT 1 FROM farmers WHERE farmer_id=p_farmer_id) THEN RAISE EXCEPTION 'Unknown farmer'; END IF;
 IF p_weight IS NULL OR p_weight<=0 OR p_date IS NULL THEN RAISE EXCEPTION 'Invalid delivery'; END IF;
 INSERT INTO deliveries(farmer_id,grade,weight_kg,unit_rate,total_value,delivered_on,is_paid)
 VALUES(p_farmer_id,UPPER(p_grade),p_weight,0,0,p_date,false); END $$;
CREATE OR REPLACE FUNCTION trg_delivery_pricing_fn() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN IF NEW.weight_kg IS NULL OR NEW.weight_kg<=0 THEN RAISE EXCEPTION 'Weight must be positive'; END IF;
 NEW.unit_rate:=fn_maize_rate(NEW.grade); NEW.total_value:=NEW.weight_kg*NEW.unit_rate; RETURN NEW; END $$;
CREATE TRIGGER trg_delivery_pricing BEFORE INSERT OR UPDATE ON deliveries FOR EACH ROW EXECUTE FUNCTION trg_delivery_pricing_fn();
CREATE VIEW v_farmer_amount_due AS SELECT f.farmer_number,f.full_name,COALESCE(SUM(d.total_value) FILTER(WHERE NOT d.is_paid),0) AS unpaid_value
FROM farmers f LEFT JOIN deliveries d USING(farmer_id) GROUP BY f.farmer_id,f.farmer_number,f.full_name;
CREATE INDEX idx_deliveries_farmer_date ON deliveries(farmer_id,delivered_on);
-- EXPLAIN SELECT * FROM deliveries WHERE farmer_id=1 AND delivered_on BETWEEN DATE '2026-11-01' AND DATE '2026-11-30';
CREATE OR REPLACE PROCEDURE pr_refresh_purchases(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN INSERT INTO daily_purchases(purchase_date,total_weight,total_value)
 SELECT p_day,COALESCE(SUM(weight_kg),0),COALESCE(SUM(total_value),0) FROM deliveries WHERE delivered_on=p_day
 ON CONFLICT(purchase_date) DO UPDATE SET total_weight=EXCLUDED.total_weight,total_value=EXCLUDED.total_value; END $$;
INSERT INTO farmers(farmer_number,full_name) VALUES('F001','Farmer One'),('F002','Farmer Two'),('F003','Farmer Three');
CALL pr_receive_delivery(1,'A',100,CURRENT_DATE); CALL pr_receive_delivery(1,'B',50,CURRENT_DATE);
CALL pr_receive_delivery(2,'C',75,CURRENT_DATE); CALL pr_receive_delivery(2,'A',200,CURRENT_DATE);
CALL pr_receive_delivery(3,'B',120,CURRENT_DATE); CALL pr_receive_delivery(3,'C',60,CURRENT_DATE);
UPDATE deliveries SET is_paid=true WHERE delivery_id=2;
SELECT * FROM v_farmer_amount_due; CALL pr_refresh_purchases(CURRENT_DATE); SELECT * FROM daily_purchases;