CREATE SCHEMA IF NOT EXISTS q7_water;
SET search_path TO q7_water, public;
CREATE TABLE customers(customer_id SERIAL PRIMARY KEY,full_name VARCHAR(100) NOT NULL);
CREATE TABLE readings(reading_id SERIAL PRIMARY KEY,customer_id INT REFERENCES customers,reading_month DATE NOT NULL,
 previous_reading NUMERIC(12,2) NOT NULL CHECK(previous_reading>=0),current_reading NUMERIC(12,2) NOT NULL CHECK(current_reading>=0),
 UNIQUE(customer_id,reading_month),CHECK(reading_month=DATE_TRUNC('month',reading_month)::DATE));
CREATE TABLE bills(bill_id SERIAL PRIMARY KEY,reading_id INT UNIQUE REFERENCES readings,charge NUMERIC(12,2) NOT NULL,
 amount_paid NUMERIC(12,2) NOT NULL DEFAULT 0,due_on DATE NOT NULL,CHECK(amount_paid>=0 AND amount_paid<=charge));
CREATE TABLE receivable_snapshot(snapshot_date DATE PRIMARY KEY,total_due NUMERIC(12,2));
CREATE OR REPLACE FUNCTION fn_water_charge(p_units NUMERIC) RETURNS NUMERIC LANGUAGE plpgsql AS $$
BEGIN IF p_units IS NULL OR p_units<0 THEN RAISE EXCEPTION 'Units must be nonnegative'; END IF;
 RETURN ROUND(LEAST(p_units,10)*5+GREATEST(p_units-10,0)*8,2); END $$;
CREATE OR REPLACE PROCEDURE pr_generate_bill(p_reading_id INT,p_due_on DATE) LANGUAGE plpgsql AS $$
DECLARE v_units NUMERIC;
BEGIN SELECT current_reading-previous_reading INTO v_units FROM readings WHERE reading_id=p_reading_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown reading'; END IF;
 IF EXISTS(SELECT 1 FROM bills WHERE reading_id=p_reading_id) THEN RAISE EXCEPTION 'Bill already exists'; END IF;
 INSERT INTO bills(reading_id,charge,amount_paid,due_on) VALUES(p_reading_id,fn_water_charge(v_units),0,p_due_on); END $$;
CREATE OR REPLACE FUNCTION trg_reading_validate_fn() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN IF NEW.current_reading<NEW.previous_reading THEN RAISE EXCEPTION 'Current reading below previous reading'; END IF; RETURN NEW; END $$;
CREATE TRIGGER trg_reading_validate BEFORE INSERT OR UPDATE ON readings FOR EACH ROW EXECUTE FUNCTION trg_reading_validate_fn();
CREATE VIEW v_overdue_bills AS SELECT c.full_name,b.due_on,b.charge-b.amount_paid AS outstanding_amount
FROM bills b JOIN readings r USING(reading_id) JOIN customers c USING(customer_id)
WHERE b.due_on<CURRENT_DATE AND b.amount_paid<b.charge;
CREATE INDEX idx_bills_due_on ON bills(due_on);
-- EXPLAIN SELECT * FROM bills WHERE due_on<CURRENT_DATE AND amount_paid<charge;
CREATE OR REPLACE PROCEDURE pr_refresh_receivables() LANGUAGE plpgsql AS $$
BEGIN INSERT INTO receivable_snapshot(snapshot_date,total_due)
 SELECT CURRENT_DATE,COALESCE(SUM(charge-amount_paid),0) FROM bills WHERE amount_paid<charge
 ON CONFLICT(snapshot_date) DO UPDATE SET total_due=EXCLUDED.total_due; END $$;
INSERT INTO customers(full_name) VALUES('Customer One'),('Customer Two'),('Customer Three');
INSERT INTO readings(customer_id,reading_month,previous_reading,current_reading) VALUES
(1,DATE '2026-10-01',0,0),(1,DATE '2026-11-01',0,10),(2,DATE '2026-10-01',10,20),
(2,DATE '2026-11-01',20,25),(3,DATE '2026-10-01',5,22),(3,DATE '2026-11-01',22,30);
CALL pr_generate_bill(1,CURRENT_DATE+30); CALL pr_generate_bill(2,CURRENT_DATE+30); CALL pr_generate_bill(3,CURRENT_DATE+30);
CALL pr_generate_bill(4,CURRENT_DATE+30); CALL pr_generate_bill(5,CURRENT_DATE+30); CALL pr_generate_bill(6,CURRENT_DATE+30);
SELECT * FROM v_overdue_bills; CALL pr_refresh_receivables(); SELECT * FROM receivable_snapshot;