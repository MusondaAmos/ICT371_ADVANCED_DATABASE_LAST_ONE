CREATE SCHEMA IF NOT EXISTS q3_library;
SET search_path TO q3_library, public;
CREATE TABLE books(book_id SERIAL PRIMARY KEY,title VARCHAR(200) NOT NULL);
CREATE TABLE loans(loan_id SERIAL PRIMARY KEY,book_id INT NOT NULL REFERENCES books,
 borrower_name VARCHAR(100) NOT NULL,borrowed_on DATE NOT NULL,due_on DATE NOT NULL,
 returned_on DATE,fine_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
 CHECK(due_on>=borrowed_on));
CREATE TABLE loan_audit(audit_id SERIAL PRIMARY KEY,loan_id INT REFERENCES loans,
 old_returned_on DATE,new_returned_on DATE,changed_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE overdue_summary(snapshot_date DATE PRIMARY KEY,overdue_count INT,total_fine NUMERIC(12,2));

CREATE OR REPLACE FUNCTION fn_loan_fine(p_loan_id INT,p_as_of DATE) RETURNS NUMERIC
LANGUAGE plpgsql AS $$
DECLARE v_due DATE; v_return DATE; v_end DATE; v_fine NUMERIC;
BEGIN
 SELECT due_on,returned_on INTO v_due,v_return FROM loans WHERE loan_id=p_loan_id;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown loan'; END IF;
 v_end:=LEAST(p_as_of,COALESCE(v_return,p_as_of));
 v_fine:=GREATEST(v_end-v_due,0)*2;
 RETURN v_fine;
END $$;
CREATE OR REPLACE PROCEDURE pr_return_loan(p_loan_id INT,p_returned_on DATE)
LANGUAGE plpgsql AS $$
DECLARE v_borrowed DATE; v_return DATE;
BEGIN
 SELECT borrowed_on,returned_on INTO v_borrowed,v_return FROM loans WHERE loan_id=p_loan_id FOR UPDATE;
 IF NOT FOUND THEN RAISE EXCEPTION 'Unknown loan'; END IF;
 IF v_return IS NOT NULL THEN RAISE EXCEPTION 'Loan already returned'; END IF;
 IF p_returned_on<v_borrowed THEN RAISE EXCEPTION 'Return cannot precede borrowing'; END IF;
 UPDATE loans SET returned_on=p_returned_on,fine_amount=fn_loan_fine(p_loan_id,p_returned_on) WHERE loan_id=p_loan_id;
END $$;
CREATE OR REPLACE FUNCTION trg_loan_audit_fn() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN IF OLD.returned_on IS DISTINCT FROM NEW.returned_on THEN
 INSERT INTO loan_audit(loan_id,old_returned_on,new_returned_on) VALUES(NEW.loan_id,OLD.returned_on,NEW.returned_on);
 END IF; RETURN NEW; END $$;
CREATE TRIGGER trg_loan_audit AFTER UPDATE ON loans FOR EACH ROW EXECUTE FUNCTION trg_loan_audit_fn();
CREATE VIEW v_overdue_loans AS SELECT b.title,l.borrower_name,l.due_on,fn_loan_fine(l.loan_id,CURRENT_DATE) AS fine
FROM loans l JOIN books b USING(book_id) WHERE l.returned_on IS NULL AND l.due_on<CURRENT_DATE;
CREATE INDEX idx_loans_book_open ON loans(book_id) WHERE returned_on IS NULL;
-- EXPLAIN SELECT * FROM loans WHERE book_id=1 AND returned_on IS NULL;
CREATE OR REPLACE PROCEDURE pr_refresh_overdue(p_as_of DATE) LANGUAGE plpgsql AS $$
BEGIN
 INSERT INTO overdue_summary(snapshot_date,overdue_count,total_fine)
 SELECT p_as_of,COUNT(*),COALESCE(SUM(fn_loan_fine(loan_id,p_as_of)),0)
 FROM loans WHERE returned_on IS NULL AND due_on<p_as_of
 ON CONFLICT(snapshot_date) DO UPDATE SET overdue_count=EXCLUDED.overdue_count,total_fine=EXCLUDED.total_fine;
END $$;
INSERT INTO books(title) VALUES('Database Systems'),('Operating Systems'),('Networking');
INSERT INTO loans(book_id,borrower_name,borrowed_on,due_on,returned_on,fine_amount) VALUES
(1,'Borrower A',CURRENT_DATE-20,CURRENT_DATE-10,NULL,0),
(2,'Borrower B',CURRENT_DATE-10,CURRENT_DATE-3,CURRENT_DATE-3,0),
(3,'Borrower C',CURRENT_DATE-8,CURRENT_DATE-2,CURRENT_DATE-1,0),
(1,'Borrower D',CURRENT_DATE-5,CURRENT_DATE+5,NULL,0),
(2,'Borrower E',CURRENT_DATE-15,CURRENT_DATE-5,NULL,0),
(3,'Borrower F',CURRENT_DATE-7,CURRENT_DATE+3,NULL,0);
SELECT * FROM v_overdue_loans; CALL pr_refresh_overdue(CURRENT_DATE); SELECT * FROM overdue_summary;