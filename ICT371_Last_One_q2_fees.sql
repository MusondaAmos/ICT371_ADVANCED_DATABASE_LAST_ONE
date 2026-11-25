CREATE SCHEMA IF NOT EXISTS q2_fees;
SET search_path TO q2_fees, public;
CREATE TABLE students(student_id SERIAL PRIMARY KEY,student_number VARCHAR(30) UNIQUE NOT NULL,
 full_name VARCHAR(100) NOT NULL,fee_due NUMERIC(12,2) NOT NULL CHECK(fee_due>=0));
CREATE TABLE payments(payment_id SERIAL PRIMARY KEY,student_id INT NOT NULL REFERENCES students,
 amount NUMERIC(12,2) NOT NULL CHECK(amount>0),paid_on DATE NOT NULL);
CREATE TABLE payment_audit(audit_id SERIAL PRIMARY KEY,payment_id INT REFERENCES payments,
 student_id INT REFERENCES students,amount NUMERIC(12,2),logged_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE daily_collections(collection_date DATE PRIMARY KEY,payment_count INT NOT NULL,total_amount NUMERIC(12,2) NOT NULL);

CREATE OR REPLACE FUNCTION fn_fee_balance(p_student_id INT) RETURNS NUMERIC
LANGUAGE plpgsql AS $$
DECLARE v_due NUMERIC; v_paid NUMERIC;
BEGIN
 SELECT fee_due INTO v_due FROM students WHERE student_id=p_student_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown student'; END IF;
 SELECT COALESCE(SUM(amount),0) INTO v_paid FROM payments WHERE student_id=p_student_id;
 RETURN v_due-v_paid;
END $$;

CREATE OR REPLACE PROCEDURE pr_receive_payment(p_student_id INT,p_amount NUMERIC,p_paid_on DATE)
LANGUAGE plpgsql AS $$
BEGIN
 IF p_amount IS NULL OR p_amount<=0 OR p_paid_on IS NULL THEN RAISE EXCEPTION 'Invalid payment'; END IF;
 IF NOT EXISTS(SELECT 1 FROM students WHERE student_id=p_student_id) THEN RAISE EXCEPTION 'Unknown student'; END IF;
 IF p_amount>fn_fee_balance(p_student_id) THEN RAISE EXCEPTION 'Payment exceeds balance'; END IF;
 INSERT INTO payments(student_id,amount,paid_on) VALUES(p_student_id,p_amount,p_paid_on);
END $$;

CREATE OR REPLACE FUNCTION trg_payment_audit_fn() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN INSERT INTO payment_audit(payment_id,student_id,amount)
 VALUES(NEW.payment_id,NEW.student_id,NEW.amount); RETURN NEW; END $$;
CREATE TRIGGER trg_payment_audit AFTER INSERT ON payments FOR EACH ROW EXECUTE FUNCTION trg_payment_audit_fn();

CREATE VIEW v_fee_balances AS SELECT student_number,full_name,fn_fee_balance(student_id) AS outstanding_balance
FROM students WHERE fn_fee_balance(student_id)>0;
CREATE INDEX idx_payments_student_paid_on ON payments(student_id,paid_on);
-- EXPLAIN SELECT * FROM payments WHERE student_id=1 AND paid_on BETWEEN DATE '2026-11-01' AND DATE '2026-11-30';
CREATE OR REPLACE PROCEDURE pr_refresh_collections(p_day DATE) LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO daily_collections(collection_date,payment_count,total_amount)
 SELECT p_day,COUNT(*),COALESCE(SUM(amount),0) FROM payments WHERE paid_on=p_day
 ON CONFLICT(collection_date) DO UPDATE SET payment_count=EXCLUDED.payment_count,total_amount=EXCLUDED.total_amount;
END $$;
INSERT INTO students(student_number,full_name,fee_due) VALUES
('ST001','Student One',5000),('ST002','Student Two',3500),('ST003','Student Three',2000);
CALL pr_receive_payment(1,500,CURRENT_DATE); CALL pr_receive_payment(1,750,CURRENT_DATE);
CALL pr_receive_payment(1,250,CURRENT_DATE); CALL pr_receive_payment(2,1000,CURRENT_DATE);
CALL pr_receive_payment(2,500,CURRENT_DATE); CALL pr_receive_payment(2,200,CURRENT_DATE);
SELECT * FROM v_fee_balances; CALL pr_refresh_collections(CURRENT_DATE);
SELECT * FROM daily_collections;