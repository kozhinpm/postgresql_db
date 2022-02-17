--------------
-- CREATE DB
--------------
CREATE DATABASE transactions_db;
CREATE EXTENSION tablefunc;
-----------------------
-- set initial parameters: 'customer_total_number', 'card_total_number', 'transactions_total_number'
-----------------------


CREATE TEMP TABLE vals (val_id TEXT PRIMARY KEY, val INT);
INSERT INTO vals(val_id, val) VALUES
  ('customer_total_number', 50)
, ('card_total_number', 300)
, ('transactions_total_number', 500);

---------------------
-- CREATE functions
---------------------

-- call initial parameter
CREATE OR REPLACE FUNCTION fun_val(_id text)
RETURNS setof int as
$BODY$
BEGIN
    RETURN QUERY SELECT val FROM vals WHERE val_id = $1;
    RETURN;
END;
$BODY$
LANGUAGE plpgsql;


----- card_exp_date_check
CREATE OR REPLACE FUNCTION card_exp_date_check(c_id int) 
returns DATE as $$
begin 
	return (select distinct c.card_exp_date
			from public.cards as c
			where c.card_id = c_id);
end;
$$ language 'plpgsql';


----- count transactions_sum by card
CREATE OR REPLACE FUNCTION transaction_sum_check(t_sum double precision, c_id int) 
returns double precision as $$
begin 
	return ((select COALESCE(SUM(transaction_sum),0)
			from transactions t
			where card_id =c_id)+t_sum);
end;
$$ language 'plpgsql';


-- function to generate names
CREATE OR REPLACE FUNCTION generate_names(num int) RETURNS SETOF text AS
$BODY$
begin 
	return QUERY select concat(firstname, ' ', lastname) customer_name from (SELECT
    arrays.firstnames[s.a % ARRAY_LENGTH(arrays.firstnames,1) + 1] AS firstname,
    ---substring('ABCDEFGHIJKLMNOPQRSTUVWXYZ' from s.a%26+1 for 1) AS middlename,
    arrays.lastnames[s.a % ARRAY_LENGTH(arrays.lastnames,1) + 1] AS lastname
FROM     generate_series(1, (SELECT num)) AS s(a) -- number of names to generate
CROSS JOIN(
    SELECT ARRAY[
    'Adam','Bill','Bob','Calvin','Donald','Dwight','Frank','Fred','George','Howard',
    'James','John','Jacob','Jack','Martin','Matthew','Max','Michael',
    'Paul','Peter','Phil','Roland','Ronald','Samuel','Steve','Theo','Warren','William',
    'Abigail','Alice','Allison','Amanda','Anne','Barbara','Betty','Carol','Cleo','Donna',
    'Jane','Jennifer','Julie','Martha','Mary','Melissa','Patty','Sarah','Simone','Susan'
    ] AS firstnames,
    ARRAY[
        'Matthews','Smith','Jones','Davis','Jacobson','Williams','Donaldson','Maxwell','Peterson','Stevens',
        'Franklin','Washington','Jefferson','Adams','Jackson','Johnson','Lincoln','Grant','Fillmore','Harding','Taft',
        'Truman','Nixon','Ford','Carter','Reagan','Bush','Clinton','Hancock'
    ] AS lastnames
) AS arrays) as names;	
    RETURN;
end;
$BODY$
LANGUAGE plpgsql;

-- function to generate random date
CREATE OR REPLACE FUNCTION generate_date() RETURNS SETOF DATE AS
$BODY$
DECLARE
    r float;
BEGIN
    FOR r IN
        select normal_rand(1, 100, 1000)
    loop
    	RETURN QUERY SELECT  current_date + cast(r as INT); 
    END LOOP;
    RETURN;
END;
$BODY$
LANGUAGE plpgsql;

--function to random row of customer.customer_id
CREATE OR REPLACE FUNCTION random_from_customer_id() 
   RETURNS setof int AS $$
BEGIN
    return QUERY select (array_agg(customer_id))[floor(random() * cardinality(array_agg(customer_id)) + 1)]
					   from public.customers;
return;
END;
$$ language 'plpgsql';


--function to get random from cards.card_id 
CREATE OR REPLACE FUNCTION random_from_card_id()
	RETURNS setof int AS $$
BEGIN
    return QUERY select (array_agg(card_id))[floor(random() * cardinality(array_agg(card_id)) + 1)]
					   from public.cards;
return;
END;
$$ language 'plpgsql';

--function to generate random card number
CREATE OR REPLACE FUNCTION random_card_num() 
   RETURNS  BIGINT as $$
BEGIN
   RETURN floor(random()* 8999999999999999 + 1000000000000000);
END;
$$ language 'plpgsql';

--function to generate random transaction sum
CREATE OR REPLACE FUNCTION random_sum() 
   RETURNS  float as $$
BEGIN
   RETURN  normal_rand(1, 100, 1000);
END;
$$ language 'plpgsql';

--function to fill transaction table and catch exceptions
CREATE OR REPLACE FUNCTION fill_transactions(c_id INT, t_sum FLOAT, t_date DATE)
RETURNS VOID AS $$
	begin
		if (transaction_sum_check(t_sum, c_id) < 0) then 
			RAISE INFO 'недостаточно средств';
	    	INSERT INTO errors (msg, detail) VALUES ('недостаточно средств', CONCAT(c_id,'; ', t_sum,'; ', t_date));
	    	RETURN;
		elsif (card_exp_date_check(c_id) <  t_date) then
			RAISE INFO 'карта недействительна';
			INSERT INTO errors (msg, detail) VALUES ('карта недействительна', CONCAT(c_id,', ', t_sum,'; ', t_date));
			RETURN;
		end IF;
		INSERT INTO public.transactions(card_id, transaction_sum, transaction_date)
		values (c_id, t_sum, t_date);
	end;
  $$ LANGUAGE plpgsql;
 
 
 
-------------------
-- CREATE tabels
-------------------

CREATE TABLE public.customers (
customer_id SERIAL PRIMARY KEY,
customer_name VARCHAR(100) NOT NULL);


CREATE TABLE public.cards (
card_id SERIAL PRIMARY KEY,
customer_id INTEGER NOT NULL REFERENCES public.customers(customer_id),
card_num BIGINT NOT NULL,
card_exp_date DATE NOT NULL,
CONSTRAINT card_num_positive_num CHECK (card_num > 0),
CONSTRAINT card_num_length CHECK (LENGTH(CAST(card_num AS TEXT)) = 16)
);


CREATE TABLE public.transactions (
transaction_id SERIAL PRIMARY KEY,
card_id INTEGER NOT NULL REFERENCES public.cards(card_id),
transaction_sum FLOAT NOT NULL,
transaction_date DATE NOT NULL,
CONSTRAINT transactions_sum_not_negative check (transaction_sum_check(transaction_sum, card_id) >=0),
CONSTRAINT transaction_by_valid_card check (card_exp_date_check(card_id) >=  transaction_date)
);
CREATE INDEX ON public.transactions(card_id);

CREATE TABLE public.errors (
error_id SERIAL,
error_date date default current_date,
msg text,
detail text);
 
 
------------------------
-- fill tabels with DATA
------------------------

--customers
INSERT INTO public.customers(customer_name)
select generate_names(fun_val('customer_total_number'));

--cards
INSERT INTO public.cards(customer_id, card_num, card_exp_date)
select random_from_customer_id() as customer_id , 
random_card_num() as card_num,
generate_date() as card_exp_date
from generate_series(1, (select fun_val('card_total_number')));

--transactions
select fill_transactions(random_from_card_id(), random_sum(), current_date) -- generate_date()
from generate_series(1, (select fun_val('transactions_total_number')));

--PROFIT transactions
select * from public.transactions;
--transactions with ERROR
select * from errors ;




            