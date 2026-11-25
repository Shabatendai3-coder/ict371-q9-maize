-- ICT371 Advanced Database | Question 9: Farmer Cooperative Maize Deliveries
-- Student: Patience Shaba (202409214) | PostgreSQL 14+ with pg_cron
DROP SCHEMA IF EXISTS q9 CASCADE;
CREATE SCHEMA q9;
SET search_path TO q9, public;

-- (a) Tables and seed farmers ------------------------------------------------------------------
CREATE TABLE farmers (
  farmer_id     INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  farmer_number VARCHAR(20) NOT NULL UNIQUE,
  full_name     VARCHAR(100) NOT NULL
);
CREATE TABLE deliveries (
  delivery_id  INTEGER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  farmer_id    INTEGER NOT NULL REFERENCES farmers(farmer_id),
  grade        VARCHAR(1) NOT NULL CHECK (grade IN ('A', 'B', 'C')),
  weight_kg    NUMERIC(10,2) NOT NULL CHECK (weight_kg > 0),
  unit_rate    NUMERIC(10,2) NOT NULL,      -- always filled by the trigger
  total_value  NUMERIC(12,2) NOT NULL,      -- always filled by the trigger
  delivered_on DATE NOT NULL,
  is_paid      BOOLEAN NOT NULL DEFAULT FALSE
);
CREATE TABLE daily_purchases (
  purchase_date DATE PRIMARY KEY,
  total_weight  NUMERIC(14,2) NOT NULL,
  total_value   NUMERIC(14,2) NOT NULL
);
INSERT INTO farmers (farmer_number, full_name) VALUES
 ('F001', 'Joseph Banda'), ('F002', 'Lillian Tembo'), ('F003', 'Moses Mwale');

-- (b) Function ----------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION fn_maize_rate(p_grade TEXT)
RETURNS NUMERIC LANGUAGE plpgsql AS $$
BEGIN
  IF p_grade IS NULL THEN RAISE EXCEPTION 'Grade is required.'; END IF;
  IF p_grade = 'A' THEN RETURN 5.00;
  ELSIF p_grade = 'B' THEN RETURN 4.00;
  ELSIF p_grade = 'C' THEN RETURN 3.00;
  END IF;
  RAISE EXCEPTION 'Unsupported grade "%". Use A, B or C.', p_grade;
END; $$;

-- (d) Trigger: one pricing rule for every insert/update, including direct SQL ----------------------------
CREATE OR REPLACE FUNCTION fn_trg_delivery_price() RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.weight_kg IS NULL OR NEW.weight_kg <= 0 THEN
    RAISE EXCEPTION 'Weight must be greater than zero.';
  END IF;
  NEW.unit_rate   := fn_maize_rate(NEW.grade);
  NEW.total_value := ROUND(NEW.weight_kg * NEW.unit_rate, 2);
  RETURN NEW;                                  -- any client-supplied rate/value is overwritten
END; $$;
CREATE TRIGGER trg_deliveries_price BEFORE INSERT OR UPDATE ON deliveries
  FOR EACH ROW EXECUTE FUNCTION fn_trg_delivery_price();

-- (c) Procedure (supplies only the basic fields; the trigger prices the delivery) -------------------------
CREATE OR REPLACE PROCEDURE pr_receive_delivery(p_farmer_id INTEGER, p_grade TEXT, p_weight NUMERIC, p_date DATE)
LANGUAGE plpgsql AS $$
BEGIN
  PERFORM 1 FROM farmers WHERE farmer_id = p_farmer_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'Farmer % does not exist.', p_farmer_id; END IF;
  PERFORM fn_maize_rate(p_grade);              -- rejects NULL / unsupported grade
  IF p_weight IS NULL OR p_weight <= 0 THEN
    RAISE EXCEPTION 'Weight must be greater than zero.';
  END IF;
  IF p_date IS NULL THEN RAISE EXCEPTION 'Delivery date is required.'; END IF;
  INSERT INTO deliveries (farmer_id, grade, weight_kg, delivered_on, is_paid)
    VALUES (p_farmer_id, p_grade, p_weight, p_date, FALSE);
END; $$;

-- (a, continued) Six deliveries loaded after the trigger exists: all grades, both payment states
CALL pr_receive_delivery(1, 'A', 100, DATE '2026-11-20');
CALL pr_receive_delivery(1, 'B', 250.5, DATE '2026-11-21');
CALL pr_receive_delivery(2, 'C', 400, DATE '2026-11-20');
CALL pr_receive_delivery(2, 'A', 80, DATE '2026-11-24');
CALL pr_receive_delivery(3, 'B', 150, DATE '2026-11-24');
CALL pr_receive_delivery(3, 'C', 60.25, DATE '2026-11-24');
UPDATE deliveries SET is_paid = TRUE WHERE delivery_id IN (1, 3, 5);   -- some paid, some unpaid
-- Direct SQL follows the same rule: the wrong rate/value below is overwritten
INSERT INTO deliveries (farmer_id, grade, weight_kg, unit_rate, total_value, delivered_on, is_paid)
  VALUES (3, 'A', 10, 99, 1, DATE '2026-11-25', TRUE);
UPDATE deliveries SET is_paid = FALSE WHERE delivery_id = 7;           -- keep farmer 3 with an unpaid row too

-- Tests
SELECT fn_maize_rate('A') AS a, fn_maize_rate('B') AS b, fn_maize_rate('C') AS c;
DO $$ BEGIN PERFORM fn_maize_rate(NULL);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Rejected (NULL): %', SQLERRM; END $$;
DO $$ BEGIN PERFORM fn_maize_rate('D');
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Rejected (bad grade): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_receive_delivery(99, 'A', 10, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Rejected (unknown farmer): %', SQLERRM; END $$;
DO $$ BEGIN CALL pr_receive_delivery(1, 'A', -5, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Rejected (bad weight): %', SQLERRM; END $$;
DO $$ BEGIN INSERT INTO deliveries (farmer_id, grade, weight_kg, delivered_on) VALUES (1, 'A', 0, CURRENT_DATE);
EXCEPTION WHEN OTHERS THEN RAISE NOTICE 'Rejected (direct, zero weight): %', SQLERRM; END $$;
SELECT delivery_id, farmer_id, grade, weight_kg, unit_rate, total_value, is_paid
FROM deliveries ORDER BY delivery_id;                                    -- rate 5 and value 50.00 on row 7

-- (e) View -------------------------------------------------------------------------------------------------
CREATE VIEW v_farmer_amount_due AS
  SELECT f.farmer_number, f.full_name, COALESCE(SUM(d.total_value), 0) AS total_unpaid
  FROM farmers f
  LEFT JOIN deliveries d ON d.farmer_id = f.farmer_id AND d.is_paid = FALSE
  GROUP BY f.farmer_id, f.farmer_number, f.full_name;
SELECT * FROM v_farmer_amount_due ORDER BY farmer_number;
-- Zero-amount case: settle everything for farmer 3 and look again
UPDATE deliveries SET is_paid = TRUE WHERE farmer_id = 3;
SELECT * FROM v_farmer_amount_due WHERE farmer_number = 'F003';          -- shows 0
UPDATE deliveries SET is_paid = FALSE WHERE delivery_id = 6;             -- restore one unpaid row

-- (f) Index ---------------------------------------------------------------------------------------------------
-- Equality on farmer_id then a range on delivered_on: the composite index serves one farmer's
-- deliveries between two dates with a single range scan.
CREATE INDEX idx_deliveries_farmer_date ON deliveries (farmer_id, delivered_on);
ANALYZE deliveries;
SET enable_seqscan = off;   -- tiny table: forces the plan to show the index
EXPLAIN SELECT delivery_id, grade, weight_kg, total_value FROM deliveries
WHERE farmer_id = 1 AND delivered_on BETWEEN DATE '2026-11-20' AND DATE '2026-11-24';
RESET enable_seqscan;

-- (g) Scheduled job ------------------------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE pr_refresh_purchases(p_day DATE)
LANGUAGE plpgsql SET search_path = q9, public AS $$
BEGIN
  IF p_day IS NULL THEN RAISE EXCEPTION 'Day is required.'; END IF;
  INSERT INTO daily_purchases (purchase_date, total_weight, total_value)
    SELECT p_day, COALESCE(SUM(weight_kg), 0), COALESCE(SUM(total_value), 0)
    FROM deliveries WHERE delivered_on = p_day
  ON CONFLICT (purchase_date) DO UPDATE                 -- replace, never add again
    SET total_weight = EXCLUDED.total_weight, total_value = EXCLUDED.total_value;
END; $$;
CALL pr_refresh_purchases(DATE '2026-11-20');
CALL pr_refresh_purchases(DATE '2026-11-24');
CALL pr_refresh_purchases(DATE '2026-11-20');                            -- rerun: same totals
SELECT * FROM daily_purchases ORDER BY purchase_date;

CREATE EXTENSION IF NOT EXISTS pg_cron;
SELECT cron.schedule('q9_refresh_purchases', '30 1 * * *', $$CALL q9.pr_refresh_purchases(CURRENT_DATE - 1)$$);
SELECT jobid, jobname, schedule, command FROM cron.job WHERE jobname = 'q9_refresh_purchases';
