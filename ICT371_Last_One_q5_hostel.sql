CREATE SCHEMA IF NOT EXISTS q5_hostel;
SET search_path TO q5_hostel, public;
CREATE TABLE students(student_id SERIAL PRIMARY KEY,student_number VARCHAR(30) UNIQUE,full_name VARCHAR(100) NOT NULL);
CREATE TABLE rooms(room_id SERIAL PRIMARY KEY,room_number VARCHAR(20) UNIQUE,capacity INT NOT NULL CHECK(capacity>0));
CREATE TABLE allocations(allocation_id SERIAL PRIMARY KEY,student_id INT REFERENCES students,room_id INT REFERENCES rooms,
 allocated_on DATE NOT NULL,released_on DATE,status VARCHAR(10) NOT NULL CHECK(status IN('ACTIVE','ENDED')),
 CHECK((status='ACTIVE' AND released_on IS NULL) OR (status='ENDED' AND released_on IS NOT NULL)));
CREATE TABLE occupancy_snapshot(snapshot_date DATE,room_id INT REFERENCES rooms,occupied_beds INT,free_beds INT,PRIMARY KEY(snapshot_date,room_id));
CREATE OR REPLACE FUNCTION fn_free_beds(p_room_id INT) RETURNS INT LANGUAGE plpgsql AS $$
DECLARE v_cap INT; v_occ INT;
BEGIN SELECT capacity INTO v_cap FROM rooms WHERE room_id=p_room_id; IF NOT FOUND THEN RAISE EXCEPTION 'Unknown room'; END IF;
 SELECT COUNT(*) INTO v_occ FROM allocations WHERE room_id=p_room_id AND status='ACTIVE'; RETURN v_cap-v_occ; END $$;
CREATE OR REPLACE PROCEDURE pr_allocate_room(p_student_id INT,p_room_id INT,p_allocated_on DATE)
LANGUAGE plpgsql AS $$
BEGIN
 IF NOT EXISTS(SELECT 1 FROM students WHERE student_id=p_student_id) THEN RAISE EXCEPTION 'Unknown student'; END IF;
 IF NOT EXISTS(SELECT 1 FROM rooms WHERE room_id=p_room_id) THEN RAISE EXCEPTION 'Unknown room'; END IF;
 IF EXISTS(SELECT 1 FROM allocations WHERE student_id=p_student_id AND status='ACTIVE') THEN RAISE EXCEPTION 'Student already allocated'; END IF;
 IF fn_free_beds(p_room_id)<=0 THEN RAISE EXCEPTION 'Room full'; END IF;
 INSERT INTO allocations(student_id,room_id,allocated_on,status) VALUES(p_student_id,p_room_id,p_allocated_on,'ACTIVE');
END $$;
CREATE OR REPLACE FUNCTION trg_allocation_validate_fn() RETURNS TRIGGER LANGUAGE plpgsql AS $$
DECLARE v_capacity INT; v_active INT;
BEGIN IF NEW.status='ACTIVE' THEN
 SELECT capacity INTO v_capacity FROM rooms WHERE room_id=NEW.room_id;
 SELECT COUNT(*) INTO v_active FROM allocations WHERE room_id=NEW.room_id AND status='ACTIVE'
 AND (TG_OP='INSERT' OR allocation_id<>NEW.allocation_id);
 IF v_active>=v_capacity THEN RAISE EXCEPTION 'Room capacity exceeded'; END IF;
 IF EXISTS(SELECT 1 FROM allocations WHERE student_id=NEW.student_id AND status='ACTIVE'
 AND (TG_OP='INSERT' OR allocation_id<>NEW.allocation_id) ) THEN RAISE EXCEPTION 'Student already has active allocation'; END IF;
 END IF; RETURN NEW; END $$;
CREATE TRIGGER trg_allocation_validate BEFORE INSERT OR UPDATE ON allocations FOR EACH ROW EXECUTE FUNCTION trg_allocation_validate_fn();
CREATE VIEW v_room_occupancy AS SELECT r.room_id,r.room_number,r.capacity,COUNT(a.allocation_id) FILTER(WHERE a.status='ACTIVE') AS occupied_beds,
 r.capacity-COUNT(a.allocation_id) FILTER(WHERE a.status='ACTIVE') AS free_beds
FROM rooms r LEFT JOIN allocations a USING(room_id) GROUP BY r.room_id,r.room_number,r.capacity;
CREATE INDEX idx_allocations_active_room ON allocations(room_id) WHERE status='ACTIVE';
-- EXPLAIN SELECT * FROM allocations WHERE room_id=1 AND status='ACTIVE';
CREATE OR REPLACE PROCEDURE pr_refresh_occupancy() LANGUAGE plpgsql AS $$
BEGIN INSERT INTO occupancy_snapshot(snapshot_date,room_id,occupied_beds,free_beds)
 SELECT CURRENT_DATE,room_id,occupied_beds,free_beds FROM v_room_occupancy
 ON CONFLICT(snapshot_date,room_id) DO UPDATE SET occupied_beds=EXCLUDED.occupied_beds,free_beds=EXCLUDED.free_beds;
END $$;
INSERT INTO students(student_number,full_name) VALUES('H001','Hostel Student 1'),('H002','Hostel Student 2'),('H003','Hostel Student 3'),('H004','Hostel Student 4');
INSERT INTO rooms(room_number,capacity) VALUES('A1',2),('A2',1),('A3',3);
CALL pr_allocate_room(1,1,CURRENT_DATE); CALL pr_allocate_room(2,1,CURRENT_DATE); CALL pr_allocate_room(3,2,CURRENT_DATE);
CALL pr_allocate_room(4,3,CURRENT_DATE);
SELECT * FROM v_room_occupancy; CALL pr_refresh_occupancy(); SELECT * FROM occupancy_snapshot;