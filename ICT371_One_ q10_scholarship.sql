CREATE SCHEMA IF NOT EXISTS q10_scholarship;
SET search_path TO q10_scholarship, public;
CREATE TABLE students(student_id SERIAL PRIMARY KEY,student_number VARCHAR(30) UNIQUE,full_name VARCHAR(100) NOT NULL);
CREATE TABLE applications(application_id SERIAL PRIMARY KEY,student_id INT REFERENCES students,
 age_at_application INT NOT NULL CHECK(age_at_application>0),monthly_income NUMERIC(12,2) NOT NULL CHECK(monthly_income>=0),
 average_mark NUMERIC(5,2) NOT NULL CHECK(average_mark BETWEEN 0 AND 100),submitted_on DATE NOT NULL,
 status VARCHAR(10) NOT NULL CHECK(status IN('PENDING','APPROVED','REJECTED')));
CREATE TABLE decision_audit(audit_id SERIAL PRIMARY KEY,application_id INT REFERENCES applications,
 old_status VARCHAR(10),new_status VARCHAR(10),changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE OR REPLACE FUNCTION fn_scholarship_eligible(p_age INT,p_income NUMERIC,p_mark NUMERIC) RETURNS BOOLEAN
LANGUAGE plpgsql AS $$
BEGIN IF p_age IS NULL OR p_income IS NULL OR p_mark IS NULL OR p_age<=0 OR p_income<0 OR p_mark<0 OR p_mark>100 THEN
 RAISE EXCEPTION 'Invalid eligibility inputs'; END IF;
 RETURN p_age BETWEEN 18 AND 25 AND p_income<=3000 AND p_mark>=70; END $$;
CREATE OR REPLACE PROCEDURE pr_assess_application(p_application_id INT) LANGUAGE plpgsql AS $$
DECLARE a RECORD; v_status VARCHAR(10);
BEGIN SELECT * INTO a FROM applications WHERE application_id=p_application_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown application'; END IF;
 IF a.status<>'PENDING' THEN RAISE EXCEPTION 'Application already assessed'; END IF;
 IF fn_scholarship_eligible(a.age_at_application,a.monthly_income,a.average_mark) THEN v_status:='APPROVED'; ELSE v_status:='REJECTED'; END IF;
 UPDATE applications SET status=v_status WHERE application_id=p_application_id; END $$;
CREATE OR REPLACE FUNCTION trg_decision_audit_fn() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN IF OLD.status IS DISTINCT FROM NEW.status THEN
 INSERT INTO decision_audit(application_id,old_status,new_status) VALUES(NEW.application_id,OLD.status,NEW.status);
 END IF; RETURN NEW; END $$;
CREATE TRIGGER trg_decision_audit AFTER UPDATE ON applications FOR EACH ROW EXECUTE FUNCTION trg_decision_audit_fn();
CREATE VIEW v_approved_applicants AS SELECT s.student_number,s.full_name,a.average_mark,a.status
FROM applications a JOIN students s USING(student_id) WHERE a.status='APPROVED';
CREATE INDEX idx_applications_status_submitted ON applications(status,submitted_on);
-- EXPLAIN SELECT * FROM applications WHERE status='PENDING' AND submitted_on BETWEEN DATE '2026-11-01' AND DATE '2026-11-30';
CREATE OR REPLACE PROCEDURE pr_assess_pending() LANGUAGE plpgsql AS $$
DECLARE a RECORD;
BEGIN FOR a IN SELECT application_id FROM applications WHERE status='PENDING' LOOP
 CALL pr_assess_application(a.application_id); END LOOP; END $$;
INSERT INTO students(student_number,full_name) VALUES('S001','Applicant One'),('S002','Applicant Two'),('S003','Applicant Three');
INSERT INTO applications(student_id,age_at_application,monthly_income,average_mark,submitted_on,status) VALUES
(1,18,3000,70,CURRENT_DATE,'PENDING'),(1,26,2000,80,CURRENT_DATE,'PENDING'),
(2,20,3001,90,CURRENT_DATE,'PENDING'),(2,25,2500,69,CURRENT_DATE,'PENDING'),
(3,17,1500,95,CURRENT_DATE,'PENDING'),(3,22,1000,85,CURRENT_DATE,'PENDING');
CALL pr_assess_pending();
SELECT * FROM v_approved_applicants; SELECT * FROM decision_audit;