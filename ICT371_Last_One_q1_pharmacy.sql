CREATE SCHEMA IF NOT EXISTS q1_pharmacy;
SET search_path TO q1_pharmacy, public;

CREATE TABLE medicines (
 medicine_id SERIAL PRIMARY KEY, medicine_name VARCHAR(100) NOT NULL,
 unit_price NUMERIC(10,2) NOT NULL CHECK(unit_price>0),
 stock_qty INT NOT NULL CHECK(stock_qty>=0));
CREATE TABLE sales (
 sale_id SERIAL PRIMARY KEY, medicine_id INT NOT NULL REFERENCES medicines,
 quantity INT NOT NULL CHECK(quantity>0), unit_price NUMERIC(10,2) NOT NULL CHECK(unit_price>0),
 sold_on DATE NOT NULL);
CREATE TABLE stock_audit (
 audit_id SERIAL PRIMARY KEY, medicine_id INT NOT NULL REFERENCES medicines,
 old_qty INT NOT NULL, new_qty INT NOT NULL, changed_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE daily_sales (
 sales_date DATE PRIMARY KEY, total_qty INT NOT NULL, total_amount NUMERIC(12,2) NOT NULL);

CREATE OR REPLACE FUNCTION fn_sale_value(p_medicine_id INT,p_quantity INT)
RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE v_price NUMERIC(10,2);
BEGIN
 IF p_quantity IS NULL OR p_quantity<=0 THEN RAISE EXCEPTION 'Quantity must be positive'; END IF;
 SELECT unit_price INTO v_price FROM medicines WHERE medicine_id=p_medicine_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown medicine ID %',p_medicine_id; END IF;
 RETURN v_price*p_quantity;
END $$;

CREATE OR REPLACE PROCEDURE pr_record_sale(p_medicine_id INT,p_quantity INT,p_sold_on DATE)
LANGUAGE plpgsql AS $$
DECLARE v_price NUMERIC(10,2); v_stock INT;
BEGIN
 IF p_quantity IS NULL OR p_quantity<=0 OR p_sold_on IS NULL THEN RAISE EXCEPTION 'Invalid sale input'; END IF;
 SELECT unit_price,stock_qty INTO v_price,v_stock FROM medicines
 WHERE medicine_id=p_medicine_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown medicine'; END IF;
 IF v_stock<p_quantity THEN RAISE EXCEPTION 'Insufficient stock'; END IF;
 INSERT INTO sales(medicine_id,quantity,unit_price,sold_on) VALUES(p_medicine_id,p_quantity,v_price,p_sold_on);
 UPDATE medicines SET stock_qty=stock_qty-p_quantity WHERE medicine_id=p_medicine_id;
END $$;

CREATE OR REPLACE FUNCTION trg_stock_audit_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
 IF OLD.stock_qty IS DISTINCT FROM NEW.stock_qty THEN
  INSERT INTO stock_audit(medicine_id,old_qty,new_qty)
  VALUES(NEW.medicine_id,OLD.stock_qty,NEW.stock_qty);
 END IF; RETURN NEW;
END $$;
CREATE TRIGGER trg_stock_audit AFTER UPDATE ON medicines
FOR EACH ROW EXECUTE FUNCTION trg_stock_audit_fn();

CREATE VIEW v_low_stock AS SELECT medicine_id,medicine_name,unit_price,stock_qty
FROM medicines WHERE stock_qty<10;

CREATE INDEX idx_sales_medicine_sold_on ON sales(medicine_id,sold_on);
-- EXPLAIN SELECT * FROM sales WHERE medicine_id=1 AND sold_on BETWEEN DATE '2026-11-01' AND DATE '2026-11-30';

CREATE OR REPLACE PROCEDURE pr_refresh_sales(p_day DATE)
LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO daily_sales(sales_date,total_qty,total_amount)
 SELECT p_day,COALESCE(SUM(quantity),0),COALESCE(SUM(quantity*unit_price),0)
 FROM sales WHERE sold_on=p_day
 ON CONFLICT(sales_date) DO UPDATE SET total_qty=EXCLUDED.total_qty,total_amount=EXCLUDED.total_amount;
END $$;
INSERT INTO medicines(medicine_name,unit_price,stock_qty) VALUES
('Paracetamol',5.00,100),('Amoxicillin',12.50,80),('Ibuprofen',8.00,60);
CALL pr_record_sale(1,2,CURRENT_DATE); CALL pr_record_sale(2,1,CURRENT_DATE);
CALL pr_record_sale(3,3,CURRENT_DATE); CALL pr_record_sale(1,4,CURRENT_DATE);
CALL pr_record_sale(2,2,CURRENT_DATE); CALL pr_record_sale(3,1,CURRENT_DATE);
SELECT * FROM v_low_stock;
CALL pr_refresh_sales(CURRENT_DATE);
SELECT * FROM daily_sales;