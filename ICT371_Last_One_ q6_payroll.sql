CREATE SCHEMA IF NOT EXISTS q6_payroll;
SET search_path TO q6_payroll, public;
CREATE TABLE employees(employee_id SERIAL PRIMARY KEY,full_name VARCHAR(100),basic_salary NUMERIC(12,2) CHECK(basic_salary>=0),
 allowance NUMERIC(12,2) CHECK(allowance>=0),deduction NUMERIC(12,2) CHECK(deduction>=0),active BOOLEAN NOT NULL);
CREATE TABLE payroll(payroll_id SERIAL PRIMARY KEY,employee_id INT REFERENCES employees,pay_month DATE NOT NULL,
 gross_pay NUMERIC(12,2),net_pay NUMERIC(12,2),UNIQUE(employee_id,pay_month),CHECK(pay_month=DATE_TRUNC('month',pay_month)::DATE));
CREATE TABLE salary_audit(audit_id SERIAL PRIMARY KEY,employee_id INT REFERENCES employees,old_salary NUMERIC(12,2),new_salary NUMERIC(12,2),changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE OR REPLACE FUNCTION fn_net_pay(p_employee_id INT) RETURNS NUMERIC LANGUAGE plpgsql AS $$
DECLARE v_gross NUMERIC; v_net NUMERIC;
BEGIN SELECT basic_salary+allowance-deduction INTO v_net FROM employees WHERE employee_id=p_employee_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown employee'; END IF;
 IF v_net<0 THEN RAISE EXCEPTION 'Computed net pay is negative'; END IF; RETURN v_net; END $$;
CREATE OR REPLACE PROCEDURE pr_process_payroll(p_month DATE) LANGUAGE plpgsql AS $$
DECLARE e RECORD; v_net NUMERIC;
BEGIN IF p_month IS NULL OR p_month<>DATE_TRUNC('month',p_month)::DATE THEN RAISE EXCEPTION 'Use first day of month'; END IF;
 FOR e IN SELECT employee_id,basic_salary,allowance FROM employees WHERE active LOOP
 v_net:=fn_net_pay(e.employee_id);
 INSERT INTO payroll(employee_id,pay_month,gross_pay,net_pay) VALUES(e.employee_id,p_month,e.basic_salary+e.allowance,v_net)
 ON CONFLICT(employee_id,pay_month) DO NOTHING;
 END LOOP; END $$;
CREATE OR REPLACE FUNCTION trg_salary_audit_fn() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN IF OLD.basic_salary IS DISTINCT FROM NEW.basic_salary THEN
 INSERT INTO salary_audit(employee_id,old_salary,new_salary) VALUES(NEW.employee_id,OLD.basic_salary,NEW.basic_salary);
 END IF; RETURN NEW; END $$;
CREATE TRIGGER trg_salary_audit AFTER UPDATE ON employees FOR EACH ROW EXECUTE FUNCTION trg_salary_audit_fn();
CREATE VIEW v_payroll_report AS SELECT e.full_name,p.pay_month,p.gross_pay,p.net_pay FROM payroll p JOIN employees e USING(employee_id);
CREATE INDEX idx_payroll_month ON payroll(pay_month);
-- EXPLAIN SELECT * FROM payroll WHERE pay_month=DATE '2026-10-01';
INSERT INTO employees(full_name,basic_salary,allowance,deduction,active) VALUES
('Employee One',5000,500,300,true),('Employee Two',4200,300,250,true),('Employee Three',6000,1000,500,false);
CALL pr_process_payroll(DATE '2026-10-01'); CALL pr_process_payroll(DATE '2026-11-01');
SELECT * FROM v_payroll_report;