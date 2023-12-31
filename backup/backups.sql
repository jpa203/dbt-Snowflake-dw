PGDMP                         {           Netflix    14.2    14.2 x    �           0    0    ENCODING    ENCODING        SET client_encoding = 'UTF8';
                      false            �           0    0 
   STDSTRINGS 
   STDSTRINGS     (   SET standard_conforming_strings = 'on';
                      false            �           0    0 
   SEARCHPATH 
   SEARCHPATH     8   SELECT pg_catalog.set_config('search_path', '', false);
                      false            �           1262    33735    Netflix    DATABASE     T   CREATE DATABASE "Netflix" WITH TEMPLATE = template0 ENCODING = 'UTF8' LOCALE = 'C';
    DROP DATABASE "Netflix";
                postgres    false                        3079    41303 	   tablefunc 	   EXTENSION     =   CREATE EXTENSION IF NOT EXISTS tablefunc WITH SCHEMA public;
    DROP EXTENSION tablefunc;
                   false            �           0    0    EXTENSION tablefunc    COMMENT     `   COMMENT ON EXTENSION tablefunc IS 'functions that manipulate whole tables, including crosstab';
                        false    2                       1255    42097    audit()    FUNCTION     W  CREATE FUNCTION public.audit() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN                       
        -- insert
		IF (TG_OP = 'INSERT') THEN
		INSERT INTO payment_history (memberid, paymentid, amountpaid, amountpaiddate, amountpaiduntildate, changetype, time_stamp)
        SELECT NEW.memberid, NEW.paymentid, NEW.amountpaid, NEW.amountpaiddate, NEW.amountpaiduntildate, 'I', now();
        RETURN NEW;  --- we are inserting the new record into the payment_history table while also adding two columns 'changetype' and 'time_stamp' with 'I' to indicate insert and now() for the current date
		
		-- update
		ELSIF (TG_OP = 'UPDATE') THEN 
		INSERT INTO payment_history(memberid, paymentid, amountpaid, amountpaid_new, amountpaiddate, amountpaiddate_new, amountpaiduntildate, amountpaiduntildate_new, changetype, time_stamp)
		VALUES (NEW.memberid, NEW.paymentid, OLD.amountpaid,NEW.amountpaid,OLD.amountpaiddate, current_date, OLD.amountpaiduntildate, current_date, 'U', current_date); -- update the paymment history table with data of old record and new records
		RETURN NEW;
		
		-- delete
		ELSIF (TG_OP = 'DELETE') THEN
		INSERT INTO payment_history(memberid, paymentid, amountpaid, amountpaid_new, amountpaiddate, amountpaiddate_new, amountpaiduntildate, amountpaiduntildate_new, changetype, time_stamp)
		VALUES (OLD.memberid, OLD.paymentid, OLD.amountpaid, OLD.amountpaid, OLD.amountpaiddate, current_date, OLD.amountpaiduntildate, current_date, 'D', current_date);
		RETURN NULL; -- sme as above but with delete and recording old row
		
		END IF; 


		
                                        
END;
$$;
    DROP FUNCTION public.audit();
       public          postgres    false                       1255    42375    delete_record(integer, integer) 	   PROCEDURE       CREATE PROCEDURE public.delete_record(IN p_memberid integer, IN p_dvdid integer)
    LANGUAGE plpgsql
    AS $$

declare

v_counter INT;
v_memberid INT;
v_dvdid INT;
v_dvdqueueposition INT;

begin	

	select COUNT(*) from rentalqueue
 	into v_counter -- add a counter for all records that match the given 'where' clause ie where memberid/dvdid exists 
 	where memberid = p_memberid and dvdid = p_dvdid;
	
	if v_counter > 0 then
		
		select memberid, dvdid, dvdqueueposition from rentalqueue
		into v_memberid, v_dvdid, v_dvdqueueposition
		where memberid = p_memberid and dvdid = p_dvdid;
		
		if v_dvdqueueposition = (select(max(dvdqueueposition))from rentalqueue where memberid = p_memberid) then  -- needs to be the last one 
		
			delete from rentalqueue 
			where memberid = v_memberid and dvdid = v_dvdid;
			
		elsif v_dvdqueueposition <> (select(max(dvdqueueposition))from rentalqueue where memberid = p_memberid) then
		
			delete from rentalqueue
			where memberid = v_memberid and dvdid = v_dvdid;
			
			update rentalqueue
			set dvdqueueposition = dvdqueueposition - 1 -- change all positions below by -1
			where memberid = p_memberid and dvdqueueposition > v_dvdqueueposition;
			
		end if;
		
 	else 
		raise notice 'DVD does not exist in queue';
	
	end if; 
		
end;
$$;
 P   DROP PROCEDURE public.delete_record(IN p_memberid integer, IN p_dvdid integer);
       public          postgres    false                       1255    42383 %   dvd_return(integer, integer, integer) 	   PROCEDURE     E  CREATE PROCEDURE public.dvd_return(IN p_memberid integer, IN p_dvdid integer, IN p_returned_lost integer)
    LANGUAGE plpgsql
    AS $_$
declare

	v_movierental int;
	v_dvdid int;
	v_rentalrequestdate timestamp;
	
begin

-- if dvd is returned

	if p_returned_lost = 1 then -- not lost, update stock
		update dvd
		set dvdquantityonhand = dvdquantityonhand + 1,  
		dvdquantityonrent = dvdquantityonrent - 1
		where dvdid = p_dvdid;

		update rental -- update rental table to reflect dvd back
		set rentalreturneddate = current_date
		where memberid = p_memberid and dvdid = p_dvdid;

-- if dvd is lost

	elsif p_returned_lost = 0 then -- lost, update stock
		update dvd  
		set dvdlostquantity = dvdlostquantity + 1,
		dvdquantityonrent = dvdquantityonrent - 1
		where dvdid = p_dvdid;
		
		update rental -- update rental table to reflect dvd back
		set rentalreturneddate = '1990-01-01 00:00:00' -- to reflect dvd that have been lost
		where memberid = p_memberid and dvdid = p_dvdid;

		insert into payment(memberid, amountpaid, amountpaiddate, amountpaiduntildate) -- insert payment for lost dvd
		values(p_memberid, 25.00, current_date, current_date); -- we can hard code $25 because all membership dvd lost prices are $ 25

	end if; 
	
-- initiate function to notify how many dvd can be rented and removes from queue

	select dvdlimit(p_memberid) into v_movierental; 

	if v_movierental = 0 then -- if they can't rent
		raise notice 'Limit reached';
	
	else -- if they can rent
		select dvdinstock(p_memberid) into v_dvdid; -- returns dvdid
		
		select dateaddedinqueue from rentalqueue into v_rentalrequestdate
		where memberid = p_memberid and dvdid = v_dvdid; -- find rentalrequest date for aforementioned dvd
				
		insert into rental(memberid, dvdid, rentalrequestdate, rentalshippeddate)
		values(p_memberid, v_dvdid, v_rentalrequestdate, current_date); -- insert rental into table
		
		update dvd 
		set dvdquantityonhand = dvdquantityonhand - 1,
		dvdquantityonrent = dvdquantityonrent + 1
		where dvdid = v_dvdid; -- update dvd table 
		
		call delete_record(p_memberid, v_dvdid);
	
	end if;

end;$_$;
 i   DROP PROCEDURE public.dvd_return(IN p_memberid integer, IN p_dvdid integer, IN p_returned_lost integer);
       public          postgres    false                       1255    42239    dvdinstock(integer)    FUNCTION     D  CREATE FUNCTION public.dvdinstock(p_memberid integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare 

	v_dvdid int;
	v_memberid int;

begin

	select dvd.dvdid into v_dvdid from rentalqueue
	join dvd on dvd.dvdid = rentalqueue.dvdid
	where memberid = p_memberid
	and dvdqueueposition = (select min(dvdqueueposition) from rentalqueue
							join dvd on dvd.dvdid = rentalqueue.dvdid
							where memberid = p_memberid
							and dvd.dvdquantityonhand >= 1);
	
	return v_dvdid;
-- 	if not found then
-- 		raise 'Null';

-- 	else
-- 		return v_dvdid;
	
-- 	end if;

end;
$$;
 5   DROP FUNCTION public.dvdinstock(p_memberid integer);
       public          postgres    false                       1255    42380    dvdlimit(integer)    FUNCTION       CREATE FUNCTION public.dvdlimit(p_memberid integer) RETURNS integer
    LANGUAGE plpgsql
    AS $$
declare 

	v_dvdattime int; -- how many they can rent at a time
	v_monthlimit int; -- member's monthly limit
	v_rentcount int; -- all dvds currrently rented (return date NULL)
	v_renttotal int; -- all rented dvds this month (including those that are out)

begin

	select dvdattime, membershiplimitpermonth into v_dvdattime, v_monthlimit from member
	join membership on membership.membershipid = member.membershipid
	where memberid = p_memberid;

	select count(*) into v_rentcount from rental -- CURRENTLY RENTED
	where rentalreturneddate IS NULL 
	and memberid = p_memberid;
	
	select count(*) into v_renttotal from rental -- DVD MONTH TOTAL
	where memberid = p_memberid;
	
	if v_renttotal >= v_monthlimit then -- if they've reached their limit
		return 0;
		
	elsif v_rentcount = v_dvdattime then -- if they reach their max at one time
		return 0;
	
	elsif v_rentcount < v_dvdattime and v_monthlimit > v_renttotal and (v_monthlimit - v_renttotal) <= v_dvdattime then
		return (v_monthlimit - v_renttotal);
	
	elsif v_rentcount < v_dvdattime and v_monthlimit > v_renttotal and  (v_monthlimit - v_renttotal) > v_dvdattime then
		return (v_dvdattime - v_rentcount);
		
	else
		return 0;
	end if;
	
end;
$$;
 3   DROP FUNCTION public.dvdlimit(p_memberid integer);
       public          postgres    false                       1255    42198 @   lost_dvd(numeric, numeric, numeric, timestamp without time zone)    FUNCTION     �  CREATE FUNCTION public.lost_dvd(p_rentalid numeric, p_memberid numeric, p_amount numeric, p_trans_date timestamp without time zone) RETURNS void
    LANGUAGE plpgsql
    AS $_$ --opens the $$ quotation for the block
-- The V prefix denotes variables.
declare V_DVDId NUMERIC =0;
declare V_PaymentId NUMERIC = 0;
declare V_UntilDate TIMESTAMP(3)  = NULL;
BEGIN

-- Get DVDId 
	SELECT DVDId INTO V_DVDID FROM RENTAL WHERE RentalId = P_RentalId;
	
-- Get PaymentId
	SELECT COUNT(*)+1 INTO V_PaymentId FROM Payment; --maybe we can do something here with the count
	
-- Get AmountPaidUntilDate
	SELECT AmountPaidUntilDate INTO V_UntilDate FROM Payment 
		WHERE MemberId = P_MemberId
AND PaymentId = 
(SELECT MAX(PaymentId) FROM Payment WHERE MemberId=P_MemberId); -- max operations can be costly 

-- Now, make the changes to the database…
INSERT INTO Payment(PaymentId, MemberId, AmountPaid,
     	AmountPaidDate,AmountPaidUntilDate)
	VALUES(V_PaymentId,P_MemberId,P_Amount,P_Trans_Date,V_UntilDate); -- insert variables into the payment table

UPDATE Rental SET RentalReturnedDate = P_Trans_Date -- since it's not returned, we can just update to date of payment
WHERE RentalId = P_RentalId; -- maybe some indexing comes here 

UPDATE DVD SET DVDQuantityOnRent = DVDQuantityOnRent - 1
WHERE DVDId = V_DVDId; -- again some indexing comes here 

UPDATE DVD SET DVDLostQuantity = DVDLostQuantity + 1
WHERE DVDId = V_DVDId; -- again some indexing comes here 


END;
$_$;
 �   DROP FUNCTION public.lost_dvd(p_rentalid numeric, p_memberid numeric, p_amount numeric, p_trans_date timestamp without time zone);
       public          postgres    false                       1255    42169 +   queue_management(integer, integer, integer) 	   PROCEDURE     B  CREATE PROCEDURE public.queue_management(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer)
    LANGUAGE plpgsql
    AS $$

declare

v_counter INT;
v_dvdid INT;
v_dvdqueueposition INT; 
v_memberid INT;
begin	
		
 		select COUNT(*) from rentalqueue
 		into v_counter -- add a counter for all records that match the given 'where' clause ie where memberid/dvdid exists 
 		where memberid = p_memberid and dvdid = p_dvdid;
	

 		if v_counter > 0  then  -- if records exists then...
		
			select dvdid, dvdqueueposition, memberid from rentalqueue
			into v_dvdid, v_dvdqueueposition, v_memberid  -- ... get the dvdid and its queue position
			where memberid = p_memberid  and dvdid = p_dvdid;
																	
			if v_dvdqueueposition <> 1 and v_dvdqueueposition < (select max(dvdqueueposition) from rentalqueue where memberid = v_memberid) then -- and NOT LAST -- then...
				update rentalqueue
  				set dvdqueueposition = dvdqueueposition + 1 -- change all other positions to +1 
  				where dvdqueueposition >= p_dvdqueueposition
				and memberid = p_memberid;
				
				update rentalqueue
 				set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
				where memberid = p_memberid and dvdid = p_dvdid; -- update dvd with new position
				
 				update rentalqueue
 				set dvdqueueposition = dvdqueueposition - 1
				where dvdqueueposition > v_dvdqueueposition 
 				and memberid = p_memberid;
			
				
 			elsif v_dvdqueueposition = (select max(dvdqueueposition) from rentalqueue where memberid = v_memberid) then -- AND IS LAST -- then...
 				update rentalqueue
 				set dvdqueueposition = dvdqueueposition + 1 -- change all other positions to +1 
 				where dvdqueueposition >= p_dvdqueueposition 
 				and memberid = p_memberid;
				
				update rentalqueue
 				set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
 				where memberid = p_memberid and dvdid = p_dvdid; -- update dvd with new position									
			
 			elsif v_dvdqueueposition = 1 then -- NOW IF THE DVDQUEUE POSITION IS ONE
			
 				update rentalqueue
  				set dvdqueueposition = dvdqueueposition + 1 -- change all positions above by +1 
   				where dvdqueueposition >= p_dvdqueueposition
 				and memberid = p_memberid;
				
 				update rentalqueue
 				set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
 				where memberid = p_memberid and dvdid = p_dvdid;
				
 				update rentalqueue 
 				set dvdqueueposition = dvdqueueposition - 1 -- change all positions below by -1
 				where memberid = p_memberid; 
				
			elsif v_dvdqueueposition > (select max(dvdqueueposition) from rentalqueue where memberid = v_memberid) then
			
				update rentalqueue
				set dvdqueuposition = (select max(dvdqueueposition) from rentalqueue where memberid = v_memberid) + 1
				where memberid = p_memberid;
				
 			end if;
			
   		elsif v_counter = 0 then -- if record doesn't exist in table..
		
				select memberid, dvdqueueposition from rentalqueue
				into v_memberid, v_dvdqueueposition
				where memberid = p_memberid and dvdqueueposition = (select max(dvdqueueposition) from rentalqueue where memberid = p_memberid);
		
				if p_dvdqueueposition > v_dvdqueueposition then
				
					
				
					insert into rentalqueue(memberid, dvdid, dateaddedinqueue, dvdqueueposition) -- insert the new record into the table
					values(p_memberid, p_dvdid, current_date, v_dvdqueueposition + 1);
				

				else 

   					update rentalqueue
    				set dvdqueueposition = dvdqueueposition + 1
    				where dvdqueueposition >= p_dvdqueueposition
 					and memberid = p_memberid; -- update all other records greater than position
			
 					insert into rentalqueue(memberid, dvdid, dateaddedinqueue, dvdqueueposition) -- insert the new record into the table
					values(p_memberid, p_dvdid, current_date, p_dvdqueueposition);
					
				end if; 

 		end if;
end; 
$$;
 r   DROP PROCEDURE public.queue_management(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer);
       public          postgres    false                       1255    42161 ,   queue_management2(integer, integer, integer) 	   PROCEDURE     �  CREATE PROCEDURE public.queue_management2(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer)
    LANGUAGE plpgsql
    AS $$

declare

v_counter INT;
v_dvdid INT;
v_dvdqueueposition INT; 
v_memberid INT;
begin	
		
 		select COUNT(*) from test_table
 		into v_counter -- add a counter for all records that match the given 'where' clause ie where memberid/dvdid exists 
 		where memberid = p_memberid and dvdid = p_dvdid;
	

 		if v_counter > 0  then  -- if records exists then...
		
			select dvdid, dvdqueueposition, memberid from test_table
			into v_dvdid, v_dvdqueueposition, v_memberid  -- ... get the dvdid and its queue position
			where memberid = p_memberid  and dvdid = p_dvdid;
																	
			if v_dvdqueueposition <> 1 and v_dvdqueueposition < (select max(dvdqueueposition) from test_table where memberid = v_memberid) then -- and NOT LAST -- then...
				update test_table
  				set dvdqueueposition = dvdqueueposition + 1 -- change all other positions to +1 
  				where dvdqueueposition >= p_dvdqueueposition
				and memberid = p_memberid;
				
				update test_table
 				set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
				where memberid = p_memberid and dvdid = p_dvdid; -- update dvd with new position
				
 				update test_table
 				set dvdqueueposition = dvdqueueposition - 1
				where dvdqueueposition > v_dvdqueueposition 
 				and memberid = p_memberid;
			
				
 			elsif v_dvdqueueposition = (select max(dvdqueueposition) from test_table where memberid = v_memberid) then -- AND IS LAST -- then...
 				update test_table
 				set dvdqueueposition = dvdqueueposition + 1 -- change all other positions to +1 
 				where dvdqueueposition >= p_dvdqueueposition 
 				and memberid = p_memberid;
				
				update test_table
 				set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
 				where memberid = p_memberid and dvdid = p_dvdid; -- update dvd with new position									
			
 			elsif v_dvdqueueposition = 1 then -- NOW IF THE DVDQUEUE POSITION IS ONE
			
 				update test_table
  				set dvdqueueposition = dvdqueueposition + 1 -- change all positions above by +1 
   				where dvdqueueposition >= p_dvdqueueposition
 				and memberid = p_memberid;
				
 				update test_table
 				set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
 				where memberid = p_memberid and dvdid = p_dvdid;
				
 				update test_table 
 				set dvdqueueposition = dvdqueueposition - 1 -- change all positions below by -1
 				where memberid = p_memberid; 
				
			elsif v_dvdqueueposition > (select max(dvdqueueposition) from test_table where memberid = v_memberid) then
			
				update test_table
				set dvdqueuposition = (select max(dvdqueueposition) from test_table where memberid = v_memberid) + 1
				where memberid = p_memberid;
				
 			end if;
			
   		elsif v_counter = 0 then -- if record doesn't exist in table..
		
				select memberid, dvdqueueposition from test_table
				into v_memberid, v_dvdqueueposition
				where memberid = p_memberid and dvdqueueposition = (select max(dvdqueueposition) from test_table where memberid = p_memberid);
		
				if p_dvdqueueposition > v_dvdqueueposition then
				
					
				
					insert into test_table(memberid, dvdid, dateaddedinqueue, dvdqueueposition) -- insert the new record into the table
					values(p_memberid, p_dvdid, current_date, v_dvdqueueposition + 1);
				
-- 					update test_table
-- 					set dvdqueueposition = (select max(dvdqueueposition) from test_table where memberid = p_memberid)
-- 					where memberid = p_memberid and dvdid = p_dvdid;
				
				else 

   					update test_table
    				set dvdqueueposition = dvdqueueposition + 1
    				where dvdqueueposition >= p_dvdqueueposition
 					and memberid = p_memberid; -- update all other records greater than position
			
 					insert into test_table(memberid, dvdid, dateaddedinqueue, dvdqueueposition) -- insert the new record into the table
					values(p_memberid, p_dvdid, current_date, p_dvdqueueposition);
					
				end if; 

 		end if;
end; 
$$;
 s   DROP PROCEDURE public.queue_management2(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer);
       public          postgres    false                       1255    42167    stop_delete()    FUNCTION     �   CREATE FUNCTION public.stop_delete() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
BEGIN
	raise exception 'You cannot delete data from this table'; -- raise exception when someone tries to delete from table
END; 
$$;
 $   DROP FUNCTION public.stop_delete();
       public          postgres    false                       1255    41666 )   test_procedure(integer, integer, integer) 	   PROCEDURE     �  CREATE PROCEDURE public.test_procedure(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer)
    LANGUAGE plpgsql
    AS $$

declare

v_memberid INT;
v_dvdid INT;

begin	

		select memberid, dvdid from rentalqueue -- select all records where the memberid and dvdid matches input
		into v_memberid, v_dvdid;
		
		if v_memberid = p_memberid and v_dvdid = p_dvdid then 
			update test_table
 			set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
			where v_memberid = p_memberid and v_dvdid = p_dvdid;
 
		else
			update test_table
			set dvdqueueposition = dvdqueueposition + 1
			where dvdqueueposition >= p_dvdqueueposition; -- if the dvd queue position is greater than the input, +1 
	
			insert into test_table(memberid, dvdid, dateaddedinqueue, dvdqueueposition)
			values(p_memberid, p_dvdid, current_date, p_dvdqueueposition);
			
		 end if;

end; 
$$;
 p   DROP PROCEDURE public.test_procedure(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer);
       public          postgres    false                       1255    41667 *   test_procedure1(integer, integer, integer) 	   PROCEDURE     �  CREATE PROCEDURE public.test_procedure1(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer)
    LANGUAGE plpgsql
    AS $$

declare

v_memberid INT;
v_dvdid INT;

begin	

		select memberid, dvdid from rentalqueue -- select all records where the memberid and dvdid matches input
		into v_memberid, v_dvdid;
		
		if v_memberid = p_memberid and v_dvdid = p_dvdid then 
			update test_table
 			set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
			where v_memberid = p_memberid and v_dvdid = p_dvdid;
 
		else
			update test_table
			set dvdqueueposition = dvdqueueposition + 1
			where dvdqueueposition >= p_dvdqueueposition
			and v_memberid = p_memberid and v_dvdid = p_dvdid; -- if the dvd queue position is greater than the input, +1 
	
			insert into test_table(memberid, dvdid, dateaddedinqueue, dvdqueueposition)
			values(p_memberid, p_dvdid, current_date, p_dvdqueueposition);
			
		 end if;

end; 
$$;
 q   DROP PROCEDURE public.test_procedure1(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer);
       public          postgres    false            
           1255    41711 +   test_procedure10(integer, integer, integer) 	   PROCEDURE     �	  CREATE PROCEDURE public.test_procedure10(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer)
    LANGUAGE plpgsql
    AS $$

declare

v_counter INT;
v_dvdtest INT;
v_dvdqueueposition INT; 

begin	
		
 		select COUNT(*) from test_table
 		into v_counter -- add a counter for all records that match the given 'where' clause ie where memberid/dvdid exists 
 		where memberid = p_memberid and dvdid = p_dvdid;
		
		select dvdid from test_table
		into v_dvdtest
		where memberid = p_memberid;
		
		select dvdqueueposition from test_table
		into v_dvdqueueposition
		where memberid = p_memberid; 

 		if v_counter > 0  then  -- if records exists then...

			update test_table
 			set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
			where memberid = p_memberid and dvdid = p_dvdid; -- update table with new position
			
			if v_dvdqueueposition <> 1 then -- if the position of the dvd is not 1 then we can reshuffle
				update test_table
  				set dvdqueueposition = dvdqueueposition + 1 -- change all other positions to +1 
  				where dvdqueueposition >= p_dvdqueueposition
				and memberid = p_memberid;
				
			else -- otherwise, we need to shift everything down one
			
				update test_table
  				set dvdqueueposition = dvdqueueposition + 1 -- change all positions above by +1 
  				where dvdqueueposition >= p_dvdqueueposition
				and memberid = p_memberid;
				
				update test_table 
				set dvdqueueposition = dvdqueueposition - 1 -- change all positions below by -1
				-- where dvdqueueposition < p_dvdqueueposition
				where memberid = p_memberid; 
				
				update test_table 
				set dvdqueueposition = dvdqueueposition -1
				where memberid = p_memberid and dvdid = p_dvdid;
			
			end if;
		
		elsif v_dvdtest is null then -- where no dvds exist for that member in queue	
			
			insert into test_table(memberid, dvdid, dateaddedinqueue, dvdqueueposition)
			values (p_memberid, p_dvdid, current_date, 1);
 
  		else -- if record doesn't exist in table...
		
			insert into test_table(memberid, dvdid, dateaddedinqueue, dvdqueueposition) -- insert the new record into the table
			values(p_memberid, p_dvdid, current_date, p_dvdqueueposition);
			
  			update test_table
   			set dvdqueueposition = dvdqueueposition + 1
   			where dvdqueueposition > p_dvdqueueposition
			and memberid = p_memberid; -- update all other records greater than position
		
 		end if;

end; 
$$;
 r   DROP PROCEDURE public.test_procedure10(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer);
       public          postgres    false                       1255    41668 *   test_procedure2(integer, integer, integer) 	   PROCEDURE     �  CREATE PROCEDURE public.test_procedure2(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer)
    LANGUAGE plpgsql
    AS $$

declare

v_memberid INT;
v_dvdid INT;

begin	

		select memberid, dvdid from rentalqueue -- select all records where the memberid and dvdid matches input
		into v_memberid, v_dvdid;
		
		if v_memberid = p_memberid and v_dvdid = p_dvdid then 
			update test_table
 			set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
			where memberid = 12 and dvdid = 3;
 
		else
			update test_table
			set dvdqueueposition = dvdqueueposition + 1
			where dvdqueueposition >= p_dvdqueueposition
			and v_memberid = p_memberid and v_dvdid = p_dvdid; -- if the dvd queue position is greater than the input, +1 
	
			insert into test_table(memberid, dvdid, dateaddedinqueue, dvdqueueposition)
			values(p_memberid, p_dvdid, current_date, p_dvdqueueposition);
			
		 end if;

end; 
$$;
 q   DROP PROCEDURE public.test_procedure2(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer);
       public          postgres    false                       1255    41669 *   test_procedure3(integer, integer, integer) 	   PROCEDURE     �  CREATE PROCEDURE public.test_procedure3(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer)
    LANGUAGE plpgsql
    AS $$

declare

begin	


		update test_table
 		set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
		where memberid = 12 and dvdid = 3;
 
-- 		update test_table
-- 		set dvdqueueposition = dvdqueueposition + 1
-- 		where dvdqueueposition >= p_dvdqueueposition
-- 		and v_memberid = p_memberid and v_dvdid = p_dvdid; -- if the dvd queue position is greater than the input, +1 
	
-- 		insert into test_table(memberid, dvdid, dateaddedinqueue, dvdqueueposition)
-- 		values(p_memberid, p_dvdid, current_date, p_dvdqueueposition);
			
		 

end; 
$$;
 q   DROP PROCEDURE public.test_procedure3(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer);
       public          postgres    false                       1255    41670 *   test_procedure4(integer, integer, integer) 	   PROCEDURE     �  CREATE PROCEDURE public.test_procedure4(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer)
    LANGUAGE plpgsql
    AS $$

declare

begin	

		update test_table
 		set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
		where memberid = p_memberid and dvdid = p_dvdid;
 
-- 		update test_table
-- 		set dvdqueueposition = dvdqueueposition + 1
-- 		where dvdqueueposition >= p_dvdqueueposition
-- 		and v_memberid = p_memberid and v_dvdid = p_dvdid; -- if the dvd queue position is greater than the input, +1 
	
-- 		insert into test_table(memberid, dvdid, dateaddedinqueue, dvdqueueposition)
-- 		values(p_memberid, p_dvdid, current_date, p_dvdqueueposition);
			
		 

end; 
$$;
 q   DROP PROCEDURE public.test_procedure4(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer);
       public          postgres    false                       1255    41673 *   test_procedure5(integer, integer, integer) 	   PROCEDURE     �  CREATE PROCEDURE public.test_procedure5(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer)
    LANGUAGE plpgsql
    AS $$

declare

begin	
		
		if p_memberid = 12 and p_dvdid = 3 then

			update test_table
 			set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
			where memberid = p_memberid and dvdid = p_dvdid;
 
 		else 
			update test_table
 			set dvdqueueposition = dvdqueueposition + 1
 			where dvdqueueposition >= p_dvdqueueposition; -- if the dvd queue position is greater than the input, +1 
	
			insert into test_table(memberid, dvdid, dateaddedinqueue, dvdqueueposition)
			values(p_memberid, p_dvdid, current_date, p_dvdqueueposition);
			
		end if;

end; 
$$;
 q   DROP PROCEDURE public.test_procedure5(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer);
       public          postgres    false                       1255    41674 *   test_procedure6(integer, integer, integer) 	   PROCEDURE     S  CREATE PROCEDURE public.test_procedure6(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer)
    LANGUAGE plpgsql
    AS $$

declare

begin	
		
		if p_memberid = 12 and p_dvdid = 3 then

			update test_table
 			set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
			where memberid = p_memberid and dvdid = p_dvdid;
			
			update test_table
 			set dvdqueueposition = dvdqueueposition + 1
 			where dvdqueueposition >= p_dvdqueueposition;
 
 		else 
			
			update test_table
 			set dvdqueueposition = dvdqueueposition + 1
 			where dvdqueueposition >= p_dvdqueueposition; -- if the dvd queue position is greater than the input, +1
			
			insert into test_table(memberid, dvdid, dateaddedinqueue, dvdqueueposition)
			values(p_memberid, p_dvdid, current_date, p_dvdqueueposition);
	
		
		end if;

end; 
$$;
 q   DROP PROCEDURE public.test_procedure6(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer);
       public          postgres    false                       1255    41676 *   test_procedure7(integer, integer, integer) 	   PROCEDURE     D  CREATE PROCEDURE public.test_procedure7(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer)
    LANGUAGE plpgsql
    AS $$

declare

v_memberid INT;
v_dvdid INT; 

begin	
		
		select memberid, dvdid from test_table
		into v_memberid, v_dvdid;

		if p_memberid = v_memberid and p_dvdid = v_dvdid then

			update test_table
 			set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
			where memberid = p_memberid and dvdid = p_dvdid; -- update table with new position
			
			update test_table
 			set dvdqueueposition = dvdqueueposition + 1 -- change all positions to +1 
 			where dvdqueueposition >= p_dvdqueueposition;
 
 		else -- if record doesn't exist in table
		
			insert into test_table(memberid, dvdid, dateaddedinqueue, dvdqueueposition) -- insert the record into the table
			values(p_memberid, p_dvdid, current_date, p_dvdqueueposition);
			
			update test_table
 			set dvdqueueposition = dvdqueueposition + 1
 			where dvdqueueposition >= p_dvdqueueposition; -- update all other records greater than position
	
		
		end if;

end; 
$$;
 q   DROP PROCEDURE public.test_procedure7(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer);
       public          postgres    false            	           1255    41677 *   test_procedure8(integer, integer, integer) 	   PROCEDURE     v  CREATE PROCEDURE public.test_procedure8(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer)
    LANGUAGE plpgsql
    AS $$

declare

v_memberid INT;
v_dvdid INT; 

begin	
		
		select memberid, dvdid from test_table
		into v_memberid, v_dvdid
		where p_memberid = memberid and p_dvdid = dvdid;

		if p_memberid = v_memberid and p_dvdid = v_dvdid then

			update test_table
 			set dateaddedinqueue = current_date, dvdqueueposition = p_dvdqueueposition
			where memberid = p_memberid and dvdid = p_dvdid; -- update table with new position
			
			update test_table
 			set dvdqueueposition = dvdqueueposition + 1 -- change all positions to +1 
 			where dvdqueueposition >= p_dvdqueueposition;
 
 		else -- if record doesn't exist in table
		
			insert into test_table(memberid, dvdid, dateaddedinqueue, dvdqueueposition) -- insert the record into the table
			values(p_memberid, p_dvdid, current_date, p_dvdqueueposition);
			
			update test_table
 			set dvdqueueposition = dvdqueueposition + 1
 			where dvdqueueposition >= p_dvdqueueposition; -- update all other records greater than position
	
		
		end if;

end; 
$$;
 q   DROP PROCEDURE public.test_procedure8(IN p_memberid integer, IN p_dvdid integer, IN p_dvdqueueposition integer);
       public          postgres    false            �            1259    33736    city    TABLE     m   CREATE TABLE public.city (
    cityid numeric(10,0) NOT NULL,
    cityname character varying(32) NOT NULL
);
    DROP TABLE public.city;
       public         heap    postgres    false            �            1259    33811    dvd    TABLE     �  CREATE TABLE public.dvd (
    dvdid numeric(16,0) NOT NULL,
    dvdtitle character varying(100) NOT NULL,
    genreid numeric(2,0) NOT NULL,
    ratingid numeric(2,0) NOT NULL,
    dvdreleasedate timestamp(3) without time zone NOT NULL,
    theaterreleasedate timestamp(3) without time zone,
    dvdquantityonhand numeric(8,0) NOT NULL,
    dvdquantityonrent numeric(8,0) NOT NULL,
    dvdlostquantity numeric(8,0) NOT NULL
);
    DROP TABLE public.dvd;
       public         heap    postgres    false            �            1259    33879 	   dvdreview    TABLE     )  CREATE TABLE public.dvdreview (
    memberid integer NOT NULL,
    dvdid integer NOT NULL,
    starvalue integer NOT NULL,
    reviewdate date DEFAULT CURRENT_DATE NOT NULL,
    comment character varying,
    CONSTRAINT dvdreview_starvalue_check CHECK (((starvalue <= 5) AND (starvalue >= 0)))
);
    DROP TABLE public.dvdreview;
       public         heap    postgres    false            �            1259    33791    genre    TABLE     o   CREATE TABLE public.genre (
    genreid numeric(2,0) NOT NULL,
    genrename character varying(20) NOT NULL
);
    DROP TABLE public.genre;
       public         heap    postgres    false            �            1259    33766    member    TABLE       CREATE TABLE public.member (
    memberid numeric(12,0) NOT NULL,
    memberfirstname character varying(32) NOT NULL,
    memberlastname character varying(32) NOT NULL,
    memberinitial character varying(32),
    memberaddress character varying(100),
    memberaddressid numeric(10,0) NOT NULL,
    memberphone character varying(14),
    memberemail character varying(32) NOT NULL,
    memberpassword character varying(32) NOT NULL,
    membershipid numeric(10,0) NOT NULL,
    membersincedate timestamp(3) without time zone NOT NULL
);
    DROP TABLE public.member;
       public         heap    postgres    false            �            1259    33761 
   membership    TABLE     ^  CREATE TABLE public.membership (
    membershipid numeric(10,0) NOT NULL,
    membershiptype character varying(128) NOT NULL,
    membershiplimitpermonth numeric(2,0) NOT NULL,
    membershipmonthlyprice numeric(5,2) NOT NULL,
    membershipmonthlytax numeric(5,2) NOT NULL,
    membershipdvdlostprice numeric(5,2) NOT NULL,
    dvdattime integer
);
    DROP TABLE public.membership;
       public         heap    postgres    false            �            1259    33781    payment    TABLE       CREATE TABLE public.payment (
    paymentid numeric(16,0) NOT NULL,
    memberid numeric(12,0) NOT NULL,
    amountpaid numeric(8,2) NOT NULL,
    amountpaiddate timestamp(3) without time zone NOT NULL,
    amountpaiduntildate timestamp(3) without time zone NOT NULL
);
    DROP TABLE public.payment;
       public         heap    postgres    false            �            1259    33861    rental    TABLE     7  CREATE TABLE public.rental (
    rentalid numeric(16,0) NOT NULL,
    memberid numeric(12,0) NOT NULL,
    dvdid numeric(16,0) NOT NULL,
    rentalrequestdate timestamp(3) without time zone NOT NULL,
    rentalshippeddate timestamp(3) without time zone,
    rentalreturneddate timestamp(3) without time zone
);
    DROP TABLE public.rental;
       public         heap    postgres    false            �            1259    42258    hello    VIEW     �  CREATE VIEW public.hello AS
 SELECT member.memberid,
    membership.dvdattime,
    payment.paymentid,
    payment.amountpaid,
    rental.rentalid,
    rental.rentalrequestdate,
    rental.rentalshippeddate,
    rental.rentalreturneddate,
    dvd.dvdquantityonhand,
    dvd.dvdquantityonrent,
    dvd.dvdlostquantity
   FROM ((((public.member
     JOIN public.membership ON ((membership.membershipid = member.membershipid)))
     JOIN public.payment ON ((payment.memberid = member.memberid)))
     JOIN public.rental ON ((rental.memberid = member.memberid)))
     JOIN public.dvd ON ((dvd.dvdid = rental.dvdid)))
  WHERE (member.memberid = (1)::numeric)
 LIMIT 4;
    DROP VIEW public.hello;
       public          postgres    false    223    223    220    215    213    213    214    223    220    223    214    220    215    220    215    223    223            �            1259    42252    measures_measure_id_seq    SEQUENCE     �   CREATE SEQUENCE public.measures_measure_id_seq
    START WITH 10
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 .   DROP SEQUENCE public.measures_measure_id_seq;
       public          postgres    false    215            �           0    0    measures_measure_id_seq    SEQUENCE OWNED BY     Q   ALTER SEQUENCE public.measures_measure_id_seq OWNED BY public.payment.paymentid;
          public          postgres    false    232            �            1259    33806    movieperson    TABLE       CREATE TABLE public.movieperson (
    personid numeric(12,0) NOT NULL,
    personfirstname character varying(32) NOT NULL,
    personlastname character varying(32),
    personinitial character varying(32),
    persondateofbirth timestamp(3) without time zone
);
    DROP TABLE public.movieperson;
       public         heap    postgres    false            �            1259    33841    moviepersonrole    TABLE     �   CREATE TABLE public.moviepersonrole (
    personid numeric(12,0) NOT NULL,
    roleid numeric(2,0) NOT NULL,
    dvdid numeric(16,0) NOT NULL
);
 #   DROP TABLE public.moviepersonrole;
       public         heap    postgres    false            �            1259    42062    payment_history    TABLE       CREATE TABLE public.payment_history (
    paymenthistoryid integer NOT NULL,
    memberid integer NOT NULL,
    paymentid integer NOT NULL,
    amountpaid character varying(300),
    amountpaid_new character varying(300),
    amountpaiddate timestamp without time zone,
    amountpaiddate_new timestamp without time zone,
    amountpaiduntildate timestamp without time zone,
    amountpaiduntildate_new timestamp without time zone,
    changetype character varying(1),
    time_stamp timestamp without time zone
);
 #   DROP TABLE public.payment_history;
       public         heap    postgres    false            �            1259    42061 $   payment_history_paymenthistoryid_seq    SEQUENCE     �   CREATE SEQUENCE public.payment_history_paymenthistoryid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
 ;   DROP SEQUENCE public.payment_history_paymenthistoryid_seq;
       public          postgres    false    230            �           0    0 $   payment_history_paymenthistoryid_seq    SEQUENCE OWNED BY     m   ALTER SEQUENCE public.payment_history_paymenthistoryid_seq OWNED BY public.payment_history.paymenthistoryid;
          public          postgres    false    229            �            1259    33796    rating    TABLE     �   CREATE TABLE public.rating (
    ratingid numeric(2,0) NOT NULL,
    ratingname character varying(10) NOT NULL,
    ratingdescription character varying(255) NOT NULL
);
    DROP TABLE public.rating;
       public         heap    postgres    false            �            1259    42264    rentalid    SEQUENCE     s   CREATE SEQUENCE public.rentalid
    START WITH 104
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;
    DROP SEQUENCE public.rentalid;
       public          postgres    false    223            �           0    0    rentalid    SEQUENCE OWNED BY     @   ALTER SEQUENCE public.rentalid OWNED BY public.rental.rentalid;
          public          postgres    false    234            �            1259    33826    rentalqueue    TABLE     �   CREATE TABLE public.rentalqueue (
    memberid numeric(12,0) NOT NULL,
    dvdid numeric(16,0) NOT NULL,
    dateaddedinqueue timestamp(3) without time zone NOT NULL,
    dvdqueueposition integer
);
    DROP TABLE public.rentalqueue;
       public         heap    postgres    false            �            1259    33801    role    TABLE     l   CREATE TABLE public.role (
    roleid numeric(2,0) NOT NULL,
    rolename character varying(20) NOT NULL
);
    DROP TABLE public.role;
       public         heap    postgres    false            �            1259    41302    sequence_example    SEQUENCE     z   CREATE SEQUENCE public.sequence_example
    START WITH 11
    INCREMENT BY 1
    MINVALUE 11
    NO MAXVALUE
    CACHE 1;
 '   DROP SEQUENCE public.sequence_example;
       public          postgres    false    223            �           0    0    sequence_example    SEQUENCE OWNED BY     H   ALTER SEQUENCE public.sequence_example OWNED BY public.rental.rentalid;
          public          postgres    false    225            �            1259    33741    state    TABLE     o   CREATE TABLE public.state (
    stateid numeric(2,0) NOT NULL,
    statename character varying(20) NOT NULL
);
    DROP TABLE public.state;
       public         heap    postgres    false            �            1259    42190    total_member_movie_req    MATERIALIZED VIEW     �  CREATE MATERIALIZED VIEW public.total_member_movie_req AS
 SELECT (((m.memberfirstname)::text || ' '::text) || (m.memberlastname)::text) AS name,
    m.memberid,
    count(*) AS count
   FROM ((public.member m
     JOIN public.rentalqueue r ON ((r.memberid = m.memberid)))
     JOIN public.dvd d ON ((d.dvdid = r.dvdid)))
  GROUP BY m.memberfirstname, m.memberlastname, m.memberid
  WITH NO DATA;
 6   DROP MATERIALIZED VIEW public.total_member_movie_req;
       public         heap    postgres    false    214    214    214    220    221    221            �            1259    33746    zipcode    TABLE     �   CREATE TABLE public.zipcode (
    zipcodeid numeric(10,0) NOT NULL,
    zipcode character varying(5) NOT NULL,
    stateid numeric(2,0),
    cityid numeric(10,0)
);
    DROP TABLE public.zipcode;
       public         heap    postgres    false            �           2604    42253    payment paymentid    DEFAULT     x   ALTER TABLE ONLY public.payment ALTER COLUMN paymentid SET DEFAULT nextval('public.measures_measure_id_seq'::regclass);
 @   ALTER TABLE public.payment ALTER COLUMN paymentid DROP DEFAULT;
       public          postgres    false    232    215            �           2604    42065     payment_history paymenthistoryid    DEFAULT     �   ALTER TABLE ONLY public.payment_history ALTER COLUMN paymenthistoryid SET DEFAULT nextval('public.payment_history_paymenthistoryid_seq'::regclass);
 O   ALTER TABLE public.payment_history ALTER COLUMN paymenthistoryid DROP DEFAULT;
       public          postgres    false    229    230    230            �           2604    42268    rental rentalid    DEFAULT     g   ALTER TABLE ONLY public.rental ALTER COLUMN rentalid SET DEFAULT nextval('public.rentalid'::regclass);
 >   ALTER TABLE public.rental ALTER COLUMN rentalid DROP DEFAULT;
       public          postgres    false    234    223            �          0    33736    city 
   TABLE DATA           0   COPY public.city (cityid, cityname) FROM stdin;
    public          postgres    false    210   ��       �          0    33811    dvd 
   TABLE DATA           �   COPY public.dvd (dvdid, dvdtitle, genreid, ratingid, dvdreleasedate, theaterreleasedate, dvdquantityonhand, dvdquantityonrent, dvdlostquantity) FROM stdin;
    public          postgres    false    220   /�       �          0    33879 	   dvdreview 
   TABLE DATA           T   COPY public.dvdreview (memberid, dvdid, starvalue, reviewdate, comment) FROM stdin;
    public          postgres    false    224   �6      �          0    33791    genre 
   TABLE DATA           3   COPY public.genre (genreid, genrename) FROM stdin;
    public          postgres    false    216   �6      �          0    33766    member 
   TABLE DATA           �   COPY public.member (memberid, memberfirstname, memberlastname, memberinitial, memberaddress, memberaddressid, memberphone, memberemail, memberpassword, membershipid, membersincedate) FROM stdin;
    public          postgres    false    214   m7      �          0    33761 
   membership 
   TABLE DATA           �   COPY public.membership (membershipid, membershiptype, membershiplimitpermonth, membershipmonthlyprice, membershipmonthlytax, membershipdvdlostprice, dvdattime) FROM stdin;
    public          postgres    false    213   ��      �          0    33806    movieperson 
   TABLE DATA           r   COPY public.movieperson (personid, personfirstname, personlastname, personinitial, persondateofbirth) FROM stdin;
    public          postgres    false    219   ��      �          0    33841    moviepersonrole 
   TABLE DATA           B   COPY public.moviepersonrole (personid, roleid, dvdid) FROM stdin;
    public          postgres    false    222   6r      �          0    33781    payment 
   TABLE DATA           g   COPY public.payment (paymentid, memberid, amountpaid, amountpaiddate, amountpaiduntildate) FROM stdin;
    public          postgres    false    215   �r      �          0    42062    payment_history 
   TABLE DATA           �   COPY public.payment_history (paymenthistoryid, memberid, paymentid, amountpaid, amountpaid_new, amountpaiddate, amountpaiddate_new, amountpaiduntildate, amountpaiduntildate_new, changetype, time_stamp) FROM stdin;
    public          postgres    false    230   "s      �          0    33796    rating 
   TABLE DATA           I   COPY public.rating (ratingid, ratingname, ratingdescription) FROM stdin;
    public          postgres    false    217   �t      �          0    33861    rental 
   TABLE DATA           u   COPY public.rental (rentalid, memberid, dvdid, rentalrequestdate, rentalshippeddate, rentalreturneddate) FROM stdin;
    public          postgres    false    223   �u      �          0    33826    rentalqueue 
   TABLE DATA           Z   COPY public.rentalqueue (memberid, dvdid, dateaddedinqueue, dvdqueueposition) FROM stdin;
    public          postgres    false    221   
w      �          0    33801    role 
   TABLE DATA           0   COPY public.role (roleid, rolename) FROM stdin;
    public          postgres    false    218   ۱      �          0    33741    state 
   TABLE DATA           3   COPY public.state (stateid, statename) FROM stdin;
    public          postgres    false    211   '�      �          0    33746    zipcode 
   TABLE DATA           F   COPY public.zipcode (zipcodeid, zipcode, stateid, cityid) FROM stdin;
    public          postgres    false    212   ��      �           0    0    measures_measure_id_seq    SEQUENCE SET     F   SELECT pg_catalog.setval('public.measures_measure_id_seq', 16, true);
          public          postgres    false    232            �           0    0 $   payment_history_paymenthistoryid_seq    SEQUENCE SET     S   SELECT pg_catalog.setval('public.payment_history_paymenthistoryid_seq', 46, true);
          public          postgres    false    229            �           0    0    rentalid    SEQUENCE SET     8   SELECT pg_catalog.setval('public.rentalid', 150, true);
          public          postgres    false    234            �           0    0    sequence_example    SEQUENCE SET     ?   SELECT pg_catalog.setval('public.sequence_example', 13, true);
          public          postgres    false    225            �           2606    33740    city city_cityid_pk 
   CONSTRAINT     U   ALTER TABLE ONLY public.city
    ADD CONSTRAINT city_cityid_pk PRIMARY KEY (cityid);
 =   ALTER TABLE ONLY public.city DROP CONSTRAINT city_cityid_pk;
       public            postgres    false    210            �           2606    33815    dvd dvd_dvdid_pk 
   CONSTRAINT     Q   ALTER TABLE ONLY public.dvd
    ADD CONSTRAINT dvd_dvdid_pk PRIMARY KEY (dvdid);
 :   ALTER TABLE ONLY public.dvd DROP CONSTRAINT dvd_dvdid_pk;
       public            postgres    false    220                       2606    33887    dvdreview dvdreview_pkey 
   CONSTRAINT     c   ALTER TABLE ONLY public.dvdreview
    ADD CONSTRAINT dvdreview_pkey PRIMARY KEY (memberid, dvdid);
 B   ALTER TABLE ONLY public.dvdreview DROP CONSTRAINT dvdreview_pkey;
       public            postgres    false    224    224            �           2606    33795    genre genre_genreid_pk 
   CONSTRAINT     Y   ALTER TABLE ONLY public.genre
    ADD CONSTRAINT genre_genreid_pk PRIMARY KEY (genreid);
 @   ALTER TABLE ONLY public.genre DROP CONSTRAINT genre_genreid_pk;
       public            postgres    false    216            �           2606    33770    member member_memberid_pk 
   CONSTRAINT     ]   ALTER TABLE ONLY public.member
    ADD CONSTRAINT member_memberid_pk PRIMARY KEY (memberid);
 C   ALTER TABLE ONLY public.member DROP CONSTRAINT member_memberid_pk;
       public            postgres    false    214            �           2606    33765 %   membership membership_membershipid_pk 
   CONSTRAINT     m   ALTER TABLE ONLY public.membership
    ADD CONSTRAINT membership_membershipid_pk PRIMARY KEY (membershipid);
 O   ALTER TABLE ONLY public.membership DROP CONSTRAINT membership_membershipid_pk;
       public            postgres    false    213            �           2606    33810 #   movieperson movieperson_personid_pk 
   CONSTRAINT     g   ALTER TABLE ONLY public.movieperson
    ADD CONSTRAINT movieperson_personid_pk PRIMARY KEY (personid);
 M   ALTER TABLE ONLY public.movieperson DROP CONSTRAINT movieperson_personid_pk;
       public            postgres    false    219            �           2606    33845 "   moviepersonrole moviepersonrole_pk 
   CONSTRAINT     u   ALTER TABLE ONLY public.moviepersonrole
    ADD CONSTRAINT moviepersonrole_pk PRIMARY KEY (personid, dvdid, roleid);
 L   ALTER TABLE ONLY public.moviepersonrole DROP CONSTRAINT moviepersonrole_pk;
       public            postgres    false    222    222    222                       2606    42069 $   payment_history payment_history_pkey 
   CONSTRAINT     p   ALTER TABLE ONLY public.payment_history
    ADD CONSTRAINT payment_history_pkey PRIMARY KEY (paymenthistoryid);
 N   ALTER TABLE ONLY public.payment_history DROP CONSTRAINT payment_history_pkey;
       public            postgres    false    230            �           2606    33785    payment payment_paymentid_pk 
   CONSTRAINT     a   ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_paymentid_pk PRIMARY KEY (paymentid);
 F   ALTER TABLE ONLY public.payment DROP CONSTRAINT payment_paymentid_pk;
       public            postgres    false    215            �           2606    33800    rating rating_ratingid_pk 
   CONSTRAINT     ]   ALTER TABLE ONLY public.rating
    ADD CONSTRAINT rating_ratingid_pk PRIMARY KEY (ratingid);
 C   ALTER TABLE ONLY public.rating DROP CONSTRAINT rating_ratingid_pk;
       public            postgres    false    217                       2606    33865    rental rental_rentalid_pk 
   CONSTRAINT     ]   ALTER TABLE ONLY public.rental
    ADD CONSTRAINT rental_rentalid_pk PRIMARY KEY (rentalid);
 C   ALTER TABLE ONLY public.rental DROP CONSTRAINT rental_rentalid_pk;
       public            postgres    false    223            �           2606    33830 )   rentalqueue rentalqueue_memberid_dvdid_pk 
   CONSTRAINT     t   ALTER TABLE ONLY public.rentalqueue
    ADD CONSTRAINT rentalqueue_memberid_dvdid_pk PRIMARY KEY (memberid, dvdid);
 S   ALTER TABLE ONLY public.rentalqueue DROP CONSTRAINT rentalqueue_memberid_dvdid_pk;
       public            postgres    false    221    221            �           2606    33805    role role_roleid_pk 
   CONSTRAINT     U   ALTER TABLE ONLY public.role
    ADD CONSTRAINT role_roleid_pk PRIMARY KEY (roleid);
 =   ALTER TABLE ONLY public.role DROP CONSTRAINT role_roleid_pk;
       public            postgres    false    218            �           2606    33745    state state_stateid_pk 
   CONSTRAINT     Y   ALTER TABLE ONLY public.state
    ADD CONSTRAINT state_stateid_pk PRIMARY KEY (stateid);
 @   ALTER TABLE ONLY public.state DROP CONSTRAINT state_stateid_pk;
       public            postgres    false    211            �           2606    33750    zipcode zipcode_zipcodeid_pk 
   CONSTRAINT     a   ALTER TABLE ONLY public.zipcode
    ADD CONSTRAINT zipcode_zipcodeid_pk PRIMARY KEY (zipcodeid);
 F   ALTER TABLE ONLY public.zipcode DROP CONSTRAINT zipcode_zipcodeid_pk;
       public            postgres    false    212            �           1259    33876    i_membername    INDEX     Z   CREATE INDEX i_membername ON public.member USING btree (memberfirstname, memberlastname);
     DROP INDEX public.i_membername;
       public            postgres    false    214    214            �           1259    33877    i_personname    INDEX     _   CREATE INDEX i_personname ON public.movieperson USING btree (personfirstname, personlastname);
     DROP INDEX public.i_personname;
       public            postgres    false    219    219            �           1259    42176    idvdgenreid    INDEX     >   CREATE INDEX idvdgenreid ON public.dvd USING btree (genreid);
    DROP INDEX public.idvdgenreid;
       public            postgres    false    220            �           1259    42172    idvdid    INDEX     C   CREATE INDEX idvdid ON public.moviepersonrole USING btree (dvdid);
    DROP INDEX public.idvdid;
       public            postgres    false    222            �           1259    42181    idvdratingid    INDEX     @   CREATE INDEX idvdratingid ON public.dvd USING btree (ratingid);
     DROP INDEX public.idvdratingid;
       public            postgres    false    220            �           1259    42173    iorder    INDEX     Y   CREATE INDEX iorder ON public.movieperson USING btree (personlastname, personfirstname);
    DROP INDEX public.iorder;
       public            postgres    false    219    219            �           1259    42174 	   ipersonid    INDEX     I   CREATE INDEX ipersonid ON public.moviepersonrole USING btree (personid);
    DROP INDEX public.ipersonid;
       public            postgres    false    222            �           1259    42188    irdvdid    INDEX     ;   CREATE INDEX irdvdid ON public.rental USING btree (dvdid);
    DROP INDEX public.irdvdid;
       public            postgres    false    223                        1259    42175    irentalmemberid    INDEX     F   CREATE INDEX irentalmemberid ON public.rental USING btree (memberid);
 #   DROP INDEX public.irentalmemberid;
       public            postgres    false    223                       1259    42187 
   irmemberid    INDEX     A   CREATE INDEX irmemberid ON public.rental USING btree (memberid);
    DROP INDEX public.irmemberid;
       public            postgres    false    223            �           1259    42171    iroleid    INDEX     E   CREATE INDEX iroleid ON public.moviepersonrole USING btree (roleid);
    DROP INDEX public.iroleid;
       public            postgres    false    222                       2620    42098    payment audit_table    TRIGGER     }   CREATE TRIGGER audit_table BEFORE INSERT OR DELETE OR UPDATE ON public.payment FOR EACH ROW EXECUTE FUNCTION public.audit();
 ,   DROP TRIGGER audit_table ON public.payment;
       public          postgres    false    215    267                       2620    42168    payment_history delete_trigger    TRIGGER     �   CREATE TRIGGER delete_trigger BEFORE DELETE ON public.payment_history FOR EACH STATEMENT EXECUTE FUNCTION public.stop_delete();
 7   DROP TRIGGER delete_trigger ON public.payment_history;
       public          postgres    false    230    268                       2606    33816    dvd dvd_genreid_fk    FK CONSTRAINT     v   ALTER TABLE ONLY public.dvd
    ADD CONSTRAINT dvd_genreid_fk FOREIGN KEY (genreid) REFERENCES public.genre(genreid);
 <   ALTER TABLE ONLY public.dvd DROP CONSTRAINT dvd_genreid_fk;
       public          postgres    false    216    3563    220                       2606    33821    dvd dvd_ratingid    FK CONSTRAINT     w   ALTER TABLE ONLY public.dvd
    ADD CONSTRAINT dvd_ratingid FOREIGN KEY (ratingid) REFERENCES public.rating(ratingid);
 :   ALTER TABLE ONLY public.dvd DROP CONSTRAINT dvd_ratingid;
       public          postgres    false    3565    220    217                       2606    33893    dvdreview dvdreview_dvdid_fkey    FK CONSTRAINT     |   ALTER TABLE ONLY public.dvdreview
    ADD CONSTRAINT dvdreview_dvdid_fkey FOREIGN KEY (dvdid) REFERENCES public.dvd(dvdid);
 H   ALTER TABLE ONLY public.dvdreview DROP CONSTRAINT dvdreview_dvdid_fkey;
       public          postgres    false    220    3573    224                       2606    33888 !   dvdreview dvdreview_memberid_fkey    FK CONSTRAINT     �   ALTER TABLE ONLY public.dvdreview
    ADD CONSTRAINT dvdreview_memberid_fkey FOREIGN KEY (memberid) REFERENCES public.member(memberid);
 K   ALTER TABLE ONLY public.dvdreview DROP CONSTRAINT dvdreview_memberid_fkey;
       public          postgres    false    214    224    3559            
           2606    33771    member member_memberaddid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY public.member
    ADD CONSTRAINT member_memberaddid_fk FOREIGN KEY (memberaddressid) REFERENCES public.zipcode(zipcodeid);
 F   ALTER TABLE ONLY public.member DROP CONSTRAINT member_memberaddid_fk;
       public          postgres    false    3554    214    212                       2606    33776    member member_membershipid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY public.member
    ADD CONSTRAINT member_membershipid_fk FOREIGN KEY (membershipid) REFERENCES public.membership(membershipid);
 G   ALTER TABLE ONLY public.member DROP CONSTRAINT member_membershipid_fk;
       public          postgres    false    3556    213    214                       2606    33851 (   moviepersonrole moviepersonrole_dvdid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY public.moviepersonrole
    ADD CONSTRAINT moviepersonrole_dvdid_fk FOREIGN KEY (dvdid) REFERENCES public.dvd(dvdid);
 R   ALTER TABLE ONLY public.moviepersonrole DROP CONSTRAINT moviepersonrole_dvdid_fk;
       public          postgres    false    3573    220    222                       2606    33846 +   moviepersonrole moviepersonrole_personid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY public.moviepersonrole
    ADD CONSTRAINT moviepersonrole_personid_fk FOREIGN KEY (personid) REFERENCES public.movieperson(personid);
 U   ALTER TABLE ONLY public.moviepersonrole DROP CONSTRAINT moviepersonrole_personid_fk;
       public          postgres    false    219    222    3571                       2606    33856 )   moviepersonrole moviepersonrole_roleid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY public.moviepersonrole
    ADD CONSTRAINT moviepersonrole_roleid_fk FOREIGN KEY (roleid) REFERENCES public.role(roleid);
 S   ALTER TABLE ONLY public.moviepersonrole DROP CONSTRAINT moviepersonrole_roleid_fk;
       public          postgres    false    218    3567    222                       2606    33786    payment payment_memberid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY public.payment
    ADD CONSTRAINT payment_memberid_fk FOREIGN KEY (memberid) REFERENCES public.member(memberid);
 E   ALTER TABLE ONLY public.payment DROP CONSTRAINT payment_memberid_fk;
       public          postgres    false    215    214    3559                       2606    33871    rental rental_dvdid_fk    FK CONSTRAINT     t   ALTER TABLE ONLY public.rental
    ADD CONSTRAINT rental_dvdid_fk FOREIGN KEY (dvdid) REFERENCES public.dvd(dvdid);
 @   ALTER TABLE ONLY public.rental DROP CONSTRAINT rental_dvdid_fk;
       public          postgres    false    3573    220    223                       2606    33866    rental rental_memberid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY public.rental
    ADD CONSTRAINT rental_memberid_fk FOREIGN KEY (memberid) REFERENCES public.member(memberid);
 C   ALTER TABLE ONLY public.rental DROP CONSTRAINT rental_memberid_fk;
       public          postgres    false    3559    214    223                       2606    33836     rentalqueue rentalqueue_dvdid_fk    FK CONSTRAINT     ~   ALTER TABLE ONLY public.rentalqueue
    ADD CONSTRAINT rentalqueue_dvdid_fk FOREIGN KEY (dvdid) REFERENCES public.dvd(dvdid);
 J   ALTER TABLE ONLY public.rentalqueue DROP CONSTRAINT rentalqueue_dvdid_fk;
       public          postgres    false    220    3573    221                       2606    33831 #   rentalqueue rentalqueue_memberid_fk    FK CONSTRAINT     �   ALTER TABLE ONLY public.rentalqueue
    ADD CONSTRAINT rentalqueue_memberid_fk FOREIGN KEY (memberid) REFERENCES public.member(memberid);
 M   ALTER TABLE ONLY public.rentalqueue DROP CONSTRAINT rentalqueue_memberid_fk;
       public          postgres    false    221    3559    214            	           2606    33756    zipcode zipcode_cityid_fk    FK CONSTRAINT     z   ALTER TABLE ONLY public.zipcode
    ADD CONSTRAINT zipcode_cityid_fk FOREIGN KEY (cityid) REFERENCES public.city(cityid);
 C   ALTER TABLE ONLY public.zipcode DROP CONSTRAINT zipcode_cityid_fk;
       public          postgres    false    3550    210    212                       2606    33751    zipcode zipcode_stateid_fk    FK CONSTRAINT     ~   ALTER TABLE ONLY public.zipcode
    ADD CONSTRAINT zipcode_stateid_fk FOREIGN KEY (stateid) REFERENCES public.state(stateid);
 D   ALTER TABLE ONLY public.zipcode DROP CONSTRAINT zipcode_stateid_fk;
       public          postgres    false    211    3552    212            �           0    42190    total_member_movie_req    MATERIALIZED VIEW DATA     9   REFRESH MATERIALIZED VIEW public.total_member_movie_req;
          public          postgres    false    231    3773            �   �   x�5��
�0 ϻ_�/��ױADE�P/���M��ſ�ކa�"y�`�م��9{J��;��j!M���贝b�[�;8S7���c���*1�Dx��tXvI�5T�&���Ʊ��j�ɷ��p���?hJ��fU�-[��
���4Z      �      x���˖丕-8f}k�#E4�cr�����
��(i7��QN#M|����︫g�=�Q��� $@�0�ի��,�N��y�O\�qw?Vệ��^�6H�8�Q���QF�+�/��Qb�,���?��V4U���W}�� 	XY�/{�J�ee�ʟ��g��?��S����;q�?]<�������嫕���g<�|=T�ת?֭h�U�z��<^�J��¹�(^%>�������s�	���ޅ���	p��?X��v��kqƽ\v��s�3F=��D��]�c<�wU;T��1��WyaoDY��`�{�2����m����?�>����� �g��v"��s������U��|]]#ƺk��!�;����ji��l�GLmr�-���o�f_��Uw<�aXV�����ɟ�Ƀ�u������-���l� lR�:Dz�8�Z���w��x�����y+�ߏ�_O�
�F8��ű��x^���&�&z���Պ�gԇ���R�cS��dV��S�vR�^)�VȂ_�vN�o�ϯ�_�Z/��x������A4���73�!�L�Sw'�/>�6���$��D�o��fE�Q�z8k�Bl�"&^'�GM��B�>ߺ��^�4��~��g�g|e,�R,���V݄bûQ-��>h�	����f	>v�0V��֢���,���W��+3o)8��h����8�
��m+��#<�k��Uk��ħ\[ �'�b�8K_�eo~�u�C3`>J"�xmX��l|�C>ۛ�c��v�U�05��ȯy�O��`&���Q����<w��̽@	^ �oi|���ӫ�C�(vg��>.�/�zr�&���|T|��3������H��h�X���,�E�g��O��wg8�]��G?G�Kp�Ч�s�,x=�u7an[81��V��3�4Ahÿ��0w/^L��4�/�����i��*��;�~_� &��O� �n~����];v�r��V�����Ϸ�i�*vO�D���»F���v��a%a��SgY݌7b���1��s�f��i��pK兽E�"�広�&w�k}�V�Zr�Pī���v�����]����i�X� ����u���9���x�%��w�����sJ˂+b������!�Mx�4Y�=�{�p�9��� �ۇ�u�b��J�����G��.{�2�̥�Y�<2�vf�u�/�sgy#/� f9��6I���Ç����b$�9sC�B~L��gi�e)N��#/�Ra\�
��|͕�*W�C����Y�Ω1kv +�}/\7"#��;�Y!?*}XD���!������J����z���I��|?����<��jL��
vr�w��@Ȱ׉"im���G���8u;ќOC�<�cs3����:��V�o���h_�4�=�89~;�7)��&>�o���H߇�!Dq�	-�XG1�]*��J�(ruיcUd$H��<�N�����"9���c�o@|�������|eY��2"�s�5>N��NOw��-�u/��n����z���2e���!P���L��?&�� ̍W2iy�=.���o]4G<,�tޛ��'u�@L��"
n�*w���{��;�������
|pr���6W�>Ά���y������^���m�R򹮺�^�V��wC�ء"�4�.�F�Uȣ�'��^�
�.���>6Ux�uOf�Lf���T)aj��$U|���s7UhK�Jܵ�s�� Fw1\o�v����)+[�.�+�y�Q4�U;�x;���=&nQ�⹝/�-�y�8��jp�sWe�QRf�C��\!Y�h'֔��jep[�p�%�}}_	4ң�χ���#s4�N"��_H)���b�*�H��0*��� E�vc_��%t�+�|��&�} 0��H�mb<��;��;cկ�P�^{u���`�]qX�!�5��ɉH��x�V5�s�t�x��&�V��[3�v<����M��e�[�C�vۍ�,WM4/.>U�����1��s,4����w8���9��D�NXu��E1q���`���\�5�""�������&ȧ&��u��h+\��Gr�+�Gk8@�VYe��_�>)#��3m'Z��*-r����G�� �.��XU���@R���y��J�Z�j���p�Ӆ[���+74���mg�Y�2$����������r!G����mX��A��,�@�~�&�k�����<�j�8�T������L����S&Mdh��b�t���{܌H��(H��|�vu�<�.�r���̯f�)
V���k�h+�\�/�w%�����z��y�޶�~P-�~������f.���T��)k�IpY?�o!l�U�����"������;�{�9�ޯ�s���WQ�[�m}x���W�"�p�qT�ܷ@e�����k�W�Z��<L�cծ�8*r��_�[���.����+&�*�X��u䴔н;YB4�:scׇ�%��U�;�me��H=�kG:^��7��5�q��шg�Dy(����vb�9VM#z�n���;8/�a�]uZW�7*mTa�E���\��om���j�	x��l�M���+Qu')3��s\�K��2�����:J����bp1��^V�����4�rR+Euzt����5X��u��5|����-�n��I3�ii�>I��F+�>v�'0���Ex!�.�[��ܵ*�	ʜ�u���vqq�+�.��i:1����+A��U��NP$��N�)C(b����
��x��$��n�4sߕ��V��>� �W���z�{1���y	�i!��&�]/F�F�o�?q�!췌ʛ����u6d+x}�u�M<K�/�v�wga:k2T��C��vdd�(�.!�������{�~#/��$Uh�D�7=ܶ^[NV���n`K�<�s,A�Q7�n&
�!	���������C_����eri���\!��G)�����l��Jx�yp�28��9|�n��`����y\�M�Ty��를fD���jvC�M>�"8ղa��]4�����q�QBwfd^d����%��ȡ�[���[`���W�~BNF��7�}�
.`�+����R�$�If������*��ڂ�*da� p�|�jr;���?�R��\��T���a/�-w�L�k�K7$$f:߾�k;%N�|a{�H��Q;ѿ
o�?NU�!��p���<3�
�D!ұO�~#F�MC5_9��ݱXFa�?]��J����^Nc��*��5�
@��֯�)���G1���=ẗ́��*��Q�kC�>�\�u��QY�m��tK��2��i���~�(�SgEb��^����� yԃy�i2�x��0�;C�(�s1�.>�� ��\>׿��S���p���U��y! U>gq�y��*�	�g<v�
���51��,A_n��ϲI+g��&诺�A6;������y�8���w�S���/��TAر�6z�T[��*
����
�
Ũ+�^�A�q�������D�e����U���!��e�KX�Bv8���{�[��c�b��J��E��W��5U'��hKb��S!�UB�!aT�%I�:*o!�[�=��8~ӽ8��p�!��TU�6�8����/�K����i8@�y�,,����'�hK���rR�!v�>�/C���9�.�,*��T��j�����N��Xy(Q	Y#�MYnK7Sߝ*�^8I��e�8�Ȓ�2�!ظh;0K=�m���Dz� ~~s����d�ܽ��{Qc�(�qp;�X�M�	��4��
�]tq��ɺ�j_��%�g��4��=O��*�v�/*�$�Ai�X��܂��h8���-;-w;����C�%ʚ�{����][JX�Zb���Q"�^Om�qZx]��c����Ul��N�D]?��d���w�8��v���PUe��Cn��~���M�W�,�d�{��k���2n`O��1r�|8g#�[���颁��5˒�ڨ�6P��5��@n"lϧU=�&����M���T�v��ף�|�e9�'v���T��ˍ6lV�    � ��[%N��)L>��,6҅2ͩ��p,߂:r�[䑅��R�����JA��6 �H�r,.@V(�-�}`��3�<x�t��Qg�<�}=��:X��CpO!ۨ��1ݰQeRݣ[�&���h��D"z�D�޴XB�1L�_a�(h�1*��Uw<�:�~^��w�цp���,�)�m�a�*G}}���ށӆT���,yʢ�_��~*��l�]�p�w�������i�$t3���_�~�*�R�Ϙ�O�\���/�q	nt���(+��O��qS�{�r�Q� [�+���� 9�s<��S:ժoc��U�G#�	�Q��ɥl� ��>�q:�!��q�صH�!Ī_�Q=
�ʊ4�h�uO7u+�sO�(Kѱ��=<ϫj��`{�
�p^��?/��@��8�?<Z���Ӎ�(�1�2E,�{(����}�=���0G��pʪ�,���A��]7�2*���=�Ԓa\4�c��sm$�e|�����d��H~|;Qj����'4�����z�<T�t�����U��?�Ľ]-L�"K�����)��R�=���d���)�+�@��8���c��"R*�.����G��Rub�J��zW��X ����^`�6�_�t�;�b��C!࿡?��aލ]k�m�Sm0�xă/�ݾ�~���(#E�y�	RH��M��2N�R[��%QN(А����0[�<�kB��<J!��lJX�6�f��gQ|n��dʘH�b�ZΣ<��~�,�
����W��=�� +0�G��k��\�]����j�坭at�Ge�M������&��!��=_��L_��G�zm���(~q�ne1����������[����2����(4q''�N?�li �Jn�	�s7�R�e�_�t�*Yfu�;�odۻ`yU�ֆ�ˑ����M5���]>�_��8a�����l��j��|�mp�9S��m�?T�Qr"��JN$�7gE��8	H�����2�SUV1��|N�8+���b�ի2�ۋ֘E�x�*�J�a�2�ޙ��l�Y� G�����&�[�2�!��! �����pB��q )n���lFr㈸������IpӜ�Z��� x5u�b�yJ@C`��ݬN��I�����"���4�P�?��_��/bg��o�iz�ظ�]wR��}+/klB<�K�!8/� ���.ak�����7����M�ݩ�����(,S�A0���nN��eG�jkZ�]��\�J'��+����q1��̑J��x���Fn "ˋ�&6���`���3DD�1�"�㹈��ٷ(T�S�ᅥM=�9�!�&b��*'�6O�IR-j���ﺽU��|g:Y�������l���)a%�-��OR�^i����y���l�gc���y��Dn������N=J|8�ȋ#ɐ"ߋ�b�� �*6T��',�ƎՀ���*�XWtUAƂ�H��{�4�容�a���4���C��o_w��!R[��L|s�$Tf.g�-�Z��> ٱ���Xc=AJc�8��t��%����<�}_���Ϩ�Otp�ȓn4G?"����>�*DO}���
�g�6'�JhOJٱ�%��/b�5��*n��8�H�W�����(���)�LM#�U�G�j,ˢ2d��O�x�gI�
� �*8� p�w��k�,!����Z��%!��`$u$�BQG7�W����+HQ?<M����kѺ�[�u�)�O!��PKaMXbDے��A���{X��i~����B�C���	w��k�~���YR�eIu��2���� �[�x�#1e��b��U�NN���H��Ӄuh�+���c��g������R5��C}��K����2<����03�W,|�T`163!�����f��������т���6�@gI��/�wY/!h�*�$HK�m���u��'�ҍ\Z6[��D���t��-�[c�*3��gp���STQ�j�wC�ҤJ]��P�Y�=cu�
>��+�O�+�"�e���<H�̨aw�Rg��-��ġ9u���.��x#�5��m�淂#�s|�ۮ�p	��S�[��4S�b��.�^��^�UQ��b�;y�K�<G)����Y4&6��A�m�y�	�]'��!�:vR������y��d1����3�����~B��������K6RM�0���TRۨ���k��,0�"�JZe��Xr�Ņ��N'K,�n�@&���|�0�7�y]�,]��!��\����o��  iSHvS:�˅d�[�Z���t��ʚ�[��#b�������{��p�p"�OFTE(x+�ȟ�8�ZyR�-�g��/��EeΈZ^F�rF�Z���7���Cxѯ8�>ȿ�1<�(<����Q��e �8I�U�K(j�\����zXu���,�c�T�������Yn�/K(e��Z;������G$��r)uk��	�R�d\hT%�&���p�O�20�����i�8/���}x162�3�k��]�N������s#ˊo�ۮkքA�E�D�o�~79�?��j3�``���**�;��8|I�y��¼�n0����H�+E��A��ٝ�~�->�O�Xp���$���#�X
G<�����bx2��5��x(oG����
�ǹTR��sy����qD5�o�i��Ob8�!.��oի8J��ߺ�JR#B�6��xq�	�h�q�( ��<���3�4s��$�z8,@y����j�E��x��Hj�%���2:ɋ�2x#�g W\�_�����aT� �R�L��j���T�Q�F�qmtjcݽ������7HCMX���~�D��1C��U����if%�KZP���~1���Iԏ�[l!�(�X3t_��!�i�c�Z�j�k���w��cv��CE�-Q�!�{�0x��#���]��� �"�����ا<x��P=蕬`@ �b3���,�0N��T��׃fEpUc1��}��-3BX�9�ԍ�t����y�XX�h��r�L(Jt�t�X�OK!�:����U$&��6�tb���|}� �z^�}	��-~C��MlI���ZHC|O莴b<��<�Z��Xw}��W��"����b�i����ߓߋ��?~�<�%��ӌ��c���&��Pц4P�Ew����k.mA���8/��+�hV�>�m� ��pH�k���F��Z�x灒�ӥ�FyU��L@w
�<����G���
�O����qpq�9D�d������x2!�lѴh �V�z��e�H:�T�`�N�����Ϟ[sWӇ�P�
q����؝N��`&/��4i�8��u�{�=� �Ȉ��\1ʪ
�TB�eҥ�J"�-�"��l��#�Vh��{J��'�kL��&��}��ѐ���2Mį��(�N(+�7aY��H���>N�N�f���M�M�X��w��É���j�J|�D>o�Q�.��n�U�c�-/�	h˃��I̦J�+��&!fͨD_��=��F�d.H��E
'y G����_��#']ȶs��@Ͷ!QV�̀Y#LA\��|�̊��֧��>�q�Wjj�x��B���(�]4O�6~W�_N��S �����c5���;8�Ǯ3���F���Ꝯ$uJ���rt��R�a]�#
��Ȣ�V�Գ,�S{F�Ec��|+&��J�F��f������J���ntI; �q�J� N9�l����z��k6 �q:��ڝ� J��=s�fF��b��],�̅$�h$�ʈR�(��8-� ӎ15 R%�v{i�"x��=Y|�%�u*[�8�@ӡ��7:���2�C�o�$��Φ�+�ŬTI:�Y ���o�T�L��W�%7�FT͝��4��R�U��SG3�qY^C���,~h�2� �#Q$�Xw6���u3���[�Sr��0Wk|pJ��{�M��{>�']�1�I���sV�	���<�� I�Gh8���]��^�s�Vjhq�u�~F�\c-��iw�������6Ftw;��W�vS=�-��NpL+��9-��0�u��U�Y4ňG�7    �==�Qu�S썎F�BG�~Bmdh��a�wڣ��Wm'�J��*�(�vQ����	?���T�������i*AH������_2�8O�@V����o���(�Z��m�ys��<����Es�e0����-.x �+��j��b~Z���+Z��M�gS����l��Y$�M[�K�~����W�M����A��k�P	I��y��*��w�!��ONN�Q9�i��<�|�D��`)�*yIG�KnQ�G�}�حqz	!��l��Ro�f�A��]b�{*��4�u��Y�x�"z2�>N���JH�7���ƮJ����%��ձ�U%_�o����)�cHi�i\ƛ��~O�n)�P�����I ��a�W����o�/SxeH������G*n��'��/3�
��X��Gcb1N�b��ύ��4pM�l�*��C�7V楯p���d��, ���K���g�)i�,��]7��m�<��Q����H�ǻ��d�����;w�[L�I�:�3��<@����
��7��d��"?���֟ǇM�]�ݟ_\wV�DN�ђ(��j�_9!��FA�W����6��r�$�h��i8hB�蜲�
��=�2��;��@6n��=��P���Wm~O�RSe��C���od�~��DE�����|o=���?��5�� �O�2�[���Δ�rB�/��Z���j�X���e�T�(a,��',P�s�̭pv'�ûDS6-ā��&��P�O�H��UH]���ބ��d�o��o�&���!fH;��f٠���!aQ�K²���Ëp��%F��>��C��U0�i�fto1aE�n:�q��\!�C��&�T
����oս�fGʈ���G�5��𪸴h�99欥FL�,�rsmCbB�g��,�K828�U��!0���n|o>��q�ֿc&h��)�H���܆��݁7o�Ϻ$�=O�7w�E�T����C��g��d�J�����)��m@��9���%<��`�)|Q�hA��^H��)N	��L±Ա����v������Gc�܏����������B_l���G�V���R\$�q�8-��<��D��Ty��h�#��&$q��� ]�LA��܉���!/8���\�>��w�����Ï��\:Z@
D����⹮�I��MS���(Ȑ-�Q���^F�\wH<_��}���Y�8��saA�I볶!�h��ۺ}B�%�Q�n���+Υhu7Qv�э���n�~�iV���4!I��T�bwƈI	��u���;:	ǡ�g�ғN����qpW�P��%~$����v0�ڬoAs�$	��=��eenE�h��q�{�\H)d�
K#MSp�U�����/D^L0�c��dNvO�B�#��<�Bi$IȞQNft؟Um��+�HA�� E�Ψk��^���EJ�;H	M�H�2��������'�}2	rN���O5�Ͳ�cc�sM�Q�I� @�8Y��C��s�o����	ox���C���s����g�&���!7�4jS"�I7�d�(�$��8����V���^��b0�����	��Ql$&���S�/{)�;�����I}�&��+ug�50���N�z�K���T��+'2p�V#K�2���=�r�Qa�J�Q�/�
�3�`���[��z�!���X3��k;1��
J� �pM#�DZ9WcYTf�E�:�T0�${a�y�8����~9�sC�7$Y&�k+p8S���KD���N�P6�Y4�p��{h-�AI��J�V�dp���4+�I�)6�-���U?�6��*+`��W,<�tҫY��j�ك��-˾j7
@Tn_��)q_���N�8�^���0Mr6d��]��f��;+f4�.�yp�IJ/��YH�?�ES4�$����x�����f���'�7���gl��f�pW4@Ne�y��gHL����J9{��)�r�wVsш�"���[�ܙ�5�鱺I�o!>h;��	�SI6"ͼ��ԻU�jG?���4��W��^c7ә�~W%ѼF������၁(1��`G�K^5�%����b��*�	�r��/t��8>S�c/ &�[џq0�(������%�����񊎷qJ]�+�h�Le�i�Xz�Z��,����HB9W�
��n`E\�f�W2��XY<��ة��/$E�d
W��`��ɤ(�e����SA���x	-�<��J�$��I���*U3.�Dcv}26ivK���ց���x	��?)y�V�"�^w����AM�K�8���)�8���Ԉe�_"ߐ�L��Yp%�F�c����ٷ�0J�ԁ~-�lFTܶ���23Uğ}��xW���ZY1��KyS5Y�zT�&|@����*��DL��qL�2����z'���ڋ#<�Cꫧ�Ow$`|�UM|6�F�K�@fQ�u�Xz���B�g҈�أ�=M}.�H@�~|��zw0�(��ѺꝌ�����ػɂi�D�J����F��4+lMDp�i#�2�	�C���^~zy����K7%$Sӭ}E@V�rnsZ=e�����-�D�D0�4*e۔��q]�����ۂJ�V,���	u����)aJ��X��x��Q4VÎ��}}S��o�1����б����qD���b��FF��;���Tgm��3�+�v�zW�W��?*p��"�њ؝,y[d��2lb�}�N���y�oC�&eXS��k��If{A¶�^0eE�[{��mͦI-���W�I)+Qf8G��<��u� �۩�Y���RTǋZ�w�x���A�Kc�*J��#J�+V5��m�t�4��v�>Bd|Y�{C�^&$�3((���'�k���oFEoIy����sx[u���i�⼉O�)WVK;��1g�JQR))�F�G�+�:`�?U����\v��J!#T&�����/!<h��m<�Q�X��m����&��ʚ�����I�w��4�����3���s4�j��G��
Q�?g���&���[sؖ���9l��)�r#f�[J��p��T�j�����+'�����Pi�ם���/���|I�x�/i�w�ck�^�*���z�q��s���ϗ'��yi\�����PjtS������I���B>p�,
K�B?��r��#�pk���	�pW��~�0��~�=�;%�w�sM8N���I�<�K{2Zj'M����t�0��W{#�y�ۅ�4���{2mW/�Q�\TC1MRZ0��C��p��B!�&҈\����@M8�/���x����Qq׈-��&E�A��s-x��K�BΫd�w-���o_�M]��y�W�E}���GRż4��o�@(2����6�+¬.4�5RH�4���b_�?�T����,�I]j�{J�վ�-�Ѹ	�ImT�1M�~��0�������f+M����b���A=��K� ����gٗ�����娍��̡�]?X��`1Z�1�\��];�6ɰ���:�G�I�]�;t��aF���(]������8A�Ai־�F�c��r%6|� ��<�R��Ft&�"p�,�kG;���o$%��\��zt	>��B��z�~���rb�x�� gZ�#������Z�W�ݺ#��y( [����n��Q��PI^�� qO��x�ٯ�z�2Y��=���7%z�4˃w�$Ϯ���
8�f�����*l_<C�3�OG�Ӭ�4�(�Sr��V�qЖ�Z�G��9+-%=��C��U�����F��(˄ ��r:\��L�Y":��5G+�45Fد�� ���"�7��M�THW���I ��Q������F̞��������v�Aa#?t>��"��?^�����AÊWmxO@Մ�˕r�AMt������)�;H��	�b%��}T{�5�˲1�&�K����<��N��[*|p�ƈ�����a'NJ �	|9����5g�7"�.<�5�R݌����2rp^W�QJ�UNKJ����*��5�i�fn���y�����#���(����㦀�����&��uR��X�mٱ�{
/�yp��    ����BGI��ӢT���f�\pe^�����E	���������5Qݿ����n��7�)�!��X��g�K�������r�s�����Bl����	���N"O� J�8���J���5���w!�Glx����N�B+�%�Q�^���w^�l�%"||� ���,2nK����O_f3FÞأ#0o�i�K���w�^���wH��/g�rF΅X����"�� ���Y ����&6-K�������dC��t"ګe��J�i�P���y1�[o;�ZY�KLp|7~Y�uen�u�=1��S��ЦY'��'!�M�!u�(�$���@��E�D40'�R-�ю"�j�4̕S�Dt~q�j�d�����?����]�[���
��(G���ȝa�����g�sK�3�8V'�t/�˕��c�=��E�����>k�o	0�2g򻩒�c�	�� z7(cLs�����B��Qp��c9��1O4��K�c�(���ľ{���9PKb�#	��򙙦޽���Pb�Ò��*�aS�֩N�8>
\��TĮ�R��u�>XL��ƴ*Y��!^׻Q��b+?s�7�×�v�P�g<M�)���l�\�%�+�\W��*8��'��D��d��/x�D\�W�S�=�}��UR��a<၄N2�hP<�H�PSV�T�1�7�q ��@����0�pY���<���s�cx�n^a�����Rۛ?��Z�4�4�ip�z�r��*���
:��t_y�p��A
eĀ�h9�ˌ��f<Ǳ�`�lͩd1/��U�x�M �V�[e�d���6&Rz�t;��\5ӽ}|d󖳍����G}L�[6��6-���Ŷ�(?M8���'����%�F�q���^�`>!Q�M��E�	=y� �q�YN�
���OK�̗!Mi���vM�4�F]3�/Ce;N0�1����qd�؅X�As5��'�NEg��)BR�}p��^Q��,΃؝ʪajP�7؎<t�T}{����K���ǩG���.+x���������a�n� 9�v������sBBq�[�%Qp1�}^vgs�J�R�MY�,a���յZ.�~F	gd	���8"7�d�H�}W?��YCx�]��n����8K�2/���6��Y�Z�S�$�dE����nY2���Z�͠�xFC\�$~{���	�|��T��Q�Ǫ�w��#��遧.�Ue�r�";���ɼRA̐*hhx��8w/���G��Ӄ�_8����[7��3Ϳ{��Ԅ7ڕ%Z�!C�T�j�G���L�Vַ"��S�Y������I�BM%4;�x�lî��R���D��$M����Ic�"��o*d|4��.�xӌ3��j���X�Q�Ɖ�:��Z�� ��w�V����� ^�@(��k,�N����yGZ�Aj(�k�W⋨mqm�,�E���=�c\���Z(��,c���1�wu�ׅ�%����s4���0�\���1�#B5v2=P�k?����,���n�~4�2�m;�k�����i��0ɨ���	�b�?K���譃�G�F�es�Z(VOyl���� �m�!�%��6[# �y��(�<��ݯ����`�!���U��~��zgIjp�(�t5�=�&<��|�}c2�͑�?���cBT	��W2�*V�/v�I��8t�nŸ�<M��r��8AP|�D
��?�ZXX��a�D��n��X�5{�MkP��<O�1�e���AM�3 7К �G�Z��űn΋����4HҌ�9�ߘQ%(�@�fy��,%\Z��+�G��$?��T�֐�*�v�����ma;�@M�A���3A91�WU���t��O��Ϲ�T�;+8B���IiV�8�3����X��TB��\C�b3%J��"Q2I��d�_Y_ɛ:G���V�֍���?�b�"�C�.������lƄ�Tu5��H�oC�0���ΚZ��H�V��$��xFn�HF4�3����}'ɕo'%�e�D�`��bY��!k*��U躳q���G"@+٬:�:p�7�;�Y�,��{�����@������ŧ�?ڣ�OS�"�����AV?#wgS�Y��7e
Oq���{�]���sRB�v
���/(�4t����$s{M3��f�PJ�ו4sb�a"ׂ[.���Y���N?�}g�'<�D�I߲TP"�C���d�U}_�+���g��o'r�'e����b�=cW��,��������<b����˂�����ӆk��F�)mD�|����9C̣8������:�\���nI�z��e�'�7�lBH�n���8dڊ�����T
�G4�o�I�5s�C�ع<��WCӓ-�#������%��)��=�nC�R��=V(�/�ƽB��j/+A���Ԭ��)��ۘ
�GE�%{� &U��T�<�G����Lb5��KC��S9��Ej�s3��#��tR�c��(J�5��E�ɕ�t(gtO��]�z��/ɡ�A�o�Q��_�;��ۤ�e�s����d��|���=dt4gː���1�j(*q%XfC�?U�j�]x���0|9Do%[��U?U���ꭥ2W����n�u��3WSo'@Q��&N`�B��H�?��0�����Q�[ùV�i��M�'xD�S9g�Q���G%��MSe#�%O6
�ZX!��}mCAb^VAS�r�y�9�R`��U/��9O��%��`3~��?ݴ�r6J� �)8�#�[@��� _zO.�0����?���z�9��]��Rj��G�z�1���_fc�@��݋��p=�Y��Q?��b�R���|�{?-"����v��tn�SV��:��J}iA�}5.�1�9��n?<4�k�Y�lT�Ǫ����^�CS���o�o�q�n�k�HF��G�Y|��cC��(_�@}w���n�@����i�~�#�X��j�{��Mq����<�U��Z|��dN���`~��E �g���P�<F[<~7\I�JZ�5O"�1O�J����p)u�|��Ԥ9�N�e�����NX��_������,3�?a�0+��(�y�JX�׶!�ηڊ��$��ΐS@���[ˆ��ɋi�<I�n���.s�y��B&Gv_%�'%߱�5>[(�Y�y����y=�J��<�:�+�� ���x�֧jծ�\Bc��)�,�����Q7��4R���'9�]��c�29e�t�b�L���0�Ȝ�����w!���߫Gai�D��K��E<#S���2uW/(0RA�Y�4> 䧒��r5ٌ�:�y���^�� :"���&�'�K�(��ٱ�/<T��]�45���A[\�=�Q�-�<�\������p"������\B����Y9`_��B(�&��Yi����h�2-��L�y�Uk�}<k�����p�����誳y�K���<��7v��lMĄ(g&40*�x��q�5zPy���y�sp�����gq0|p�
��V���^M�'�S�y��Q��a_��Bx�_�f�J�u�L[���ݴ�:RY��z��o��ߝ�22
���O�����պ��x���<+�[8�,���d}�SZ�"�J��ʡ�Lr���t�-ϣyҞ=��lLF>3���,x[���ޜ���r�S���NXe_^K�� �b�<6>�[�߫�0�E����t�9�m̹>iL�R�_[ɛ��w���S�t�tC(��ÛL���X;{�r�!J��؈��.3����Bn���x�y^W}}DH��z�e�ug�C��Ͷ</��I1��`�_O7�XX�z�5�0��WH�焞i�,@���!I����bߔJV^pI�/��^��w�ː��2&�x#-(��{~�5h�$�k�6(hy�x��ͳ$��˄F��8'�s����]V��ȕ��4Z���uG����/�� �䴤N^�~<�A���.|D�bC5/���G����;F�zX�2b*[F���E|�_������-xݩnM�������������z�c�lѦ9�,��g�K�9	c�j��cl.�8�ҵk�o�
/��^��Nf��U��
��8�t(r���&Ɲ��W�Sg��V5G��$�po_N2�$�y�ua�L��    F6�z|����D^ӄ�� �����nh��86�:�/n%����&Ԗ�XEz�H��������������^hL	t�QhC��Ml�)�V�mq\�n%|b4�͙�yG�^f��֑���b
�黅����|�;nͪ$P��B,�����h&K�)%�N��2H����K3X����w�C��ש�����Y�;'�xn(+Q�;�Ǻ���3h�U��6@DE�s��	�~�%�����N��왛B�ɓس{��4�Y0�Ur
�7�M5�cZc�J"ߥ�!�w��K^�M�(+�I^���Ź�n�,F.�� V�b���!�(DE������	�x���.P0SV�oQ)�:skvF�i��xS�`���vb5Œ1bd(������A�c^�����\�͞D��R��	{S��j<�J��$.�0і�i�Jd��%�X�z���-PgFd�-USH9M����"�E����)8�ԏr�Ւ�0����
q��kz/G��zM�i�k�Q[�r!�Ԉ
�	���<��� �q-Lj������)�J7=V�iނЯR��zs:J�ҍ��.�,���f��I��_ţRu�zpR3����{_*�Z%ޞ��(�d�ք���aQұ~���M_���j��B���9��K3�.TMqU�ie�����Km�AI<�db���;���A:�eg�DRL���ƱNT������ѳ��
E�@�}<
����J��Q��"N��E�����`���7���
=�zzR����?��Kf;j��Zw����<*���t�oǪ����y�-�jo�U�)�2x�����Aa,4N�Ԭ=���b�D�U�$��c׮����.�	>V�,U� 	���j-߈`zF4�H8dА3H�)�lA���lkR3�S�o��&Yp&O���g�$Q����Ɉ<�m�2ݏ���}F�B��*�������$�4�\��A�T����+��Gbk #��F�����U��@��~��s�y9U�,��W����7�ReV��G�M���!X��3b�yEQ
n\�H�$�w�������#D��H��<Tp�*�=�	h�V)	{�"~@���LR�n��f���˕��M��o��k�G�v���6Ļ�g{�U�������x���Y����wm��T护GwO�62�Zk�H��
����-X�(���6p٫U'���:���Ns��r�e���0�gz�+�B����7��0�#�(m�"-%O��u���gU$4p��o��M��ɿ��������=I�$n_���GJƣ�A���t#�b�ͽ�!��o]g��[��E�����̔��$|J��,^��K-�Ъ�&�)��:�e$�L�%_dG�Yn�Q8^m�j$�������N��/���4�mCm���T��js�ߣ��v�s���/Y��Qi�%N�f����+��O]��n�lf����h�.���,@��Zj��5^y� g
��0���RP�w��5�b1���q��Q��"�M5_KYcs5-5�ȏ��$�Қ�{��h����)dE.E���*| �p��வ5R���k�)c�!�n�N��FQ�{&F�X86O�AB ������Z�c\�a���[N1GM���ajL꩐��*a�s0���Q멄8����S��h(�(�;�aa$%��)�/
@�dd��cQ��B�r��µz�q0�PI�t���YA��z�鳭�H����k��R�"��W��7.V�o^�{�*�U���W �r�U�������T���N]�H�t�����<2�]h�ߗ�Ԁ�:�?��6j�Ei� _�IC�M�qx�FAVw�>U��X/��֠"�%�g�L<��4ǕUwG)�N�s%��^�`�p���sZ�T�S}p�� ̱��a�03�̡����lLm*f>��)/R~���*t����/���@���S���N�N4�Ӱ���*	��/�<��ը$��~ʹ�/��#��DǝZ���(l��e�ux(�vQB�ц�P���Ǻ�}&|�\BW��("f���y��Y�?������kLl�1"/.#���D��O�ၰ#��PF��m���ӄ�1�Κ��e� 迋�bPI��WAMI7��>�J�G�+�t���#�2J!�����-;�3ͩ
Ke�!s���$f�ꦖg�(ǰ�6J^��"��F魖Q(�-v0�k���}$N���!��?�X�tQ)M6*J߷m}�ʫ3M(�Kݾ�uN�&J������o�:��|>ʥ��k)���)Ԗ�I�j������Й*喲=�u%Q����d?�*�>ش�sw��05�d٬�.gA~xy�rտ�8�T��=�w}׆ojѮǰ2�:]ҝ��i�-ËL�?2#�����A�)�Q�>t�ڰR�n2��0�	�-�h��<2�)I���=�f�=
\B��KΔ\�2^o�n�iD8�/���Z�������ۜz|J�%��9
uӺc=T�}c�p2�'��<1Q
k�8/��bɒ����I,s����]���ʩtk��
�~���"�ǃ���;"�WĠ�n%ϕL����O@GO�!��ޟe�	g��\T�¾%��[�K�͂Bf(�>�ĭR��1���#l��m�*7P#s)1�2f��JB0Y����o�m��m��H�Q������4֨�w��#��g�	�ML��q�єp��]�;&��f��"�q���P�37�2"ES<&³�"N���0�ֱJi���2Ε���_��bS��:f^�$�'����ù�j���<̗�ӗ�� ���A(l�nخW��}�6��$R���D�����2D��/�!��k��:6���  _���;�P��*�	,0�"���/,]z�(��؋��$VH�lN�	$h��XR�q��*�j?b ��Ǯ*RQ��2I�h���ڨ����8���8��Q&O�z-IꍇMi�f�%A/Q�������4��%Ep+ZM�t���9���Z���Hc8"�>vk��ߘY_��;6�0I~Z����J7�M�E�q���֍��T[�Ly������ ����&�?���.xwR�b�!�kI�EK��W��4���F���ʕ��wՍ#��Z5[��"���EBO*�,�_�+?���hM��	I�|#��}8�L�ȍ��1���2]�w� �Lvu�$�2U1ĕ��x3����ن�E�^�{�Ygy��N=$�;�������as��!�}x {k_]G�{�/�q=+^�`˽+��9U?��LK�^��U<!�_܏l�f��30d�樹�8�Α���FǗ��=�_��i,m��@[d���e�Ks����}-������9��)�|.���3x�ìK��n�m��Y�-����V�b�8E0�Җ�Q_����\Ro�j^�AJ�!�!|[d����3d�H����D0�T��o�!���pȂ5����k��95<�xT����Ľ2�R�0Uj�O�B�s��yL9�u�	�����q��j<"1���,��笔���4����<�2'��L����d�))�����y`��+s�W�`�*��/���Z��^÷�+�C�ҝE�F���DJ�8��@��*(S��%����kl�_��1�TPj��+�E�f����&�e�N�'�f���U_&�Es��Ǿ�FY�b.Ճ];F�Q�(�|�ő5d"�ٜ�ԧ-l�9�%����U�egQ������8�k��Z�̚HW�C�c7��9��i��0K��	��&�E��yf����M2�-��(�O1�`F���	QD`�,`�{j���%Ze�;�b�#O�aY��Z��Pr�����A��`;-ſ1Өı}��u�^'�)�3��D��^��At��cc��E�X���)�4�M���8�����HOE�%�]�p{��g�3x*7Hj�
n���?�8՜%8-��TEk�ޝ�������@���FT�J8�(�0���%�ZǳM*c���{���|����d8Z�6��� XL�WI�?�8� �u��i��.��,7w(�,�2d��}�[��    �h*��5b�|�CR9�APڌt��Ò�?A�I�XB�FOh�&, �Z�1�M����M�Y���V�Uf�8���ӄ�_$���ut�D�^z��
O��"�����Ki�sX��i��Ѫ�k��ڷp����\��ր���+ln2� �жgF�Y�NLDQ1=���57�SW6hɒ|R���A��֪_#v���~��� ����ͭ����^zOq`1��Gط�ԭ{�%�9ń1ai �RY5֖ ���P"K�D&{My���f�� 2t��h�`S!��h_��梨��fظn�z-�:YJ�2;8�C�a�P�X���)�JyI��H7�n��FըJ���G�a�C�n?�V�iR�ҵ\�2�L���N��<~=�I֦ ��m7�R5U�P�F%�h�14\��3�Jx�-NU�E2H�z�k�<���2Ă�q0�t��:0�7��Ҡǈ�h�������{ҳ�fifKs��$�����m�A�k���Kő
���@��j�H�]�D@z�bh)sH��S�T�f��'i��8DX�;�#�R�w�AOoikQ��\���D�Ӭ�}f��/��XC:��eL���pb�g�$(��Σ�Z�9f�\D򒝈N�a�,�k��r�\�Y�VȕF�\S�M�6����Y�tm�,4�ﬦsF��f��,QJ��Y%=���[|l
Ţ$R���8�����k�c�2:a��X�{�-#we��k���}`X�Э$ka4;�T@�����,�R8d�L%4�@��Tb8T+mN��nn�����^�"#M��"���25qU=���]}|bD1_1��+䘂����'�j�i��Fѹa� Dmn��'�����ڞ��e G����z.�R$�@ ��K�6JU^l����"e�T�/S�s�ZD�`B��?R�+@��+T��������K��8;)jou4��Ȩ�[��TNE`	e�ߪyZfR��<��³T�P��bY��&mG���qZv���(צ30kt�'B��aPCTvT����e��n�.]�G>�>��x8ʉ���P�j;p��0�eS�C�����WX� ���d��;�I�#pmt���R��]d,�]�X��h��t'�@v��%X�+�Pw�%${/M54&
o1-�K�Z���MX3oS߷k]^bs�EX���5��TN���o��綒|1�t�V���<���@nnf��H�]>�����i(�8,�k%�����E+��z�n �	b�;����KB ��'�eP�c9�v�Ϙ�MN ��s��6#��W�R��i߲M�)�iL�`��� J����ͨh�����0~Щ��ù�];"�W71G��-K�PSB��6�\E���E�ײ�\�ic�J7t*����5��v�O��FI�B�����A4�ە.?g�%v&/�k5��ת;�~?7n����� U�X_�o���'�Y���\�(J��Ƣ"B-�b&c|C�~�AL� I�z�p_YZ0��)�P�A>���Hty%{v��ﶎ�Ě"rÂ1\[��o��L�viF�`����i��1!��LX[,-JR�u�nO��	m����2�c�P��IkoTu~~���[!_*����C��z7�i�()��I���
�cC(��!v��u�Ą��=�דש;��~cb��
��,*�@�_�jaA�$�h�K��O.���e䊭-`P��(�<B��[�%�_3ר>b��x����~!j�|�OM����*���z:�k�5I>��9���+�i ��([��sz��d�����ٖ����2P�=Ty��:!��4�z���x�����
`�������T���~���jA����?�.p
)ff�����N����Ѱ�)V�����$\�F��E�|n�R2�uc�=�Y��~oJ�мbE�=C�G>vGDJ�����v� �u@H|t������)�O.��S�Jbe�it�
�FF)��[w��k4�ك�R\CX���V48qs���2�y%�땚�+!�';�T3������J�eu���ܴ��,5Ϭ.#��Fl�ZL������JJh�s��"��J"TfL��*,�fEz������u;6#����7��:	K����K˒�c3�yj��|q�|�0���z��J2�Ge���kZ0�����ªx�o��˃�ڧ�{6)��%"oJ�(t莇����f�2�V��X�� }�����9ٰs~��F	�ъu�983"��u�@-.B�$�
�	��E��\���	&"�\��S���L�n�K�����l�%,�%���fꁒ�C��xF��X�҂�+�� �i���TY�<!p�ZFs>`u��B��{US1�I���&4'�k۽�/R�L��p�f�$[à)X��~/�{۵�8��/}�O�j��~�4+@$ �y-<2Lgq��W����Ib�Po]������Ms�˟oĭ,���j_�P5����U���P�8��߇��|�q<�?��:�ۖ��6c`��ϟ���F��I���A��e��Ҏ���z�_�|Պ������,�8�N�L��zg��rB,?�ǯ�Jyp+&#B�H�Θ����-�7S�@��۳�8���7�Cل*�K���I��~�����R�je�=}̄���
�$�ִ�Y�h+zQ��ux��wbnN��遰Z�ԧ�,9����n)�D������R��|�����g��5��&�����k��	o�9F�����"�O�澆C��߰�,�X Ƣ,���,�M!�W������0B�(	�%��TBCaa�2��1�ձ��i��n[8�{M����O��#
>M,�F8�RB��4j��"|�K�F�6��
^��i�,Z�Τ���M]>!8+�� �0�n`>6�Jc�$O�M����#������i|�=��
q�p��QǗ������;�F����_�$B-�˗��G�϶�4����+M�2$G9���_X&d�>�?�x~Z�Ng<5߄Y�:���8i<��f����i	�m�~�����D�?�ȋ�����4K�u}�:ɐ�t�{��g��ҍ��F�e*��(���=w���b]�>�ћn����;�b���@���+�w�5�!��J��Q��f��QQ�\#Un\28�]�[�#!��[�[�e��*a�E䈘,,=�UprU��RY��j�4%\�ɀ(+����{�&�N	�`���`Y)����epO�v�ģ聁�'H=�{{�3'�rzz�Âw�a\p���Q7!GR NDe,,��~��p���Je������]w�ƃ���H�wf�.;x�Y:��0��/~3���~��v�/?'�2�	��(����OS[R򛦕*�Y0G��`�E�k���`D�D&̓��(~��<ٵ:�7fz��]����s�7��8P����wk%���7� ��ண��(@R�������p����֒����<����7�	�2	N���.SR������S��,��<J5��ܯD��U�;.ȴyfM�rw78��Th6�X��j�T��[Œ����Vd������ʎK��9���^�4ucg!�A�-S G�09�|�����m{R�j���`DFÇ���N��m]<l5N8%����K�����C�a���`܈���� b8��gP+�`�F�s�z���Gm�[|3�Ga��[�W��Jd@V�G(�!o2��ʬR��n�gD�(�*��i�����8O�w�kꆖd컧U����.�����E�/Cѥa?��s�½B
I�`���v����㼪�n�?� ����AXM7�l��w�
#��|�b��Ft�K���2�o��wm�|���V��L�%���8M���V+s�b��{H (�ce;��q�i=�b��+�z�!ʕ����u="[��(+_{�j���M1h�~��R~�GYpY�v>߅w8��δ��	p�b��r�z|-�A�����|�W�m��	��C�j�_�R�("a�Qi�p�f��n��~F~ozO�pѮD)�XDH�mpF�US?<�KV��    � �s�0�lGx���ROh58ڋ�bʗr��4���(M�a�Ƨ����.���g?u�e.2u.V�[�Xe�A>�<J)�h���DK�o���e�΋؉^�4�t��b���Li��qÊ�����gd͇�"�&�6a��T'��YMqFHϲ-�����q$?-\�3�f9�C�<BnM?j/;������c�2L����z��i�:_>�
	�^?��8������%�#��(0X#~�*�K�w��I�o�l���q�,q��JZ5�fW�U�4R��T<�t�'�]�����ɰ��Ӗ5�/-)�I��9G��z�m�A��i�e�t�������'��f�͢N^�x�}�{Z�yO�6��*xQ�36�0�d��	��:���k�C���\�I"b:%��1_&���Z�L����a�X���b�n��Ɋ�Hn�G�{�V���lobM/�7x\S�� Q�w����IY�8����W��a��C�A�
�,���8[���l:v�͏S��o�JN��+�;�c;M�Ϩ�+q`q�۰Ƚ_1�
��>���㠝�*cn���@7�b�i8�W�E+�0��<�(ۮY��ئv2�!�$��+�b3��%#�T�ēd�@w�,����:��Z͔!RS�@��5'��i�-!Dt|���C=��D����r^���V.��]�Z
<)٘�އ�'a.�9OG�l���!�MR릙]�ō�Y:�O�@�d�w���x�|��S|��]�ͤ�i�>�(��FE��-ȡ�c�u�W��G�ӥ����6�|<�W�F�0�2�����S`����}og���p'̎h9>X'�tҘ���1α�0Ӭ ���3&e�V�Ӆ%�/<̓7��e��_�Sm��0ܘ��2͇��i�"�"��^���u��@�t�N��WB�^��mu)y��G��rbtO��v3��˝�,O�υF[�4�F1�g�q� ɱvM�/S�r'<Sq�L:ŐY�;�;^~G�my��N��Yʳ\�����5JK�����ۡC���#���M�Jz�,�R5�\w�e��R�3��
��<�P���]q���4�N8�seŒŚd�>b���y`Rc��;5Ld��ͱ/�O���FQ��]�Py�%�n}����Cxۋ�Un�"K�<�v�)�Xݽ�wȏ�9�brU}X�f��;�2�(#�a7�~�ݙ��/'"��u��s%s�qn�6�V<��~:�
*�'�H�e�!����)�M�!d�X�	�-p��G�J�s����u+pW�c=#m,/ѥ�E^88�bR��nS��:�8���,Gq��T�,Q��}����#�E�o��[����?�J�y����Z�0"���+�.�pr�d�V@�Pm�Tl%��>~�j�UNL��j��"fih9��j��z\[-w|c[�I�C@�����Ux��]�7{Q�2	�7F>��f����0���W��c��-���>���ѳ�v��^�\��|���ԇ���+9��Ր�!^2��0�����}N�`��Q��z�U�;<���*f�D�h�
���£�-;fj�ܫ�Sӏ`�d-i6H�}�Q���@����7[�ɶ��Q/e�֙u 0��)j%Q)U�2PD q1�_���E��zo�����CZ�'p߾�5�WOJ�<��qX�~����;��Ԣ�(���(d��-F�1��!����(".�O��Y4� �p��\B���'��'"����>��9��ݳpN6F�����S�tB#�ѱ;�<�?1	+��c���9����YOyDav��>7ũg�A�\�?0�ݚf��6	lOӈ�;�%MST�߽G����t�x�'
�5��p��?�}�CG	���%$�HU��2���ifw����7��%ǳ�V+�V3�Ȍ��N�L#U�0>�G���;߰�$��22s�Y����i�b}������%9��װ�~�fw��I׉���)�x�eI�7o��c�
°-���3�x�j�.t1�T�E2u�I�3; l��wz�A�9���@���L+ � ˡjv
��39T�$5J^oo���:���pA�!1�$ܐ��CW�wp\���gvm�Ûח!�Ĝ�KTɫ��!EG���	�l���m.�X�\��&���o�%���Y�|�;c���S��L�8c��A]\�ޭ[  �q=��7㠥��y%1�,~��ĘH.����XW��8p&�H��� 3�d��N��ܿ��Z`�E��9+T'��dj=7Sv�2i!p3�C;y���P~r7{>N"�8��\��K(O��[����� ay7���Xt�Y�z���74�����`��I}����YrY�K�� c�r�s�|'�ifZ�+�!�⦏���Ia>և;o��b%	$b%�p��Pl��wp�M;?O�B6�VR��	ϓ�u���Itw�y�;�������y��""f����v�mfHT11��B~R�dD�ᥓ|�<���i=�:���y���7��*��_��'c9������tY�$���,��#���*�[ �<��H�q�r}7�0���"�M���~`���<�|"C �b�L+�N}{�#��{=n�9��qbUV�q����i�9g��'n�Fq;Ͻ&�(���Ҋ�"����~kǳa�0��H�"V<ص:;�U�\�u�a�l��*Q���������4�O���8�SB���_�$�n��\�����H{�̒�T�h�z8��}Xd�,��kr	�rs8 ��[f���"(4.ͼu�Z�C�a��9[KB�YF@��(&��cg�M_�ԃ��R&����u��4!g+VX��o�4�S_�� Ic .�,ߵ�:�3�hY�����f{A'�ƞ�`���d�oU��m.�Sk|���y`j���Ա�uH��5�z����U��yd�č?�k�N�=RIh��PD�9SN�
��g8���@ɦG_���5������r#�!4��f�� ���M��Ӡ2�����R�2���Ft��t������#���[��Va�"y�����^�cj�ܨ�6�N�er��Ϙ�`f��i�"F���"J�W�_7O:�k:����U�E�k��ċ4y�{{�|�-��	ԋi�Q�d�@�;�����ސ�#��2@��Lީ���,m�n�����q�)nG1B5�E����m_?�,%��xfͶ���P�Ⱄ4i�y��4���,�~���6r�")Z���8��/:WJ��C�{�Β��5Q�8*��7~��41�^@�7�T��kk�m�iMק��p ��cȫN/6���i�k�ۻͯ�Oc��ͮ��+|�%�����Ȓ+HO;O��@��iO��'!����jI�	�D�x�!yĦH7�zl-�5okb�"y�ݻΐ�1�`R������g�i����J��\#{��y��U���FY�J�0<̽�vA�Y�Y$�e���(��F�[�$�<�v�K-[לu�[�5}�hu\����랄'ƺ�D��
��s�p�,�6�m6R��	�9���/<j\I~��ׂ��~�*���$^��/4���j3�����Ug2Hc����(���Y���$�7�Iˍ��?��|PMi�gjn����ۿ�|�c��4�VCnK����"��TQ� ���>[����w�Mҗ�g���g5[
�fXwT˺���-���ϺnŤq�US�{�Ʒ"ER�8�����jQ�&q����
�τ��Vv��Τ���)�.�HړHY�~R����=&}�M*X0&S�rZ�	�սGs^J$�$D]�8�>&��Qӫ��FB�H%��A	�Ey��wߪ� ��c-B����a�|�sB!������H�U��(�m��%�<Ԑ�|""��L^�����ri%@I��ID�H5^T%�oG��فy'�����a��qޠ�+���s��O��SdN���l>����}Q�Uw)�~x3��TO���8t�gL#7��x��o�Y	�����l�5z��Hv"2��
*��m��c�,��(2۽v}F��b�G����0��G(׸C��1�b�� ag��.k΍'o'��OD�G������	/�    �ϭ��g�"H}:����p���n&��Bmg�D�G�4y=6�k�[@�le��>�2�����%�Ȫы'.ƒo��������a4��H	�Jl�v?�g;��	��z�f�`BY$������Ȃ`R�<W�n�YXF��Hw�<㊛�V;�Xd޷@���aQ���\�(Z<#�(wn�"k�v�g���0z��Lx�S���P���[�*Jf=���*�G̔v��qDTXy	������d����p��*%����Wp������B�h
����ȠJ|�X���nWN�6���QY(�dFwĮ�"��68�:�~�iq�j�Y��}m��?.o��-����zl�=��+#�w���� �~����y�Mw��$�#���Cq���ڟ�Jdd+x��D��7�j
/Ч�W�x���Ýb����g��C(�(b�X������R&�.{��!SHP�!��j]^�?n��]Gb=:��d"�	�qC:��
�~�=���L#h�U���w��0<�ϲB��g����wQ`WlfW8)��_��!Q����J��kKh�aD��y;�bTd�G�<�2=�����V�r�َ/�$*�(�#��w3�>3f	+�^�%�n+��鵽^��	�ԉ)�Q%�g��k�U�d�v;�~�D� ���vhw�.#�<,2Á�as	e��)��G��ȤRBa9G���*��8�p��+���|�%2FXH��.!w�m�#[�w��(���� ,a]��a��s:��<y��6���G<)P��kcO��!A��#�H�r,iaIJ��R�[������M�8���M����+z���ס��t���I�<�mEU���d��ِA�9������_C���:'�c��""��Cp�]+"�-���P�MD�"���U\�!������2�i�q�;��\D��"��5�yt�iq�s9�ϳD柍 �$��d6�tp��ۯG�Z/K,+86��?�~�5��mFPX,�̱����	>�d���|ן�΃!"W�P�om����s�T?4 7����(��ۧ�>���A�/b�"K��[[ 	;6ތA�72��"
�K�up$��(�ed&�j��P�^���k���3�j���)�aQ|�x�X���+�"j��L!��Y���xfB�(�A���e��:�3���Hz�(
��<����r3�y�"¡-�X?@a�/�q0��gF��P������� �EB���"�������hI�Q[���c����Q6�rO��15tQ2-�r�x�goЗ ��Gϣ��A+��ƪ-�yY�
u��"��Ǘ��4�2_�2��[.%F�Fw�oQ���I{(�ZF����������¥4jl<+�"�0�\��B���VL�k����#�I�9�eԘig�v��Fb�EY�d��X�di�8uX+������p���/6��mW{��202H?{���Aרx�7��0J�E��U,y�pJ��k���8}���]~��Ng��<��H�@��"���v%�2!���|*�t��$�����~�r����m}<6�/r���rTLTyR�iOE��W�Vo���W���vVַ3�Uc�G8�*�����B�:않�Rd���w���\g��o4���+�J1�.�[�9�!�|�g���	�� e�%�S�4������53��L�2ḙڃVLM��,�vz%#S�(��p����Z���2��H��7�����"i�^Q�W��
ҤОD�'q$��0~��vҼ8K杧$dJO��2����g%!�ln�A@��dZظ���K�JZ��-J�$�l�����٨� ���&��� H��V���W���Hb&�(3�b���~6I ^�s�2�-�1[�me�%�u��@ ���@��@#�+_@	���J�>�&�"+,J]%�Ȗ~i���ԻV%�k	���6h&�ם?���\�I&�2����b���׺�,(��lGfy�*���Ϋqz�0G)Q@�4�̊�,����&�
�2����ִ��L��`P4�Y�6�{�F��(�W�B妽:.d�Ǯݺl�4Z)���g(,���ѝ��k)�2��KnT/��HÁ|Qۗ���?���\3x���J+�z�_7�~_�}�.I2HLZ-&^����JNd��MƔ �����EY�%�7JT'���%b��+�Z�3k8@�S���,�crVӱ*v]�� j��8�<s�s�x"�zB�g��苛gA��l|K�%o��I_��?F��,� R��V�����:�,���=?�6����a,�l2��}L�.��M��]d���ΠL:`W���4y$ԈN5�ʒ\&��DU�7�-ly�X4᜘���G5H[q��+����&�	xq��<N'�n%�I�/y���#m�hU��?˩[�
�N��;*��MD��̳�R'h�E�4��ۨ]�EWN�R~C�+����i�����M�������"��`�eu�f5����|E_M��v���zxi��"�0U�ph}B�$�zM�k�5�|�B��+�^#+�������f��TaȝExi�-Ԯ/���U�LVb\s)ТV�u�6d����?��j�@d�_"ݱ=vx�Qq��yXk�:���D����`iաէV݇�M�,Q����f���3��3c�B�`��Y<���g��&�kJCt4�?�m���Ԡ�C�~)P�t��O��,CȪ�դޏD��vP�~#~���J�l�|���p��;12��"����h����h�)�sA�j��撽�CZ�Q���HiTLߣ׌7� Z��@��Ry
	a����3���{��=F����vhk�y?��i�~mp���<S��}P�p�����y�yh>�����A*��9�0�+�I�K����|�KF�"��e.�����z��P��Y����%��h9W�B#Fg�9�X9]���dRJ�1�jZ�6A�}�+�t<�I=v^e�1����~r�M���<r��5�D������h�M�������l c���ʈ����;����<�@H�R��a���p1�¼��|�gwb��u��"B�I�脳k������GQ������v8�fG��jh�N,��BgK��gbċ�~H���p~4k���hÂ"�r��6�鴹���!���1�Y`oc�9��3��Y�� �^\���P7�zq�(�i���ʕ)��L�s����!6g�f�7F�Xo���0�F�mEWe|i�˒�����^���Ŀl�F�/x��R��%ճ��Ŋ���<"���4T��	࿦];���$��2�0��H�	���L�7��O�f{�Z���1�%�����Γ�I�" �h\Q[�,����������9��ʣ��

���:=֋Lg-�m�(��WZ��n4C&�|�b�4=�� Q�ܶ*��ޞ��0kQ
�L%�U���><,#H�1�X�Y��pϿ;m^����2JI�5e,˩�� �w�������͒�s�6q5{c�΂J�(��k����P�4��3��P����h��J�mVS�g�As�Թ�U����#�N�ۖ'�Q�c�z �"A�q:���S?J`A���
I���vt�DK:�tC���P�U%���WkUl�>�"���t[�oC�_ H�����v	nu�bip���M��n�1T�>�u������N�)Kcm4n��ag��y��C��<�h��kg���l[�r�S����i\�o�&���_�t42"��9��8�l`��َ�y�7�������{����@=A�R�������6v�hЌy8F�:���)���R�4��N'��uE�{.7cKD��xZ��rF����B�^�}yڜR��"��-6�Z��(�(K������A���e��m(�H��92*�4P�r���H�>c2��S��7/���I�V���p�9as�5?�~}��j�f������<�߻#���%��dr����:�9�. D$�"�r3y�3���ip�%�y-�B$�%ϊ�b���f����̳21� ?��DcD��FF8{�^~j���P鬴�zA�qH������    k^9�vbI���P�,Kn���.�g3n��7������{���Ѥ��d�B."�v������$����m�v�?�+�f�I�O�L$�C�<[_7h	�^s6�!r&�?`I$]�[jY�F^Z�Z�O���3�*1���w{��t���]�<)"���;Uh�X�D��L�U���a���`h	��k.�r1���)i���GSc�N�@�iE�3f�;��L��%;?��n0�T�r~E����UD˂���6�u�������p;A�ǂ@@���H�T򒛋�`��_� P��.Hژ��$z9Ǥ����al>�I��ђFԣr�'7����1��7#bb���E�J���-"`_�GlP��g�귵��M_����2�[_�u.�m`���ZԾ��D�>z��4�6��ER.�zE�~�a��8�*9���P�E���j\5h��}�wQpB �G<�se���~A�#�ًa���?=��@�&�5�r�D��|p~zYP�gd0G�׺E�7�w3�\G�^s!С��/�ñ����XD�m�P�G8sDǅ�4I������x����/�ㆶ�.�^Z��׫X^*���qp/����Ge��羅C�[ʑ`���wE�}2M �Q���ͫk�
�3��e�|���o[�̈�Ŷ�4�#�>d0��n q:$�+�3J��5��;)� ��))���Mq�tu�PZ���ZEX7��Ny�r���E���*�o:�ƍr3U���J^���;��˃�a4��D�Er��*{���}��z�m���\���/Y����1�4�rY%�Mw�_]�SHbV#cM���M��hg
_�O��2��Wl���3o��~���r%�p�F�C�>�������};6�����GT3�'�/3�i瑫�Q�#I	�<G"T_�����?0w*#2r9��BB�ތIr *K�PF
�Ew���q�"i�.����&D[��v\N�)�\�T�6�qQ>�߇���R{x;wϿ^A"���<��o}�Ԉ����A�Z�"��J�gW��>��w�?� �&y�%�����J��rx���I����`Hr_��=�}�t��fd��b"/x�izl}^O��~j�՛��x���yg����gO���O�]��)r}����[����\/����F���B��40���*��ݦE�V�SL�-/r-8�0~�=/���A^��i����[<8KF����>/���~��k�jJl�4��+�<��|F�y�f�x|iv�ٶg�?v�X��,�X��vԷ؛	�΅7a5��4��2ï������b�>�L�X�Q����
]X�k֫��t}RB��4��\���qJ��X=Q
�:�^u�fRylϗF\�A?�4\^Q+����6�,�+��w�y?=�g���ƴyY({�]S�k���}̵,&������k����/z���H�\N;8�m��ERY�C��j���l�#�p������0��u�j E�*�Wa��u+���rM�澳83(�8\��x_o]���u�}��Gt�J��KIU��;x�z��h�V2�T�{r�g!Rƈ���&U��k�=��	�"�M�+�ߌF+����I\)���Rn؝
���U׌�s�V��	�H��U5����n!N�	y�CY��_Um��%��A��ќ��S��FUF�.���A�E�9�Pw���iR��H�g	�B^N��)��B�	,R�\6�������� �I*S�����������$��"�u��V3N嚷�W�[�EZ$�ը��_޽[4�n�^�/EZ&����F��`��`���EZY[�g�c�û�9�����=�N��
e�u�"$�"˒�}�����B�!��DM]��)}X�B=Et��}A�*�|�!��F���h�͒��}c������
�����L�����o�sBw�G��L�̫�X��S�26����@�A�3�u�,*#9r�r��X�e��ӔdYU�k���3)\d(�@%5�[�V�gq����*�X���$9Q.X�\a2�yݵ�G��#
q��`&����R,����Q���tެt����#4��C�(�9f ��t�A[15�1�#��ck���E^��b�+�e���i��♈t�f����g�&Rũ���b�#��˓w['�sG��4�M߂ar�q8k_�E�1%84�/G�m�ːh�-1�WYH��Y#ٶRB!{~?!í�����>X`��'�ZW\��콇�&|u4��z#Z�����!T�H#������;xV�0�\p��}���W��˛�ڋ(T!"U�.�W�8|[�'�k� 
���ݽ2]vĄ?��H]���K�ۭ1�������pt�cq��~����~Q��27`�	mYF꺂�F�����mT&y���;��t���Qc��W�j���U��Q�[t�2���T"�"�*
�ty9����K�`S�+�ˤ���l<t�+#]�?XY�����L�T1�42>*WX�a�T�V�}V�$�i�t�nL��<�R���'م��u�{{@��������pn�ԋB�æV��z�Q���#�lYDF�ڂ���-q���@Q"�b|��{��f�߲ �i�)����(��5�ϧ�/[��*�����gCp�����ɶN!����n]c�,����T�(���T�v��)��v)�ϒFt
ɕ��q�Л��������wd$1������D����g����~>�M����8�ө��% q�_?j.�<�"}�"����x�rz��WI�*d���w(�{Sw�v�:�F�G=a
��P��N����Va�ذwZ�����hwP0��1'Җ<�RT䙒���G�u#�
C};Կ��1]!'������0t��.0���o*�0*�_�Z��,2���"�"�X=7�lt
Εحyn�V�N�ڛ�Jͤ{�Db��m��yw޼;�H6ZLk�G1!)���"�M�48�|��s�����}I@�e,���N�:)����S�QT�M,�F�sX��#�N|�������rm������G�^�l��кo�������z��9���}m��p���/
T�T���	���k�R�vR�����+�q�����&
%kC�Z8z�QB���p�z(Bo�Q�lъQ��]�U@����+]��m�_�y����瓗N�y��RC�-SV��ջ`�n���k���PA���[/7��O��'d��O?g#��M�"��f�p	9C��O2Ҷ�(m�1���ֲ7�D$��<y7=Ļ�uj�Y4F��e��oq*�E!��L�������r�y�Z ���C3�%�ǶnOC�KmS��Mu5G��H>[�q���8=y&�I鑤�u�o�36p�f�n�|�Ѩ:�\�U��j8����Հ�Z3��Sj�Uir3@ڱ�Dh�{�rm����Z_n������O�0�T�(*���{���Qh�m@�f�R!Ā�P�-6;�U+����3��GF<ȷ#<u�O�Cs�xvTh��$RQ!�a8w�^J�������U� �v�Ϯ��m�ы�;n^+���:�-s�h�V��;��8�����j6�a�\�;#�6z�Ǽ�y��!��g��/V��4�J	�����S^�c[B���z/+	3�2#(�,��0��X��!��K#�K�2#���C�����
' H����e�F%�j�����Y�`_�%��]!_���d�k��Ǉ����/>&!UKE�eS���L�#�8�Ԭ��\G��e�b���7����̢��Qm�2-��~ƭ�e¦����{�H�+Sm/��=,��`�?�s�䠷L+4�P72�oq
= RΡ�un�jH�o�A�oǺ�׺S�[LRmhj�g��z�j�]7[���B�z�'fli=f,^wf2����Z�"���Fyր� /����qj�<i<�݈U;}P|�6ܶ�"��$��2C���Nc0�
���-��RB���=�Y�ha�N�V��:8�*�eV��m���j5�Uh�M{���LjէXp��C�$�LV���_Uj����
����e���jm�    e��F\�J���e&�:���@QF�H�Q:�����2�i��zt�AkZ-��Y$�+�{^=�\�z��Q�}�k���v�z�Y8�xgj�0ad�
��uc?��K&�[8BҤr1H�����(KT��+Y����Z�)d&����˙���,X���>�Q����׀q��Ԯ���\N�<��«sa5���3��p��W��5��/��ɿ�Bm�4� +y�����4��o%���`�1�2P�/|�+����lu7���G�JΑ�b����~ty����42���7vq_�&w��`�����j�]��ҏv��{���B]6V���/J�#��Vw��G~������Q��*b�!G���d���iDvTK��������*=���>[ɫ�[ݷ�g���TZAn�R��ar7�2�q�L����k&���h�/�"5�?��FnC��<Rې�9�-5�U�a\;`�%�6N�8�fz	Iй޼���d�'��	�n$���t�Gc�%3x��S���-�E	t���+U�"ҝ*�c����%�����^�OF�0��=ԝ=��Ds�D�QY{����~�*�^�q�k䮢��fV���� HF���̠��8`՝���O�|��L�?��l�@��Q�k(�8��k<`��&Ҙ�o)��x����,BO0�"$�R��ɴm�Qw���8�޴C�d�zMc��̭�����BX3/��'e�|k���k�� @C��z�#�e�q�++��Z��*��^�Hץc�V�*Q�"<l5T��*�{�ֽ��ו�V:�e&9�p�ҥ�����G�*z/���gMŀ-�]L4kV����I�5K>3 }w�,E����g�e���78;�����,�t:�H1����S=���[eby�?Q�2y?��f�Opr񼵭&﹈�G.)9�X�h��CN�f���4O�n�V����)�ݖF�����o���{�>�wM�5�����a������p�D��0yW��Y��X�H�������~>45�q#��bóH�l�"CեN�����x%]	/i,!/Xr5�T�:��e�asnu�T��P��4��OH�G˅�~j�]�7E����`�����V�' �X�S�d�%��x`֦�D�Q�l�L�o>M��OI(�Ħ"%J�gu޾��FԮ,2�,T��m��Ԓ@薱����K6A@C�y@a��觻�����T谉 �ѓ(�"Y��R9k���m�4hE��òd��е�����mA�Ĉ�eɓ���5~i���ّih`H��R$��v_7����a�&�hI?��4�,j:�M��Go�T4`��!�y�ʦ,��B�
�E3�Kw����%NY:���4�c|�6���2.�R]�$aB6�T*k "`Y%�ႸWM�d�R7�ud+�醇P��}�7E+B4���$����������X�(����aOaw����=l�f�M�lK��A0�HGw�M��;#l:	���K	i2�zZ�Kw|����॒�{�݇���$�*O���J����Ǯ[f1ri�_�S��h7��;0���Ej�2�x���;���R%��T�PPU����߆s���^FZGU���C�)��u;;�3�_wc���-��ǾB
{�v�v-�c=�m^��P��T��D��I&MeX��M� 2f�ܶ1��R�
��2���=l���j���k�{��K�F��?#{KU*���HO����Ea�2�s��!)��RJ��b�&!��5Vi��u�=�4�z�C�z�0>�wy�Z�8Vi�!'l�n-�8�q���Cx��'Xݵe�.�n�J��f�N���C�*�l!�z�B�[�{޼m�{�bj�@V(���x�Y�D���%��mY�i���Q�9��[���c}�����Q��x�1�'�ȓY.���(��2���V��?O��Aø��)x�I��WQ�d�����3vU!�r����~�����$���Ϡ�
���4j��e�p��GȩU�	���q�������3���g��<�`
#C�"$`B��ƻ�v� ڲ�x���
G�5'|�@���3q]U(Z�ۓ�˰c#U�����*+�iVq�(<;f���1%�2I]����9m�~7����kE��bǖÂu�	e[a�Tfp��TCoYs�x��؊���8�ֳyל�����}�*x��
�5d�f#���3D��#Ȝ���"٘�����<�7a�*�Y��a �g��t3Bڴ=��y��t�yS���#Df����y9}uYxGYD���\����(�_�7eX�E��XV�c�0 =IhQť�Ӊ�G%�#�j��`���|�3��3�����L�B
�0<4χڣ�H�&#�Ȋ������y�p��IE�W���x��>�"�m�HS�)��\�,	t��(�T"K^ۭ������
��R	��6��M.��ۺ�i]vJ2�K�DT�)[?6�4O�]ȶHl)����2��_Y*�8!6�TVN�"���Pp���YI#N�-��7〸~��?S��bR���l ����3wy�N���Ͷk�n�Ŷ�(�[�
b��C)w�d%���x����B՟E��Oڶ��uVG:bS�^���џ6��ב�� ;��(	�t}gڪ�74��H��R4���@�r�n�kAs���T0�к
���5��i�� �$�E�(�n^�#�3+t�o5]��Y%!����O��̲��,�y �@*�C\8��Ur-C3��_(��g�6�r�")Q�R�L����w������
M*�����"{�J��@���������+=�Yȇ��X�!���GY������_7�C=Z��1O^%�����%F��w=����+3���y���▉ߑv]�"�Us��qcB$��ʥ�a޼nwM׆��@l�l�Vy�|��w:����ڻ�$��b#�*/�Wύ�-�8����o�7���x��іE}=�2�\�Y����һ�J^��Q�oO�IY-����8`7��*�BI�UE� )���j�{���_FJ�@r��b�0r�X�q��9%NL��jO�[����8�UGI�-�#��	YQ�(Ħ.0�~�C�S�[�E�l�7+�<��&�`S?L�|#%hTi�UJU��z��H��j:�.PQ ���y�3/�X��y�5P���L�?��ߌ���Y�c���$�՚ϊs�>��"��T^�V�����nN�Y���JM����S���I�Tș��/}W�w1O���8C��׳����W]:�tT�H>5�W)dy(�l�ʈ������X#���V&-#�����dp��� �Y�jc�Ersz���%��uWO�]�(�L�ķ>���ν(��q��~D	Q�ߩ`kf���/G���9H�4���֛/�o�X�NL`J=w��S��w�t�˿���Y�?R�3��y_?=z�kN�����p�x@Q�v�z6�%A�� V�H�4�C�����k�Q��Z��4���լH�Y}�"֘�r����g��:xې�y������а_�B!�;#�|�ӧ��	�̕|�2y�4�������*Z{�\M�w�zZU���X�F�i�\d��É�hɇ�ؼ�6o'�j�s�q��#왷�뗍���#2=����Z�6�L}D󷠅ʰS���|3�O�"
z���P������RQ3�0@c�+���v�5�a3���pܬP�����zZ�0��4Q�R����_'f��I}�2yY�sݵ�zL)�.����N�����8��vߴھ}�l2B}D����!����{�Z�3�:��#fc��x@h���!��b�T�ZS�?��t3�v8��P��tb�<p��ͪ�֞���d�WF����}&�v�\>�N~�]r�"���Ley��UG~���j���p^U��X�H.��C�g�G]�j�k!���gF��5 �˰+���=Rf��h`-ݧ�ިz}Ɠ�j��9��)���t�΍��g���d��0c�;��OF�kO#�UX�-�|����8k Y�3K���2��;�    ���Z,�AóN��^rJ� ^�?7}֙L.k�[�IW�܏�D�I�V�����m�y�Xn �n�Q��a�ЦĮ�Y�آ/`���HW�j9�
er�l��f��g#3�S�t�	d�����[yl�D�?x:�ay�#>�x
�u��.pI��1����%߱I�i�
�.�)�5�Y��u��K|F��-$N�uM�w`4)�.���qm���}����Z�vP��]�����:R�ʻa?���gX��}Ew�`!ȯ�c3��wmsz�κ5�p��%Q>[T>�{M�X"׸Xf���C��E����!�`��A,�@A3�a�
'n�aU`ۦ�o8����itF���'l���ףm�f�	��yEW�L�NE���n�N�6`�g�~,����L7b~M�m����[��30i��V�b�Ğ"���_�Эo���T�K��vߜ1�k�����DԷʱ;�iV9#f��T�R�
%��Hհ�h��׶`�K�^`�21F���V����-:�l��Jp�X$PAe�@�XK����]}��c!�)�*+d�e;��z�1 ���ޓ݂0o���&7�/�'�tF�=*X�'h{���M�u-J��Z�N�!1����s��j]2���k�
��Ii��ڛT�.\�.����G��d}��n����u�Hk�7�Z8�ՊdVv�z��^����,{ݏ����ҢJ(ͯ_ä��(hX�(���q8�����ի���]�X�
���m7w/&~�O�gɫ�5AE7��a���"˦/QY�C��M�v���o�;��7�ZY3��V�4�������m�/�d��_�l�މo�7������H���H��]��̼X��ZA���k\[&nz*Om��1���������(� ,�,XB���k�b�;Cn��}Z��Xk(�[׎gH�A�&/�.f���j���r�\=wh�0<�P���~>���l|�P5[���f�z��r��T^FcV`CSl���)h��k\��`��a�E����BR6%�kHS�u7N�%>M㨱�1�)��PH+��ˎ�.���R#$Y�3ڢH�	'��ø�ٓ�v�2�����-& ���$�r4���Y+*(!���e������R30|=@�|3b���Q(���wciM�Q�{��ִ7+'bx�� +1�wj��{T���_|� c� =`M��xN�b�}�~4u0]Ϗ��������B�~m0Q^�&b���4� 3J3�O�`����E���������پ�\9�}��*�B��5�j=����._;fwv�|�$\ҩPY��������iӵq��3j@��
�����|=�W+Kf߂�垾Z�,�u��֓��8��^UУ����w]���ixlp+�������]"W��-�k,��-��hl��ήD�=�v}�R��Q=����/���	==�[��v�	�t�DڸR YX�8���Z7ܹ��H����R�?���'��-���*H��� z��䥕��<���F��QUf��3��~Q��;نr�����6�ý���W�\H
9Kd�Ǧ>: ����!҈��({�%�7_�~�Np{�"'%����;�|��U�ɨ�ލ�y��"KE��O��-#�a[�$ViX'��a��3CaM�ח5�$��s��؁�i����a�E6j��H.v���o��SW��\&�p�3+�9�75�q
�J�,��b����Ѻ����,�bϲ4A�H:>�V�B��ߚ�/j��������I�"�d��sߊH��Ƃ����~7�g��P��	�ʌ"�u}��� ���"v��	�}p��2D(�%�΅���0����S�c�!6o�lxx;��� J������y�c���j�&?�ԏ��ٟ�塌����0��K��,��ˢ����߽3J�j}j �q��R#n'�>3s�W��=��ࡅG�2�\I�%$���5����u�5K�-+�J?S�<��^�=���[O��8��j�j,���Z�B[��?��de�1� զO���j�[t�>���Ut*��#�˃u5kLI��=���#3����bBa����Ԡ��^�qcÁ0H��O=:~Ax���|Ɣn	�z^�v9T�����n����L-'��y�m��<";�e؍8�Eh��=���dL�e�3�\><��0h��͆�ko�}�PѶ�Y�H�\k�[��*bW7O=������ɛ�sB_�G�ϒ7�	���1p�vZ��ъɰ
�m�PM��a�nkG�b�Uƺ �'�qw��:n�/<������f���v<O��p5���y�BО;�B�aX�}}:X�)Kqa�I
��2���/������M��pNc�a	������pJ�)���	^a�eE��*R(g��e�� z�4�V���5Tip�o,`��id<��4�|wBx��jP'������U ]&2��2���lƽ�\Ҏ����.Bo���=C���ĬG�G>��ڣQ�f���M)�f�s�Nܱe��;F�fb�	᫘MʝUf��KiX"On� ��=`��'|��(�z�"y���0��#%��4�p$��I�
�ft6#� H~*��!Ϫ����鵟"��L�T�Kn�k0��H�yd��$,���x�ڏ��O\e����$���@���1t��B��I�|����\q��E�1�#GPi�p��ɩBí�������r"Ί�����ɫ��'(�Tf"u����؎<�Q�
��-4���Pߢh逶!o��۟�hK�H�6����y;nr)�X��:����L�N �m燐�rNA�9E,��Ӥ���!l=ӭ<4�/�H�)˳DOANhn��8k}�2�ĲyP�Ξ��$��R�ӰG>�*F���vo��	��3��Y�V�5@b�\(����u������J����h�P;�Z���:\��r�% ը]�i��k����).��"�nw��g�m`�1r)�*�ɕ}��No��.N�\�2?�$`��ww^C+���г��c�*$Jf7r�,�ڨ�YdF�]���z�a�\pF+��:̓�֗�cl
�іH�5}��v:nN\��h�]-,�f~3�]��P�����u{:��b�d��p�"9ig�d����y��2��Ӧ�T�*J��v�w��BFQׁ5*�ܹ}_�:C��B�2�"8�.������ApGƠ�Y�%� �A������IY���ss����!�����i8��!T��C=4�P�p��~�]~��-ϛn��	J
O1KJ���рU��~>��|� |��
*en������=;g��Ѕ�h*�-�Ck��dz��2��Lph�.4;��S�e�Ĳa�����d0X5A�H��4y���N��LQOV���|����}��PR��
�s�k�4Y��)QpQ�Ȭ6�8�U�xo�'.҅�e�W(���Mӻ�QqmxG%��L�`��\��(]�q5�:k��̪��b��P�gц	A"Ni��j%��#T-[/T.xЗ'�W
�*e����}}<�]���U��%"U��y�����+�yE1dH~���V��ya����R�Ī�@��"��M���-[��U��,�-�vv^jƣ�/a]�iuǷ��ch|v<��gy�*c�L���c�?��O/�Z��
*��5��@6�G�f����Uϛ��N�����������G�]_�S��3��T�l7F��30�#�'��jj�C�۟Ef�,Ka/ݶ�W�n>�:�
�0{ �����>gk�U$�����8jH��O�L�/��;�!W>a�xXo�)w�Vbfz�|ǵ��a�>	"ɶ�Ω�YװPޗ��0�lb��{�5��t���a�	�noRω���[�ctUNpT
�@S�{󈊘 T��	����4�m�����Ut�h&AV�3bl�[�������)�MS�%o��n�.r�r�XW�k_�A[Q��GP�QJ�c�,v���S,s�7*��J����a_���Ǳ=y"9�:�G(`�t��u�TۓG�hΑ    k�x�e������eA���1L$�N��_�	��x���3�sj����\$��:m��u盺�
R�O2�)���t����d-	��X9¬���<�ٰӪ��5�N6,�S�%�`�u��Y���X�o�xx}�ߌ��w���:m��eAཊH!�8le������k;W�d�xu�Z������y�7Ϻ���HP0��A�U�[h�rީ�{=X�%�ؿ���u��5�������ms��T�m�V�Iq��� g�w��n�3�m>b�<��ozM��\7gl7u��i� W3�*����[3�ڭ|�M�ev>��R?��vT�zN�-��I#�-��"���8�ub�1�9lcB��.�s{Zh���-����,��n=uيh@T�z�	��0�[�k���?c��/.,�a�y]�N�v4�������й����@rz��l�s�k$>�{��G��(AXJZ �Y��]����=yKFܽ,��a"On�����{���	9��b�0��7�3�l8ً�I�(�m��K1&��:6�cF�=m��dk[�y���4y?4�nդ�yy}� �P�̔*n�zk=��X�f�BG2�m^O����"���I����,e'�u?����R������%�pBY�r�ۦz��i���;&%)❱uɛǢ��4"WW�
�C������h�0������u�"���9�e� q����S�=�*����#r�T2|�_��

��i�"�!��lq�m%m�ʁ��|
˳40l��&�,gɗ����le�l��2h >�R�\��+3��	��F_:�!b3����(y�j���BY�ÛRC቏���f�v�����9B;T-��ڡ*��YJX��0Yx�t��͹܀�di����>���@5~c-][��cD�7,!Sz¶�~� K3f�"�^V���yڳrѰX�E��lYW�+2%��ճަm�&g��MM��{3��(��6ה~H�h���
�3%ٝY�(�t��a���è�;�G��p�ge����J3N�k29��2��`l����4	{I�C��a�T̛V{1+�5J�Tw�$8������J	pz�F������i���[�e�`�`q�s6���H};2$F~�̒N��J�\��UUF$�jNO:��i�	e%O�OOuw�5�s}��9GN&�H.�z���t�0�]�)�<�3� �$N��2On�5��3HB�F�>�$����D��͒<9V����g+1V!�V:o�`&��3��U����Y� ^"�ӈ�� d�Mޫ̫VRD~~���a���:�S�E[�eD]LB�1�͛��А�t��cg��K�}�l�k�Ќ��;���g�;��՞I#�`VI׹�l����æ��T���,G�����J�=[�z�fH�m��<��f�.�ƛ!@Iq2�3TF�\������GzЕ�]�m��?҃! ��Ȉ�=��_�N�O_�y�y�bߟ���@3 X�_����T������Oɱ��r��
{$y��<6�.V��""k�䓥�|��m���Vo-/Ѹ��j�#=R���\����4������?��s��k��Z��Ƃ�y�m���bU2Y��t�}����������xZ�Z>��:��(�"�H`�r�g�nE"S_�[�ʣ���g/ݖ��Z.Z��vH��@R��Y�FZ����ѝ�9��:M�M	�W��4�`xp	~��zYQ#�j��8�㏶�\o�L��{�OV8a��L&��a�ψ��u=�6?O>�pڦF�#A��x+���Sw~��:%a'_��X��|GkI&|L5!8I\�<��O�ys��Z͙=Q_j�|�Y�Ű��1<~7�ra�}A'�8'��e(���/7@i�j������d��������q�I��n:iY��u^�P��+�E�T*�M=�7�@
%��k��c�4Z�SH��Zk�8k:��3R���Ӣ���˫���~�♳"Y��SN
�O����5Β���/'� ����qf%�5��>���a���O�S����C��U],Q'�g�ˮ>�g���\�n��R�A�7�1]���.�v�)�k����32ʢ��ы�z�
��[�ľ�9c�Z��$��Y��F,B�t��5��E�K�����/���\��/���a��� �y�JM�����8f�_� � g"��
?[��۳�r�j��Y2�	�$Q�s^B���{���^�����Gi���As^in�_��;=6�;�d��x�hb\�ɛq8���(��O���EH�1j�Ė�r���3�lx��"�*���%J3'��z7<�znW�#��n��f��;Ce�4�X�fl�r���T�
p��A�B�E�`h����D Ȭ�Aɷ.�/��|U�C^�Ǥ��	�9�%���nCi8�u>js�	����D
��'�?o� !u+�(!yҗ�0���O�1�H.��u�n=�뜰���ys�R���Hz�.0�@2K~�P�$?DYj��t��L�gL#�"�f���q���p��[��8%��&�'>��z#ck$�<�e`�Bg[R$���������n��¥L��	T@֯ٻ
�����2����ƿl���v�a�e8'��Ȱ�KC���σ���Aܡ�����@�;�ԉ�'��zN�Q"�����E,��r�3g~�����P�\%}9�f�O���]��Zo��J��	����ΐ�����
i���/�Y�*ӪS�o���^�]�6R���aιU5��y�H]�����a)��!�|V�p��^�\%�<�X���:��iGH;Nʽ�
���Po_�p��y����{^��%�`?�$]�����4�=�G�A�A��x^$�v]�~��7�N7����RQ��,��G��x����Q��91��\RE:ʼH�=l�Z�["�#�d@2��x���!���b-O��k��d�}\�u_��ɰO��bX���J��k��b���,�����4�9� �A�$[D�R�"^�e��5H:;/rdᨺ�Um5νv}pm�`K^�����;��E��L�@�J�����J�n�kr÷�2MP7^��~��dAAI��p���2�wޠ��%�� ���%���їD����%7Sk��M�B3�_��2xBے�Y,�(2�p^�u�:��K���xz��%����D��4ͱ�u8�y�Ȉ��{�.L� 5u��2�����X{ͨ�0��"�7^VJ��E;`�9�~6�(�ߣJݶ��gI�Y1�^Y>Ay��\����
8dTBї��֝�:��m��9�'����N����~��R"���^9q{B�$lʠ�<��m<I�12�-�{��!k�5cdVkXyY�k�����Q9.<����T�܅��{��y�~����P�U[����yU*�e4�\��K��&�Kc��T:�YW�T\��;�֛����hƤ���E����B��z�I�� �*�mcWϺ�/���l̘�i%��iy�- R�o<�ꢫ��˜A��w1I)O^O}��X^2TڡE��/Rȑ(����y?L���� ��
�M<��v{�\fܥ�bm�̌ �'
���@])T,���W�u��7+���I�O�u)z����� eJ�kO�Ӥ�=���S�_��Gժ��M�pc�H-Q)(���Gg�<:LFD�ZCVH �Έ�-7S��#�z��@?�������$�H@�³��5�	1)�Q�;�A�";���%��B�8H;v�S+C���p��N�F��j��8���m���q��o������py9�,O�F�~x0%�]��тn��	��V�n!����?��5%��!�����G	"-Er<f�z�A��X��
�D�b �,,Œ�Ѥ�:�j�P���=�R���R��������c�m7v�u���1��Q�罁�!)�.Di�u���w�֓��Þ�ޠQ�$�/��y>?k��*Rbz�F&�IVm�D��lBH�t�t�z���eA�#��iY�x�T"ޅ�
�`T�C�1TS����Y�G�é&�L�y�ƨhZ��tU��8�S�y�    N���?PK�Ѣ���c�@=��1���b�Y����dn��V}�"2ef��җ����N��4��?19���Q����K��`��UڈrԐ�#��U��$zӂK-�qQd����Qq{�ZW f3fk��LZ�����d���A�G^&�!���M_���^�z�PI�n���(/ig6+�}�H�P!Ro�;���I�Dl�Im!2��F�³�j�rr=�Y	��%F������؎���hQ��?��_�3*���wh0
a #Z�B(��%�� d6�R��\�IxD�^�\X���S}\�BI,*;y�y�Z��b�C�L�A���+�m����Wn���D�#+D�|mjm�s=�NC���K��5�s��P�U͍ׅ����uYĠXB��K�z���%"`[�tN��y�F��-����� ��ED�LH����e�����4�h$$�30�jO�HB��r��{��XCɘ����{Gٖ�m�C�}�,��2�ys���~�<*��d]~j�m�sHT�IH$�@"qt?�.#�������G��B��??�6��B�����c}�<rQ��Kg%h�X���<��?ʂ&�� r����ᇅT1�^��T�ȹ�a���VĄ��̴*�6�*/N'XȿˌPt`�DN-��~�����_��C}l#��8��dYHw��O�\i�uG������c ��D����,Q���/��y��;�\#t�n���C�nH�`���]O�����~�u�]��As$�C�nj:�c�������c���7�h� �˖����HT�(�"����8:9C�a?W�}P]�_!��gssz��c}�{�nF�԰���0�D�jEZpE�?�M��&��s����������n�(�Ͱ��gRw{5hA�c'Q�vP��s�ҐDo��ā)���p7X:��fSb�tk�ߢ4�κP�m�B�#�B�n����(ū�te(�.�5D��K�\�c��Zd��Ul |"�l���q�5�l����\[$%��iDmM��x��|��r=ᘻ�I��K^Q�i�br(b�4�:��H��e�2&`J�gEY$�KMW�TP���.��J�&�m,J�k�������5#LX�Z,J��ֻf�B}��$�9Ӧ9��Xg�J�S�Bm�d$#�C�F"��=��W��V�tQ�&�-�͠�ơ��΂x1EDYA�*j��i�v:y���P(���D���o[O��$��eD}K��"`�2��赛�ХT۝P	R�'����[Q�ȉN�a��{��"E����ȣ*��7���!{�s�	��l0�{��z~�F)���R��$�	���iPV�7]��M4�X�o^���@��V�P랇�+������u()GbȤ5��"���S��P�*���d�Q`��t�?�}�S�k��&�4���Q�ÓA�9j��&Σc�2�����X+�J��2��#�wQHR��L�u����E�r=Ჭ�Xɴ���(��~E��YA�9*%��V�j1]��g*�;o~���|��/		�Y�H��nI���JB���P�I�K1o���B�T����:�w�'5�q��2�f��d���ƃ�����ky�D���L WkO�l��V��Q IVF�Z���]�5!��>׭���B��$�����e88T�v��+�u��v���l��7m3��4Է6�=�W��}7x]C�	�%ѹB7�M��`�M7�am�I���^[E2Xi��7��xrй�5�=�Мr��k�2?i�K��C�X������u��Q1��.��8����f��ӥ߷����_룕��s�̨�I�����l�1�鬗��uRɴ$+#���au@'g.�a����^ר)h��B�%�m�/93>t�V��~�
]�g�}Ɠ��k8�!I����
6�G��\[� �W%�~�:�q��e7�����C�ܸ���s0N��<xn'39)_�U�O[r����A�|⿡/��7�} ��"�A���GzBm�S�k��Sxe�j.�F��%G�^xK���exZO�I1�r��v��_��=}\��Ȍ�f5J�pyZ�������W��ߐ$� ��R��D�	F��v�^��פ���U������Ӷ��$�v"�Hy.����oƺs#'�#�R@�8t��A�}��0\�b��N�iΞ9IJD�4��(Y��QnT���k鍕&u1�(fZ�>�#l'#����=E���'M	2M*"J�Ҩ��sƵ#��GoQ$��'�(�n��35,E�|nf̓�}����H-�7H���dg�]� �I���"���#���y39���]�"ML)3�`yՒ	�.I��la����2�R�����cbkw�?!U����Ւ�X��}p�\�����G�	�S��Bg)����XG)nI �dD�DJ	�����np;[7����M�O�̭����0�J���e�&!?Z�/���W5�Dj�ު?��}�#�hi�ʥ����D�џ�^H�.��辪�;��v�+���F��o&4���ð��q%aRs\�y
I<���sM� ���OŮ<K��˲���:,�<2��9�8,��OО=g�,���<B�����8�xȌo(��I�7(̓��c�P��Ŋ�\*�z�nn��١��d
OD�<��F!�%�$T?c82��ū��ú��:�1�Ǵ��`�%�ؕ��ځӉI��-� ������q=���Gds�'�Nò6��b�����b}j�r�g�19s�C�<�Г�Z���:�h����^[\��LD�oe�6���$��5u�@�HT5�Pd�p�#5C�VH<�}�5�IVw��1�]Y`�n��:�D���L�X�UD�H�Y�oGU�AX�v{�T^FX���Q�Z��˱�����V[�-/Ģ�`odQ%�k���P���M	v"	�e��@p� no�H�.c��:��{Ft�n��8��6�)'K�|j���d�l�v.3R��ρ����6>�/ �8@<�Л�Z6��z_�4�d�2�o>4��p�b�r�,����,��<^�&�\:�e�,�f�9��{�1nAg���ɲ�jܗ���X_a�����E��S����d}�)�0�~z=�ռ�v�����ĚB:A-�dͶ1Rķ���VZ"U;��
��1:�ߔ�0"1����p�E�X�>�31ܶS�N!~lŠfF�yC{u+��*cF�2�\�d�p�HD�:��p}
M.��8b����V��3���!3\�'�9U�i^w�Z�yJ�ț  #"q�"����X?x��Bg#��H=S��n���׆K	;Ř��*4�=��r�l_ju)�\���s�WXA��6/ՖWQN(l�z6O!�h:�I�2�wzF�yy�f�/���ݶ�����rB�9� �sd'b�V0�C҇��]p��D4f��"��&����(]����TZ��m��?/q�萈X���n�HF�����;O���H��P+��fOS��߫�]�=
���zȯ<�4�7��9���a�Y#��&�Q�j#f:���?���E���u8
��,bJ�g��k��<R	Rt!Ǵ3��p���DD	(�P\R�8�Aе

B֥���L��'t%��.#��<úp�sC���r1�{��vԵ��ȯ4R��Y�|o�-����V���I������=��*z�mQ[�?S	���"R��Ye�f��D}	�1Z�sy@E�3%��^�c�/F��p���5r�!}�!$�н ����J����Ѕ��Qyi�8|��~����P��ۡ_��z�JlB&��#�_ �|3Y��O�:q�IE2Ƙ9R�S���J���}㫊��U,֢T�ppzúZe	2bd��"Ѭ6�9������R��(K,{% V�L�6L^u���3X�4��Y�x@�N۫��n?h!"b	D�e^��4��g�\o�/�1�$���?co��n�^�-���\L��!� ��_�d˲-���'�����)5#6�!�-��f.�s15o�ج�$,�$u��(Gp7	,��߇ ^j�u��>>���-�HA�2c��P�ە�~N8�R�2�t    ��G��Ќ=T�7_���w|���7����
�����SY/}��4�+��G�����{�8e��,�5Y��m�)g�q�������<�d_f\)�A��C���iTq8�M-LNk�\4�e~�Q��2Ӎ�j���j�~U�z��!L�I�E\������:+�e֋8e�D7�6�,zz@���p�y
I�?z�'�O�}��'Q��s���_��k���:��A�y}��]�j�E��4�	1I���<��/[����'�Q����|�Y�ÑH֍��̱r�Z��;"��fkX��m#�������Z'����#�2pJF8�st���v��/; u'�s���sf�xWCzԗ����Q=�1EJ$"���Yc/�eKy��sqB��"�>Wͨ�M���0�g����͋�_^���uz�!UʲȢ��{������m�³؞�ĳ.r��	d��RY""�����3�vV�?�ɜ�@n�������퐆.�bb�l�Iب��H��P�\5:��� ��!������7��I���i@��,Q�j���B��4��T�it1�ՙDPJ7Ѷ�[�ks�P6U��G��n�Գ�e@���<��U���MAT������IdqY���z�P���*r��=�Ұ�O�i��<p*����z�����Bʠ�oP�T��޷�󹃷��Y*����,t=���~�	g$״,e��>�Ր������ޜ�ɝܓ�JC�f%��"�G4:���y����F<�5�l��h�G����[�D>���R0�e�޼���䡾`���� ��M��J�G�?�_���_�B�/����?�$� A�JFy���wM|�~o�P�VU���u+��G�J�Q	�f���7��^�1�>()j%�FCׅ�u�-���;tT�2���4�g�L*32T8��������?n��Xk`��K���g��'R��s�<d���N2���"̦Z��p���áEOĀi��l�g���V�@ ��p��WճEm��ѥ�(�T@���J�-��¥p�wS�͞���~b>�:�HT�Rk�(�7����t�:u��n�q�w���"���Rz�`nV��7m��d�!���c8Mp*��C%\�7����=	0�ɫ�O1�O�c�G���N'S=�{:ipl!!9���D�$�9q�?m����6MZS��"��'����K��D@��0�J�f����n,J7%*�BUP���s}꜡�/�X�
���-џ�"��%�YO"����}�X�h�^����V*CB_��� 	��9�:m�,�(�L��9<1��}��[9A����<I�7�ဤ�v�ԳtS�n����m]�/�k'���J�v�	2��<�5�Ro!����[%���=�t��
T�-C2ey�G��{=��vV�'�Z�<�y�^��Qd]:z��?��?%�M�׏<Q�>F������S��m��Pf&����g�"OPro��_BfA��Q��Чeo���&ٔ�G�b�]����O|-�	!~?�*�A���ޗ���2`�H⦹�?ՙ��/����m(�^���MO�s5�"?Y��Dx����G�܈�DiK��x�G�͓��|�2�M��t��6��i/�ъ��{؏�	�5kpym9Y�S]X���w�9���	�s�M�šf��ڇn���-���H/���b�s|�?Cm���w��pC#�=��< ��Q
���?T+_��8.=���?׳e�N��
�E�2 ��BS!D���-
�U��J_/�������0+���kh�K�Y���d$5��̇���!��đ؅�֨������{6zY ��Y����]����<GsY]FF������b����3�.���(�� ��gn�OC��6�'�׉�W>W��Vf��O�ՠ쵖"!sEy'�H����U��?_ܽ�x��s�f������a�����۸����"�3:��9���R��z�!���	§忥o.g�8����j,����a];p�"�D�Y�k�1��8�[,Fl�J�4,칞�A��x67	ljA�9�w*�" ����R�^��ր'q'���'_���l�S��.IG�%������J�����Oȷ�����fj<O�oh���d�u�3�2�y:���)�B�c��=��Hn�3S���p�-�x�j4Ͻ*�̳����C�/aR
�9��u},��/@m��r�s����74Dl_�(p���~����-��h�Q�>:��Ѱ2ɡ����X�tWnՌ�e�:ύ�Mu����]@F*��s�=@���}@���6��������Y��L�K�팟��ԇI�v��i�=�����-Y��Ǉ�fS����A���e(�+Xt5�}�_��cݟ��*�`.�G^d8j���ֈlٷ�o #� ^��]�m?i�LMIOh10mxQ �*���j%� ~J���"�F+~�J3<��_У\j1�p�<[�.��4M����4�!YO q]��FFF	vЯ�eoSR�?�Օ�P�����B:���@	<�AQS�Y��l;h��Kco!e�\��R�(�K��K�d�y� ��l�7���VfS�����,m�N��en�h���E���䕏��Q�K���6�81����S����������W�L�D��K����P���?�f<l�ф�&�F��2��� `a�<5�#���ɢ�G���rh�(���7hU�y}4C��,%�fi���qY��S=4�\w�Xu*qdàE��
[��3홡��gɢ����oڲ@ʫcl����rd� q��<���X�Vq9%h'΋���Vc|�N��p"&�=N"��"З�&�s8/���yq]v[He�ϔ!�J>��6�����fL*�s���!�3�s���?r#JCv0��fr�4ڌ�N�DWck��ȸ�8��g$/��4�TC��pj:h��b��=}�fpt\T��(��w�m���sw7�=,�??Ⓢc.P6r��?[ۦ��,��z�BG���PO
�Kc�U��A��?~�4�� �1��(��nQ�*V��Hr����Z��GS�hh����5�f#佅�C��m�ukƻj�|S���w���$n"��2�V�ǀ�=ٶ�?/�:�,�z��]l�6~����M����C��r^j�fx�o{���S'9%��U�b#U�x�_'���̣�ϝfu���΂�eD[!� ĥ��=7�x�������A灱>�q�Yu' ��K��ZMN8h2�+��mO���d�P"ͤ%?l���p�/�+k'2��De�������l��M)4����U����lL�2�	!+J��$-��۪��!�4ٖ	�n��#<UxAP��̉��m�d��&�LU����ei���i��%�<Re��e�sa�?Ax���H
��>T�f�z������W��ѫ-�3] �"��!��K)�A�?[�.!�i��ЛH���V�Ŧ���3v��:%.ۏ%�fF��gD���Hcxz� �;�u�����[HB�z&�H���6}��qչ�.��%���'s��feb��i��������b"�Ħ����bʕ�I���l}��?�SM�����<�_��'�]C�a&�J�oma�Ce�i�89N��t�O�"q�"-��Y���$~kN�"-�� djg3�a��!�D��$R���V��ʏ�8PZ��|��9�Ʞ_W�z*���0���|�b߬�� ���Ӹ��?���oO�%�&�4�K �JMà~��j&v����`,zuj���*�{�wy@�A��F�Li��r�{��Jc��� l�c|W���h|\��VY*�$�m����Q?�FS�4�zҷ�%{eV��>�U�=�%�"Pf�8��-n�k(�h'����IN��QXU �1����[VȲ���`�����9�PBQ��aE�h<�n��R��	���������÷��v�E�g�cn���*��ٕu�2��3C�H�e��j'����� N�3�|�v��Zjb�H�?��Y!V'���x�$0Yi�G멹<� ]쨹B�    \!��'(ˌ5ༀ��H�� Ad�Hٟ�"�.~E��P��rdl�0=�ڮ�f*�g��u�P�E�D�����9�ʇu�����z0��-}n��<� �_9�&��3Į�Rf��o<Ԓ�R�3Ϣk���򁄬k\ڏ�o�hB9��q�Uw5l�c-f�J�N����@�EqA��C��y��WϘ��"t��PT��f@c厚��Yl���"��E��2�{��ZL-�`�T����w�
+����8V�����C�J�"�p�m��P0u����ׄ���W?�1Y�H"��LfzLn�g�C�Y)�L�������E��D��		U[@�����U�5��2���ju�;;�A=�,#E�G
�{r1 �����o͢pEA�{\Q�J��IQ\w}=�`�U�f؄���2�:�S��G/���q���K����d!��ǡ�&:"7�2����$��F3�5�EU�e()+-��t
կɩ�-�g�1u-�/X�r���Y�Ґ.iA���f��BW߫G�w���sP�F�n�R��O�arf՝:�����L�U3����L*�]��p��~	Q�-���s��sm�g��ԗ(����������H2�0ҩ��f��]א�/gI���I�(uľ�@i��X/^��0���Y"�	�����ľ+B�'?�-D�Ŗ�d�����F��Q�p�'U�E����!	���.b-w��9�G�֜�5��
1�)��WP�L*B ;q��'pu�x�L��j��nU�1WTpj�S%��nt�����Ͳ�$�2~��>�6�������z_ಂ��I���jʀ����>"i2M[�/��E�\"l�
��M��s��U�v���cH{F��l�:��_1Ykޏ�#��N�4�#?���ߪaW��\���7[3�l����%c/K|u@�
#)Pn\&v�Ϗ���C�
�W�@��.����ؤo5'3��!��b�(-m85�u�%�t���Z7�'� ���� ߗ������~\B�
�3�'D��z|Do��kg�YrH$3h����TN ������G��ސ��'"qH���z�To�Ed��d��:{�3b�Vs@![e!up���XY�B/��C�3d������j�`���
�2������GH}!S����ިo*M�E�-�p;|8��ۊ�;��J����f=p3�4�� ����@�g�r}a��-��y���m?m�)[p'�" x������{��L����7����E�huƟο�d����*L{�w���|��9I��E&�h:��{���PY�� �" �"}:���>��&���<�b�$����q����?�S&H�z�7C��Z"�:$'DH&?O�V��*E�������?���0�Fe־s9y`�"[�5�	BF׍�	�fI�I7|�`z��G��ޟ����K����|�S�EFLh���H����*��rg@;�4q�KH"�1��&Fj2U�u�]�:K����H�Q��X�6�u�)d�vQ��J�t��(5d�EE��ӽqf�i��.SH/v'��	�D!�K����m<��$Y�u�O?�8R1+D\<=c��+�N�n7"h2/S�So��a�}[�WHQ�g|J����]���fP��4ԧ���nO�]|�퍓�R��:7#��Y �(�: �u ![֑��7����S]��n�F{Y[#���P3ځxs�A��>�/��z%]��NG���/�E��9��B0%�ׯ���!����T��LP�����,�Ƴ6��a�n9	����f�l�_~9J��agӟ�"ML.�S\���!e�&
y�m�͓����_'-�EN������<���R[�tX�֨J^�3CKK�3��S�D�����Uc�72�f2#b�fh�<��ռQxRIf:��鞞��2@͉�*ݎ�f�U����<>��fm��� �Yf��h?�z�Z�d�"3c3W��=�r�����py)�2C:W�զ^�X�A��.��x�D�q��Ŗ4֥:5��>�@C�8F$��I���[g2d�)3]t
��h�N{�wrNe�D�R_Z���0��?���p�n1�P��Ͼ�O�EBB�>�^�`�2g�iV��S�X����5�"�/�)p»Fw�*t���Z-�~V�
��<#^~n:���(�8�if������̋�e����ǪY�	�~r輺 �S�>ƅ�+��z5zw�
�]BDd�g5�y�`�;}D�]����鱲4�]���l��*�0��,��p3���D}�"�	d�˪H�$�L,���c+d�C�08�(�%'�R�`��/��X��o>%$	�xd�E���7�����ۦ2��dr��� �>��t���q�i������W���0�7M�⢄��Ŷ>I^�=���4�J^�s'���ʺ�/)��@�OL=\�n�6�2'�!9YH@V��_瑬%��y��=LY&���"�ܝ��n��ֳ��A�8�T	���$���j=�sp>Yh��J����#��E�? ���if��Z�-��Ԓ��������f������!f��S��e�=���]�Y�FkZd�ژHF�ӕj6\U�8��LRN�?$-�2��Om�z1�H'�N�͂K�I�Cu8�{���Xn؂p�K56��'ܖ��z������Y�U"���xq<���m+�qb��C�'\~�=m�$��ˀ���*%9<�j}z�v�+)��P�mh H~�]ci����:�S*Jr(�a���c��0!G��q�ʀ	��+J���H��z�m��V�wJ�`��u�����\iS.�y�{���29�^�8��R���^EM�g\D�Ո�~ȍ��~ �s�[��H.u�������)2/���aI���<@��"�{U)F��lM���� 3I1m�v[��2A¢��VD�C �rW\�vZz�e��+r����`��h�pvb�("R�~G?�lΝt�J!{��P��q_?V1��%cf�� �ix��d��s��D'�j�Oh��M�j�S�ɹ#29񠩃(&���Ce�8����~F+�I	I2�淆KTX��s�e�-uQ�$����	����D?I�fF����+��u%�@��@DxD�$M��]�q�zR��L�|VO�_C�ek(g? �^YDJ�Fe���X�3�B�wR������9,�P1�Sj]�Z��=�����ھ	<�i��.��S%���֌;%ʁ4@�F�T1����8�[�,�S���ys��߈s<K�Rz��9M�,a<���~�+z�@B{m�,z�?V�hD$��.}F��5�$�2��h�v����g\�A�����yt���ђg��?t�庬	Aska��`�FO@�U�8��)�H�����Ӏ���P1,�!~5�q���j�j<�N��{uN�~ 뭨(�k�n��"�oݮ���`-]i��E��S�)�vQ��(��{�0��%���Υw�`���*CX	���@`�gk�`��~8��y�W����z�F�[���{՞0��
A���z@�5nQ�S�yC}�B�X�WA���4���ȟn��¢5�)�JS�Ȩ�'���]���
��P�[p��\��y����zo�1�R�GU�i�@#�T���c�Px�,aIdTB����9z_�kxҋ��3�I7��W����i��ꏹ/��>�������03ky���b ������E���ag�>�*� +列h�Fr�Ƙ/B.=m�Ut���Fw��9����K�L�b}���uka�!d0��xtyN��O���������Ge�U7;�y9�I�y����auU㱏��癞}���o��S�_�in?�ɒLc�fV �nk��Kϣ�ӗ�����j��k:)��L�}�B���_��q>q"s���@}���U{�kڭ^�AiNn�,G���a�W����Y��s���@N]���f�4�4X���W��H���e�?������ޒ)s:Fi@���эr�D�Y#x�0`���2�e�L}4��fP3G=�}�Oz��P�o�MI>�r2z��햜��4`E�%9d�����m�3���sJ�I��i~6����8��)�릫��^�     eM���N�r�Z���*}H	�4��e���_v�h��҄���o�;�~�;H��K���+/)��r[(�K!�`1}yn,����}"s�u�s�_�ں^����,TRa�n��V����D�
4�����O���H]�v|�{3�V��L!�;���p���Wڭ�dT�`V�Lm�lV5TYr>F̛X�+r(�C@�h�:	�*�%�h����J�!�yt���]�ѧ�чQ�r=��wQP]]X�G�Zd���TY\yN��$�"�0t]u�� ���o��4#֐�mB����DS���Q� ѯ?�����3J��&�55X(5�n�d����wkؠk֤u٨��p�f% պ{s�@��_K��������2���_v^��J����GZ�uԅ�����]b��Rb�.�ǹi7E��K��'w�I �X���n	~�G�s�e�c��� ]��9�F�M����e�f,B��ԥޫj��OF����%8���~\[�OҰ�3��a]����X����lz/Cp�7(7ϥŞ��$�-�a�J�͒K�,)�/��kI��gd&vM���pɃnd�*���r�4O��W_- ���\�)z�ˢ�P�����r��{�>�VP��~V]� ��0}I��`}�Z��S�Zk���{���w��Š�+�.�\\��įY�.�I+����8�Ê~�U�ՓM�Q(�,'S$��������4$�d��
R �'m4�
zS�9��6�;����on�ɕ򄅵��+|CAX �CS5c��X{�,T!�7�,m��/|,��MP��(#%ҀZ���s^{������
�;e<����A<^�@�����TPwt���6�Ҋ!��Hso&!h�,����q7���?��q���U�#b��EPqO+��I('0��&~�*)\ �C��,�n��:�Q[R�����;�����y4	�h�U��m���U�+�g�eP���y��c6n�k+�cO/�n�J�|]c	c�>�6�	����|��)�q�9%��u��Ml��2!{�}��(���B��}G};�f���5��2R(����:WB�*�;5M����v���R�YX%G�4x����s?�/��D�̀�޻S�����Z橒��b��r��7vs<��0C�J)ܚ���'���	�]|�FD�Y/:�#�H�ؽ)�����W=@<G����r��n�;�[�7C���s�8���#�Ý�ESߏ�h�R{��>���{���p���'�U�`!�����-d��h	k����wT�D����Z�Sڟ�Z1�q/|y�^@@�Q��_S
���fj�D/�<��o�҃j���"��Nf4]6�-uf��>�����*���A)Rl�L�Ϛ�Ḥ�aA��#�5\W�ྪ3����&�j�+�8�+7ا~8B���Kc9uj���O�,�T��׭����^i�̥�p�Gf���ejG'9bw`�@)5XE�Ο�H�ټ�7paů-�Ô8���H�VS��')��j��C��L	���:.ei�^��+����I	iɀ�,¢��I���,<����Avr����]�8>�M�N�C�������2��^(D):�W����'9e��eH@���ͻ�l��� ��B�����)D�v�X �L�(�Y��e>C�a�<��>e9�g�����d���C���6�Y}���ƈw��^V�"D|�vj��O�u\����[k�0�)3�$k���>v+�/�1j��Ĺ�R�E�����]�(��!�Y9�r�kP�v86{kz#���Ҭ@���II�>Y�(�[��$���ѽ�jp��t]�8�Uj�Y��,�3����$��Ԑ�.��	������AY\�,8�"TE�i�fE��(v��y��iW-輐���O�$�4��Ĳ"��;�*LA�a�E���x�o�ߌ�q>r�����i;����?�·trw����`���(�X"��lT)�!�qk9@E]��g=M�ȏU���֖��pD�x�y)͙��J��o(LӜG�U[�h:�O\���r>�03�~8YIp�󖒀`?�!�[����[���]1_c�I�"��D�)3g�/�����F
���<��AoiMzت�D�C�ߕr��Y���$GG��U�]ò^����^Yb�w��(�kX,7�+�� Րz�U!PIr*>�6�z9T�OA�)�X���vw��]c��BC="�Y8���r��}�#5E&�U!t!�9���t�Q���s
� L�n�t鱥����*%_{�DW�=�j�!���/�̪)",s_���Ŀ����$�VJ���"D���ce�jS���]����y�я�&>��f�'>�{���!`{�����L�5�M]�� ��V�t�q8)���(�nh!wE�G�Х%'?bn}D"�2�\"�2c��D�S�=ş���B������Ӽ��Rb��#5X�/X�e(U�}ef�>zK���T�'b���;"~�����+/w�"�y�i�qsjO9�@`a>=,����4j�����(&,�E/���Wm��V!��xݘ�E���r�4�=��ε�?�y
�6���zO�m�4y�)g�j�c��kPgo�
N7H֐��Ƅ���E�b�987�4s�2����f�z���`L1GC����S���1F�3����>*���\K�~�}��7"��{�[|�Ɓ�XYh/�Ci�`��v۬�=B&Bt�-��zj��Ί�>�L�V��B%�����H/�f�6.u5uҀ~<,Rh��]��d��S߅Y�L�t�A[	���T�7�x���K�T+6p����w�^��W�p�#��bO��z ��Re�U�M�¤�)p���V�t�@;j\�'$j_a{��t�T"ʃs���6�=Oy6��=�'2%�D�����������7����sԧ�+����@"��:�Wٕ+;�IT�4��bk�N��聅���I4e"@{
^"ta�,z��JxX�G�θ5ǈ�re���8��d��/��P
������Q��,��H��.Q�R|��ŧ��,@K�C?.��o7�u�䁙i���G���Q����o��Sa��/`jj��2�ޯ���� ZZ���f�?E�X�t� X�E����К,������f�7%K�q�B�.�S=��b,�,5`��e溯��is��^�2����`XJ�5��ހ4���ץ%�ה��1K
؉�;���F:;{���X�UB������.��)�^Kt*���H�n�������uB$mzC�.,����D��ܪ5�q�.�ֺ�e��b��\Qd�"�'���4%NK�������K���΢/��F�H,M�?�L���*��^�˨AOY5/�*����y�"B���%l�2h4�����8.������П�#*U�O:-ߌ�r��lI��JAK�²Et[m��_#�Q��.�۾_��(�s:��<zW׊���a!���2Bӂ��|���4�=�z�	��cmݝܥ�̐#j1}|@�m�zk&���>r�B���n�[����a��`,���Og�u�>�y[�x�"��?֊/5)��j���0�c�L �NG��Od�{�\(��|}�PǙ��~8+i��M?��ƪQ��٠e,��^�R��3

gE~���D�=�	�<��g�ԍ����}k�`H��럑Yc�0A'є���6�D<`�(e�L��{����������f%_�v�,˒���w��������v=����w]|]�����̼Ig��Y:���ppjkx{�*'ug�n��G}����s;��JdK��h)Jzcg]i��|���o��i��gk�;��9�3��=y�d�K��ʘ���b�r���r�>Ni��$����+Ug/s� �>���G�Z}9sz������f1똪4_���X&�nl�&��a
1��:�V��a+X&�R����H��K��i�V`
Ӡ筷�Z�P�j����h��Gb !�,Ϣ��Y���U�,!nC����`6�ʴ��{�)YX��^�+�c    �)%dt#��b�l��Y���Ty�G#�H\�^��e�(f�"�%�#�
����Nn��ʭ�=$���2�[�X��1N��l�o�yJA��Y�D7�@=�w�A���6��o-�}8������?�N*����}^�b�1>TA�d�&*)1Q�O�"B�f�U����H��m�K܆C��Z�۞�Q���\_�P*|i]$ }7Zr��
���a�I���&�e�r�U$�Ù�ש�o�Q��݂k�*�X�=6�-�ޔP��Srw	ܡ���5�5�UF|1"N����b�ɚ�&�,�T<S[�L��̛ʔHS����!1C�TNBxDV�UC�� ��0��E����<�3�sJ�\J�w>���p���K0f�13	`�� ��i�Ǻ�QB֐٬t�=(� J���@��ɛ؂�zx2z/�e��^��6 !N.J���<5��
T�����4	��=��_fH���IK�K���K*J#�FJ0�@���0�̬ͅ��"G|I�5H.��_�ɫ�邌3�f餷���H�����k��J�>[z:\x�$�]Nq�F��8A�y�6'O\� R�<Gͼ4�S�.�������d�ڞ�H%5"����O��\�:<���7�;������E��G����$�?e��ϸ�@>X���`w{RY$�x�s翿�n9Cix��
$��疘ݾ�W�v�<�	]I
������#JJ�tj���p�jKn�>̠�w%����/��{p�'�������³V�J4���t�������^fw��/���z��� ���"z]����?7�I��|����Gf�M�ͦ���<,t�i�����g=��e9�`��|.�Emd2�g�u"�*	��1!�o;[���q�d�0�D�*K��0����e;WZh�G',�G+ޚ��������J^���"v��i>����-Ó풙�v�mu��		��h�a낫%Ic�hC��^3n�@r�h��^x
�
3�e��o���%�.(!fX����i�c�cE���r������LApDۮ�j�th�*Dؔn}|�1�����^���f�������C)��~�,�a����Hx[f������k &�@n�V�롇���z��b�<��@}��˻j����l�8�P)��D"?������As��ӛ�S%��k�4��R�_D4\�44��L��;�1^!v���(g	��M�O�Fz�i0��o%��@�s*Z�^Έ#���^fF��&�Gk���?H9�f�Wl�l�yOha��� /�޶���X� rޘƣ��Tw�Z�KeA�XK����4��XD��D�,�b�%�fᓭi�	~��d������������zYZ���k�m�����q~��p��q[F"܇Ge	��n	�xW?9��Ra�8B�ǇU�J�B�g��l�d����gˁazw��#�$K"͈����X��&ci�t*?W�fQF����k��U���`~}zx�W�|R�.�j*��*c�N�0�~Z�)�'�M��\ٟ�C��UTq����a�ϧ��x2b?����5̰`�n:���J�7L��Bu�6À���iN;C��d�M6��d���L�D�U23G��R�����������ӎ,���vG�P�KC��-� �o�'�ZdtF�zX n��CH65����B6��gY�/O����������sn�o��i�^=�׍�sl�k@|fY́*�_9sɣ<���2#�<�_�|��#��C�,���S��W���� �����uvn�+CJ��l��d�f��el�,<S^�8m�j�3ݦ��v^��I�E�<�.�X�]ñ:�0?Ic~��E���m?�����g��Mf4L��m�1N��˝0�1���r����apGw��7&�Y��m}��:+M䀻�Q��o���lp��8�ӖO�d�cr����� �M���d�aQyrw9&��<�m�-|���A�\D)�寙��Q_���R+��MW#T��o���|�zM3���"1{���giIL��@Q�IS���8�e�%�	
eC���jSu���i��bx��Y*�6�[�}_7��O�ڼE����ߜ���Mpx��*��"�P����i9z�Y�3��et�8�2g��P�;�qe2�����������[���B'��W�Ԕ��Cp!��;;0�䊲3$N�뇺���(��bN���
�bW��ݖ3� ���=}5�i�\!WJB��4�2��잺��j��3�Ol�RC�_����Ѻ8a	�0Ԭ���,��2�������,�޸6z�����(���P�Y��ƭ�փ����(�xs����iXߝde��.��>����b���!R�   3lE��UJ��#8����%��/
�5|�(����FC�����6�4q8�n�0'�����zAp9�.�F}C����W��YYc�6�'��}���`xW7C��l'����)e(v:h��tE	�35^b�ql�Gū��v�P#���oܣP����y��Q-%����2��8&�}�jr�ܭ3�ؓ�%9�D>�_�����(h(���t��|��y��C&�I��S5���(s��"t��^�z���݋��6YH�&�M���T��%�~�E�F�cA�����HH�2��8�4��������Nuu�}�M����3!�y�ttuL�2�kq���FՕ~����C�R��2�М^�iઞ�P4w�C�����E��D�y~�&Hu\D�]o��T�Hx&��ۮ9��m{T�=IR�?����������,J�%�ޜ��B��C�q�d��*��Lf�ᵶDwZ�����2����Sg�.�܌/"q�Wh9�,P��Η8/Xd���D�<�U���7A��*yt�J�ʘL�|>��eဳY`��I) ��Z�������׎��ڹ{j��OHN���
� �IBS���>Ǿ�8k�?��>���ם'ث0�Ea՗E#'�y�"�C�	*�����39!���y���~l�Ζ�N���a�P�'�^T¢��b5�]���	�&T�P͒�	���]�@>�qke��S�Thx����蟑WN�,BLq�C<��Bһ�'>1Q��Ƴ���<*�5�6�|��҄�0VN7k�HR��R�2�<*u!�l
�B���C�U��2�~Fd�J��(��4Ǹ����^/gm;w�vr�:�p�7���+���dG$7c�O����e�Yr��y�x"$Ci"��Sq�_�2�y��ӝ«��5�M���`%o��>��_����6s�!ݎ<后?����.�\ojv�[g��la9i����k�_��w3������kD�h	0Ĩ�{��_5��>���X�c�ѭ��:㳢����'饜��k��To�?�o��.%p"
R� ����X[u8�G\6�e�uc�����In�:�-��v��%ƅ��r�G�Ӹ��_�ݳ���p�[z?�J)��rmpMd��3ԉl��)�2vJݨ�`��PҶ�F����ۓ	8���pۭ93�U�BN���������)c%Gj��uy��w�ո����CX89�FS{8��W��?�A����i�?��W���s�	_���ا�{mQ/���߀�,���hcO��#�rA�piv2;�$�{��\���9�[��=�@�ge���W���8TH�Ao�1a�-��2���34{�#�i�vA���<��F�V�������P���>��������2t���Qz�)XOQ�Ns�4���e�A�+-��B�l�@NX}G?&����)\\��Z���)S�8��o��h��'ZK�o�(�:�Ǳ�e�����Z79����ק�	�<}!9�5_g��3�9rdGK�$'D�BZQy^F��}o	Rg!)(��9G���v{S���ĵ���UT��l�~@o�q�o���	�X��^�l7�K��]�y�(XnWm���<67
��0,s?��cݪ3z����A��J|��,zYmvu�+'�ծt���H��}����,��И%��9�����    d>�������ѲL	#�%vc��u����F jD�?Ѥ�����N�=z7�[�Ao�R�T[pq9Ʒ�K�p�T�H���f6���jb�K�ˀRF^��-�N�%��4�g�5R��G�{�Wz��_�;�f'{Ȍ_m��0����F4�H☕���ZF��,Ƹ�)&�y�ْq7ݶ>����dis��7���y�T��κ�~��xF�0�wV��x�MT��z�yC�*K$�u
b��=۲i�P���}���I_ž.|��<�g��"��U�����ب@|�2��`Ա��zT*��co�dĐ=����JKK�����
�%��i�l�tDC�?�(b����<�e!I+ҍ<����4wl'��$5�|�(��k6��k�WV/σ�M��:|��Z�9�=u[b���^�jM�K�G�p���;�t�Y�Ƴ�&��9/��Q���;�Ve�<��L~�2�� 7�M��gҌ��|�Itm�y�g�UǓ&��|O"�9�\k�W��bg�NW|F�RoL�8�N���e�Y5Õ("eD�HbD`"7�F������A�j�	���O�<1T69�Y��}�Xǟ�]�����;�AZ(�'��Y�g[�l��UÕ)����0�1���W���!T[�Lq=���z�|ԟ_�����x�wkxп�}�V[s[TV�1��[y ���l�A����,0�΅�n���X�b�-q��.7�Ɓ�u��F桽'�A���}ʪ\\�d�l����L1��7�c\mluO
���dl�o��Jk�Y�xT�d�HV��;��^�+U՛�_n��ү[b�S���	W������$qE�VY�>�:��=�$� =�t��$yr$8Z��]�?��]y��K������3��2��vѳ�ϑ�{$��92��GHn&�8���ʢ�Н ���x]�.ό��>�6_�}I:5V�N�Ќց*|�g��L�â��x�;;���|D|��$�4^W����m�5M��PC���uH8�w�>a��D���ǫt�=�8h�������׭tݙU��>M�/c��z�^������@�}y|2)Pi�n��S۟V��l\�5E"��~�X���V]��T�b~��-TĂgr��y ](�$zu��=W}{�5��,���K�t�
Ä�� ��7��i�j�	�b�1�"�*D��B�[�� uhz&���k]0�j���֮#�W�U��~�+��M�Ę�i]c��s��'�Q��_�L��)7Cf5°�\�ęO1/i��Pm�ye�o� �D�W�܌"l�N�����_췋Tb� �Ꟈ�Y�tw٩�X�#[0Ͻ����$^� �hۏ�-��?�1��^�"]�<ߑ��c�p@���e�������J�η��o�e��^wX��]WOTU=�ol�CN��#1���.C~�ރ��K����Uj�g�Y�t1"��%��X
p�:�����/�;H0^�glܗ�Ҫ�DzU0��\�����^�-E�·�ם	*�3��֋Z�>3��$��-�D� �Nz�4�1���w�WdiqpW.{�n�+���dld-!A���T��Xt���ҁꗣE��ILw�e�mo]��:��2A���؋�?�M|��K-���/+B�"+�E�w6��byh ���h#�l��DI��I��p[L7�E����o�*c�}�Mq������p��ohv�0T�����^�;��&>�3�IQ'���)�x�JYC3�Oj��h���Za�X�׏����vR\}��U���F�q��5����B��NuEn�k����r�YPY�,+r�{����-��\_N9�1��"�Ǯj���t)���}��V2�+l_�>$^�a��tCo=���L$�E����ۙ�:H��97� ��﬷���Ҧ3K=Hj��F�.�����vɏ_�$�
4��"NxLռO��$��)u���r/P�U4�>�2	�EiÉ�Q�ѷZ����zp����k�ׁ)��`���7� �39�]���,gX��Aʀ�B����0���2�6-��}`$ާ(r��=6w����ѥQ�B���P��g'�u����(#�v��o�
H��߅�ٷ�f3bב�9�Qy@��%��~��noO{H��K|;C�i^���>����i楳_-⿰=ϭ"�0ݣb_��������t�l���t���E�Mv5�|R$���s#��Z�h��o���̴H/OJG4$eS�֯� �-���4k�)�%V��6~Cx�1� �.�EY,��+������c�׺�5���䰯(9\�?~G&��_B�$��R�3���1cU�<�T�"�p���>Y)#��8�gH*α�8���k���Ko�ݠ�"I�p<���i]���V?b�k�'*��^l�O�1eR>��[F�/�e�ī�l��^C,��VW��8��HCkϢ��ۺ~�����Y �X�<�d�u�:��"��+x���a8�/䗹��%y$��%�ֺR$c���&悭YXK��\U���m�-ӯZ_~"`���V�C3�J��8�Y�oʿ�:O\F�U��u��m��T;�U[�e]�˃�&�b��ľ�"J�&���<�,r!Rt~�Pl�|Qs� �,���lf�:�Ɛ�=�?��p%T:/ŷ�N��Q���F��b*,�b�W�
����ϙx�P�H��l�]g'i�V�E��ޣ���*�}�H�L\����Sω+��i+]���2�~:u�Q�.$�^����;_����­=��m;���6�E752$w�c����	g��&9���'�6e^���؃Gз�L#�
�W��P-J�\c�X$��D1��{��G�<��d����h����K���R���1ך��@g����$k9 Ϝ:	����Th�>�ۨ�H$��%��xzKg��I$��G0ܻ󾤼nJdZa�����}�BOӐP!et����mp���pc3,4�y��т�%��j@��n����~�#~�?�7�:��A�� �8���Akc-��������2�k�2�x�;���t�nc��[��=s�����LX��ǹ|�O���[�Zm{��R�!��)����±�7.�|�'�T$?/��}���E�r�=����Al�2�7�C׃�YX:e�ܨV�#v|�h�롆�90�jz�Sl-���P�M7e�9���k�%<,<C0���i���R`hh������[6�x�2AI�	3���e�S.Zu>5��?(�$�|B�ﶂ�t����)�4d"Bf���mu��=ٚ ��K��a�x4���f�6��4��T��t���Ҹٿ������ds`uNS0+�<R��lN�"�9����A���"�Duܯ�4Φ�^󂣑^�֞U3^���6�K�"�LLY���w�FM�U��z��[�רQ{Ry��D�$��ls9F�m�Ͳ��*
Sc��k1R���y``T2��?u���4u2"�@���o��ON�D�@R2�򊆪ݡU������F�Pl`Y����,C=�q����˔
����������}Hj�
L\�\L��S&��u��o�J�~��zZ�9?�3�Ҍ\m2ۜhh\�3<������G��á�o�a_5�!P)]!�3�0�d�u�NӷE{���&g�A�S=�������+��Z5k���I{����2H]�<"eb�	MfT���d�F߹�6@;��vVA�5�Y�k�NS��R��w5[�l[� z��PFqw�������𽵟�����|C��2+Ѵ�G��<m�.�5�u�J���j��,��Oh|��%�
 vP�����}7Y"����M��:�u�@q�^���靔��<�@��Q��y����F�:3G���W��w�uDG��ʜE������"g�[f�\��4ް|�Rbs����kհk����͔y��x�odY3?J��Jb�2���遴��Է��I�D0�@A��RB���:Ɨ��5�r9Z%�\���4G������On����$
��%�,X�W��$���m���戙*�2�N\�L�8b�1�-"U�3����x5    &��)���RRS������RW������c!5	 ����i�+��=-�fT�x�IC�#ېH��@4@�T�:5���Sj*P(y1I�v��Cǒ}��0�IM��ˇa���BD����УL n�6Α�F ��Bze!!�쟍���~:T�Hڅ��!_��4Я�H��KO݈�z�9�J���U=I{2`����,�Х��m{�����2�\;!˲D9Ъ��!Ū!$\����9Q�9T\�FQY+$�nvh�6.šƶx�t�f"���*[\�{Z��2tM���Ϲ�g�]�)6�R_���l��tV���v=��rv���ޞ��A=���df�幏c���a�ەh��M'�x�j*�&]�����t���ahɎn�j����#�n�뜿	5M��FհPW^���%Q���aF�/Q�8W6F��P��&<����z�6ᛟ��LF'm<�Th���-<�#�t�А��y����
g��[l)~:+��?�����9~S�;sQ�p�q���%ׁ=Oǩ��ۭ�L@u� ��0V1J�N#F�����u�BV���{Hg52������H�V�Q�'HK���|�61�N]u!Z�,r���ihA�D�/޼����k	-$G�i�Z�^���\���P$�`��������z�_! ���`��/-d@(��Oz�t��du'� �0|�����[����o�40�.���{/k�!�G瞦��@�l	i���T�~=3c���|�=!i(����.դ�>6m�SB���P5 �N�<�ԓ�Y޵���ek��sO��a Y�x���Ea51�u�u�<�����2�P+�t�molL�̔89��f��7^�S�<�`��6��-���]���Pb�Đ���ei��橆j��"�f0� ]�\�7���"ѷ�j����i�eP������4V����9~Y��XJ��z_�b#�h��
��� 5v�%�jr_O��d,�R���}?̈����l�,��H]�G_@�S����t�a�8���Ɠ@��(�Uq��)�����t2\{��ݼ�(Y�6$�]���W���ۮ1��7�⻍�O79w�pg?j�,z]�T[���޴�-�(/�"�Z\kƟ�f�G�P��p#�,<�4g K�	���5z�ބ���q3�Zpd��ۤ��y�L�zf�٫��o�n3I��2g�E���_�	Dt�X�=uVy��s���Z<�
�t�?/}�("?p(���Ҽ�D-B��$A�#�����g1��Kן�l��t*X��5�,u�G:�"/I��[}=t���U8�Ɩ40�b�!�+��<R^��Q��VŦ�294����2�KFR�Q�Mr��GA?��OHi�s�y�)=�I)���x�����B
N�02��Bh^Quc5��<��B�	nTumI�ի�F�F��<f\y=(i��w���̴��D��������+���Cb���Wj�1-7k@6��m���� ��,z{�z{�Z�$gƌ�	
~��<7v��P�3�O��b��w�s�3���k��r�M�� ������?���6���`>!��8C���'���Vґ��%!V0G���^5�F3ƺ>����ŤAJd���h��LM�y�%qQ�AUw�%��
��g+I��x�)��|�;kT
U����S<� i���U�-:�C���}���/�5�c�Q2��y�A������?L��s�@�S�8�jj6�VHY�������h��k�)ꭇ�7fVF��ؤ��-�F����S�J�ٙ�v�������A�0�\���<�J�Pp_%d�B�j˯&�n�c�"(��.��Ki�����S���z�y�o���90��Te��P*�+V���Z(Ex΢O88�h���$#��Y���,���(��R��f<��ae�����xoy�o���!Q��C���8�١�0����2!5�V��$�[�w�ex���fR��r��I(l&�K|�����9x��9d��Xş S�8�{]�'���ih^*�����B_)6?��s�Y�xHX�Pɋ	�ۇ�9�3#߭�(^�8y�T�Y�r�
�}�e�\*�ʌ�M?�����7�+�)|�"Ǧd	��<�(����(~���3��m9 J�o�h��(�*Զ�E޹ױt�g� ���A�h�w:ߔ_��n���`�u�5	�� �`[���,N\q��C����hF1<�v��af��׈���ǋ/ T[>�N�x�"N���!t��k��O��)�F���B�6�=��m�wJCuROl��p��soO[���<��)sl?����򗡊�D{���`"5˓�&u���~�U�_I1���" L�%�T�����k��H��!	�᥈�~{�G��~�h��-Zy]��q8Mb:�C�]d(�/�}�5�9�����@E&�3�;\�@lE��dm\��w]�~B��y]�ӷ�r��\+e=m_&�);��1G��� �"��}����zkP4��5�?'g؜��
vb����b�r�['y(ж���4�L��� ���vh��X)|9�R�M���y��� ��]�ѹa�1
ȉ理��A�y��*)!�R>�\�TGJv�).l��ō���[a$��$( =lN��h^�R�{	!�(fT?�i�RW��J2�E��c|?�q6'��<����d7Ip��]��l\��
�I�k��{��Y@Ɠ��>�*8((9��B	�c�G����vJ����`=kW:�"B��xD�gDCm���0z�`oF�ԛ�JlO
@-�#�C�-.C)�"A�U��(ԝ]Db�x5$?fR � �ip}��NA���}W悲p�Ӥ"J�O�E�O�gķM����D����̣ϕ±�_����jКKu�qC�{B"
�9*ޭ4�=�֐!���?nOh����BY�#�$0D�A�R��}-w�eeI�ۋK�M�Ȏk&��U{�ԕ�H�H������E��F�'�Ci���IK��Y+ʦ��`��N:1pѶ{Ee��"zVI�	�X(oE��r�xVc���!k��"�wE������q�`��3lj[<X�j�� 	���7]�����OJt�C���+��p��+|��(fD	�<���Ӥ�!O�fb/4E�,x��K'�b���}V[��F-�!�����\N[�ymq�#��Ygu�]�[LA&i�tQ+�nz^�2��/n^�z�>Vaj/���e�(��)��^yP:|��_G%|����}���9eB�Y�n��޶�/T|`}�4_�U?�G[���9ǣ>I�Z��4�v��W�j��g)��.�El��*&��]mX��(RT��±�;�X�⺿@\�h�By�Z+=�
��f��M0OG�H�%a��P��U���]A`�%��~�6��c����ߺ=?�3���Weid4_1����i�@[P0�WJ3�����:P�7 E˔��1Z>�����7iz'Xa7� d�3=�g@�4��m���WSC]ta��H]K8t<��ћ���T����kc{������C~���^�$mph��}��^�)�<�L�hc`_<֝E��|އ�7���ժ��z�{��d��#�)Hw��)�mR^bK��iݐ�7����X�-���ɛ�E<(N���kS�B���~~q�b�Dy����Nd�)<C.�2\�I5��8�Y	qQ�e�~Y�L��CWD��4����Un�~��˄��R�Nw��Ryn&��� /�����|'?�u�*�밷�e�W�#!�#�����t�kq�n[�*�A���D<�E(u�aϱ�Z���R�F��\���k�{?l'$����x����6�
�����l��8/����0»���Rzl��Ȉ�B��"�ֶ����׀@��t�j�ۻ��,�cA���X@�rR#V�jZn����#����t:��vK���>N�OQ����kl1��W7rā*P�����}��!Ǔ�%�( �*H�u���ن��Ǎ#�P�Pr�x�F�pm3_�����x�8ps��=h?P�� �t���չ_���� 	  ��=1j-��i�s���X�I�J��H��W���CѠY. ���EJN���PL-d��6;�a�Z�S�\�֙x��Y:w*�E%��Z(���lI���*��E�j���Ю�}��B#Ϧ�#y��I��.�kG�V�(�hm��y����W��'
U���2�k�8�m��D/�ǒ�%��my#��:X�F��sW��dƈ���#R�JYj����D1FP��)	+J��V��	�@�y�(�	�h��@�`a�M;���e&���'Q���Kn��_�o=T���3�.I���ډ�!�v���ǳ��4�(�*�̛�d��4��Wuz������ӱ�S�}�nk;3k����"@[8B��[K,0aDS����C����c���
o�n���c��i�_'��R�r�3&9mP^.��M��j2Y���_ٽh���&x�w]p�x�-m.\3�ɣ����O�.����l"�ƅ�P:�u�	�ˮޜ�#WF�,�U��3�b�1�p�˽�k�,D}j�\��]NIF��+Y���U*���ƺQ�P�B�_�Ly�Púi�s�&u"!T�C9_��`����O@��pQ��A�{�N�ܴ�yuj�8��..QF��3�a�1�s���� P����+��� ��~�aв��"�t.�Ϩ�&�C>�oF�o*��6�Ne��}5�v�0�*2	��2�.Џ��X%�vY���+AH��)���'ݬ����'2�L�1$S�ΈU������`�D�F,$�RH$�Tjfx�_�lI$/92���� ��e�z��i o'������.:?o�c=Ġ�ո�(��ǥ��XK	z�%#��������/�|�f�w%�8�	�n��g���,�^B
x����<m�����<�$dF ���[�DU�(��
=d+�vI8���bJ�?���{�J�����n�K&i����C�sŷ��B,��	8=V��gg*��{R} ��LG�;�6�Z7|<�w�q��G}�A]3:aؗ>$Ոd�������)�xcC�5��ӟ#q12)#]�w�]߷��	��t3 �o@jH$�2����8�jL���$a21�b���[����b�Y&'�(;��v��46����L�Fц~����#	��e�F5�h1\Cޕ$;K����p_u�US$D��d�M�_��H��p��3Q�h�a��О�1��-�BA��#��Tҷm5C�\���АI��f1^��z^0+����$p+ʔ㕿���3<���9�����[v�����W9H���Q��B4&��j�I��7����Z�6`6E��%��ǝ݊3�0���DyV�-^5�}��w	: ��/B�վ����"���kf[�D������,��y� ����e)���-Q��̓V�ySW��E,Uz�擧u��ML�z<VP��5<��h�)w-Q�ߒA��)i-y��3=�4�Ґ65���X��
�U��F��W?Α�k��gNotCV[l1-%[�7�}UO+K����N�Գ���M=��r�j���dꉧ���4>U��B69�]�����f�a/z�����BfYd{X 8
���y�[�W��O�\y��ߋ��3�1���*XGȬ�� �Ռ�?�"���H�K����j3��]7Uwte%��M�Lg�וkթ�<Ccq$3��:�۝Z������Թ���y��d�=1��1)�<�>�T��-ٖ�&��W�ߤF��-����;���wժ4�]OI��"��$s�Z� �t^��~8.w���`I��$�,���XҰ�d-JE|�������i��o���)��䅹K��5.]p��R*�f����{L��D�ʜk��%5�'5>�^�ꝉ��~T�iu�=]D�/ N��e��1��ܞ�֦��:d�,�$�� M��j9f���� �l��q ��,_���Rk�)�O�du�QJ��Q�z����.����W>�0#k>#���)ِk%�E�u�yS�ANyt{:�pr8H�[��
��!	�Yˢ��S_�3�eI�)2��E]���d�9�̃��'��~�[�Uk�>'}�7����}�R�����L�)%}���X�>g�>��*q��T+�0��J#��h �2�^��ה"o�����\cg���-�C:�ĸ�=ů�jG��/��c���Y�M5n����d [I�il���"ߙc�e��	���ff���@�^%&g �nk��B#\}Y3HC�������#�"��'DA�԰d::7//�QK��'b���	��~� �\�      �   (   x�3�4�4�4202�50�52���2�4�����qqq �]Q      �   y   x�%̽
�0�����'S��XZ���]\Bz�&��T���ǡUsb�n~K��	��s����i�0���{�_
�.E�q*)�j��t��n�IJKt����5�d�l|�I~[=%       �      x�t���F�-��)�=@�� N�WK�,ٲl]m�}��F �@�&��1��~�/W�Llu��UY9��ϼ(��2o�����W����S[[�k,>h�|�e~��ؕ���X����f����a����������
>���߇�vm�Û�6��3��ɜ��~Y}�>�����6�v��s~���y��5����[U?�-�I��JI�h��i\���?Xo��]O�a�Ք�ɂϦJL���𐅫~xsk�+5f-��Ֆ������jS]�wu�f�n�aכ�������_�`��>�O��ןk۴�I���y�O�j�� t�_
�W������q郦N�}����M�ȧ��թ~�����7�p���_������u��@���6����-W�|�p��|4�>�f��J��w?|��)mw�߳���i�=o�m�V�|�ݼ�)xgڬ�?kW�V�ޛ���ۃ����?3ז&�����f�m/Pl�^�k���������~��g[ǹ'*� �
���+}�%0���s�������]�Wm��4��9~[��q��ǯ�F�����O�����}7�ۺ�-�����!\�𾾸:��n��fzW�N,���x#(v�����j�������?~�b�k������k�I�[�=WU���]�b�0��ֆ��6�W�-�p��Δ�������l�S�=�w�j�U#ޜ�y|����GS嗜�v���?�#�u����]�Ѽ��n?�k�������G�ZDp���(�I�O�?��n����t3Ykl���[���^�c%�?7�탧8+s��z���XԌ�ؿ���e7�m��O��?�[��1�#�[W���4y���f3#���.��rmZ卩�&�]�w~k0u�ק�S�"�і7�p�E��g@Q2B�.�{�[i��V�ٿ�6�� Yo��'t^�aofH��ؚ����'O�?��+�O���"x*��VͰ�H�������M��*O
�j��x����Wl�7�I\�Εğ���� ����צ�K��>����|��m��5��G���s����E����tLy�сW�>���'#7�����9�ϛ��/R�PTzH,.�n֋����E���Em��I��W�s������PD嵽;b���wG����^�K�5����M���W@d< ��$�J\j�dz�����_r|�x6E��xY�=����={��+����N�j�O&��+��aS^Pt!y��V��\-��@����F\�͉n��b�$_LK:�|������Mm[s�m\��@<�<�튞��^�{���sy"��JB$��]ITX�!^��oq�q.�u� Ž튴�+���= �9�Ӣ;�vd�x�R_ܐ�ؾ䤅��|��AQ$$�=��k�bHĿ�y9r��N�K�m�*���nfbJ�U�D�œ�D,��Q&�œ�n����OW�D��������ŦD�u���abs�lVb����t��SW��l��v��u�'�����Ω�^�N?�*Y_��ﵜ�Fc9JiY�8�}m�i;}����yC��}��Mܸ)s�փ�@��K��ō5�3��#��+��݉Ը�<����^�.X��l��R۲��1���q
�`�{R�l�4��ǲ�i��=q5#Rhc!�5�1���+2[v���
$��L]i���z�<��գ���kO�!xz�tFI�5����jw��GC���'��VR)�_3G��5u�"��z��������L�Zү��p|��\��q̽6)޾zb�F��� 2HM}'IJf,H��#H8�oyK��6o�.�$�b=:����#x�s�x}���L�Oy��<0�G�%�Ƞp��Þ!X�d<!��.-L�똄���H3�8ZI�@c���Q(ZkeV���'G�o�:-�/X��X�췫��I*w��㵐��L	��ξ����<���2�#�b���-&�|�Dv"qL,xk��{(�p��>ܹ�gp��7=BPl��[O�W �>tq9�ef��G��%�˸KI ��V
u�< ;�l�-��W�
gC:�$��0*&P���6�c�'�ێ�ڂ$vP2�d��B(	gh=z�ږ֖f<��#�2�d>?��~5�uc�B�H�xD^5RN*�X��f2JJ�ޅ,��}�<���(S�<k:�:뉼�^;R�,i��j'`&/ j=�P]�V��f��~�=Q��O�i��v+l۪P�~@%[omq��u�W&#jl�{���݁����#���05���^���/�|�+G�]��1������Z���3f4���s&��\w&-b��ʒ�ND�6�ۚ������!�"=$MKO��g28\^L}T|b��'�lLx�T���4\3]H�)(�daN�3�2'E��u�{�)���X052,ʧM ��9F�|T��~���k2�Y��1D̐ؕ�2q�kmn��U�~�%Z��~u0432率�/2�Q!@��s��H]�w^��K>��M�t��:mt�F�[p6�0��t�{��;�P��M|�Zs������"q�IʱN�x�`�]^��>��tUNb��.Z�^�k�ܞO�� j��'>wI�L �ͫ�<O_���@l���#���	�N���KƢ��I���9%��=,Y7��)�r���)�[Gj�l�156#��m3�J;�l�5w�������8����	��ЎG�ºx5b$�I������γ%�6Vd��w�au�)�wX'��ŶYC�����Mle�̳Ú^2Yׅk_��{�ڐy=�+b�������]n�*ɧܐb�4��SZǙ�( �ux�]�4�<m{R���~*��@C���d��S"�2�D',���_Ǥ�'D�p�	P�HH'R�t���2IH��u.#�P���冸�ɲ_�Owt��(�G���������>��R�:�o�9I��k�]XU�;�Z�#���Á^WM�m�M��y�� )g���D��W�f�"d�=�4��Ѥ�2�{ȫGZ��zDJ���d�K@:��*%�3]����TydD]3�Die�j�jX]Vq\�\�[LD����h�����s7"��f�jt��'�p\��ҷ$��	���	{�N�Ü������;���-ܲ��d��!b�RR2�]������_h��qK���@�լ��LPt �4�k��gS=Fy�fP�{扻D��+oY=�8�}2�T�9uv+����Mt�J����y���<=�ɛy��~ ���\�tǭ�$H���+%�B���LnZ�rt�eɖSGv\��m�6�;��������μ�R�N��,�+�	?R�W|�`&J�P�zH�pK��55)���El��}]�UnH�i��T-�4�$�f �K����!�m�#em'��I9Npy�ď��i֖���l^E�����6K�����<��2��&���cG�'��'��w6`��$ʺ������jN��Ǉ�+0ֺ$EL�ʄ⫌��I5+k�Uo�e9)��8|g�Q�Hk�׎~U���!履ۙ�=��ѷ:����!]o��i�
�����4I_��T��t�Ĝv�gCtj��ʳ�k��\z(�<��Jg�eG�Oe9�6jO{��mK{���邾F�F�m�[Z��8���&�C�%e�Ȳ"���cQ:`b�du���F�L
��O8M�Y�f$�&9�匇�����]�[�c�q�� Iׄ�pvr��Q�e�C�P��|�'
ο^�H����x|w{/���hQ��؞��
=y��Zsn�|��4v�("�|�w)qe��H�̍�֛�ɞ9>�5�v2+��y����e�ʳ�RU��=-�c|�|(�3�B��f`�t �$N[�=�N��p^���)���-ls��A�D��!���Z�R�"��n����j��#h�a�'��������%a���{�r�}�05n)$TZ�RcA� $I/P;p�x��-"ܫ�IC��[� �8��k��H�&>���qi�t�Ce��W��G�6�6�H2˺F��F�T�g�HGӫ�����Ne���ڝa�ы�B��K�d��@    G,͹+&�WSkbA$q��A�I �K^{����Pפ~�#�;R��e�a�W�h�j��T����R����gjI�=O.��rͯ�DC2o��O�b�83q�R��v�mN,�<]�E6Q�S�<I���ε�J=5��c�5	I�ڤ�V�^<s�>Þ��Wz?������[�\�-�d����#_Q�XȖK��,�����=AT^_h~�l齞G~b�T��?W)�/)̦d��0���A��$d(��|��6G�k8o�y&��t͋5�)u�Q��JmǾ4]kJd��S�s�������}RvU�8�;� �F��_���8�����N���❞�w��Z�é8�|��#�)��;4ݹ7me�)#b)�6dI��fWk��cF���l[�(�&�O�����IuF\.7�K2����!�V<rĆ�%������f�݉%~*sz!�p�MtŲ�5�yyE�Ϡ�������UC/�$sV��l����	�m�f5�ԭ��kO�"	7>����xY>�#�r��WeLK��!�q�<���	�~ fӋ|f��me��~Xo80O���\h�r�����Z�>���A��,J�lt���ӣ��X�����;�X��� �~��7��M��*m�﮹��2�0�@��צ�4�.5��
5؜�_,��O�b��|X�05��������#q�)�#ޮ����m��9�F	V���61��eXH�`�AT��6=5]�X��n={L�EL��>��b<���:�s�j��Û��Ql��- ���B��ŀ���D��bd�-Y����9�K�Iv0�|x$J�H�Њ��>&��iM91���1.�9�i��#����qIDi�"�Go�c�.���>_�H���K��s}�e�ΰ�o^S����M��;	%(w���{o������`�=@�2�#5�k�ܞ�fP�$̃Z���Ɲ�ʕ_���d����Ò`+�*��^�|�t��+ )R�w���$�}��j�z{�T���� y`p�5�\=N���ps���{U��Z6����i��������6����ez~,˝��F��t���p|�&�G�qu;C�Gf���#�,mk���1�c�j~n�n3d�:�(,dc�^��p�v6y��1��J���ްM,�I\=���0;'H���.!㴇]=3Z8_��ϧ2�{[\�^���3�S�Ld=$Wi��%C9V�)i�pΒ�Or�tZ�a0���ؿC��7���=i5�t��4���۞�jI�Ky�<aQL��&GFmO6�_��9�2j�C��ܑ!L:�z�֣�uD��;K6����C.�fҞ����L��v�"T^b jP�)���7��G��s!��C��{i��sD�;v;�;WL�R��ю�H6�L���n�voGz0��"��/W�r-�s��i=�nv��MU���Ź��7x�1N/]|�K�.�qPMYz�R��P��Ǡ��}���ʐ(��Ȏ諘J�2�ĽSjɌw[R���J�GM4ش&���g,:����L�����]��'����v!]��B��<l��GU5E���/([�~$l� ��E�4��v���>�/�C�����	\�>��:M����j9��#�ӜR%=khi�r�'I��wu;����?���#s�(���"�hk F�j�5ea3s/�F�6��;z�����Oqg���#��PL$aB<���c�����݉U��_����g$G~鞡
N�����?\�'��ՙ�#+�1i�ݙ�|.@��G�Bm�>#�����U���)�*ϛ�N��M�%W�o�of�O]�u�-�����Н��B��m�7���z�� ������y�Y`:�&e@�Z%p��du��Ef�����gz٤�~�j{�3����pc��!�>����������H��pp��s��v>����Cf�����ZJh�O֤C1�xB5#d�3"�(�C�xE�l-��2-c�'M��Е��կ��j Ț��?O��r&���H'����8��U9�K����1���������06IѴG9c�.Χ6/�ʲ�=5�(�����b4���B}އ1q���'���p��?��u@Ǎa�b�Y�X(�֐em>�e���;�/"3�}Y�z��apؐ-�>��h*12��A�	9Ǜ^���x��M�D^"3�����_���̈r[�ޜ�ω���G�}�9�w-j��� �]����B7�r��l��aG*W�7����Js)�����s�
��2�Q�m��<Е���O�x�ѿ�#хE�/���K�����ۮ����Od�]-{�Չ{��{���D��J��&K�3;7�����3��U�l<��DH�0��ƶ"�1�Y[Y88��ߐș��������w+�2H���p�WH��gA�_�*\�x$j��Eӫ���S�C�E�(TuȾ���n+�d�b3>@�1}@�ksF)2`[���9b��x���I�U�g���[e9����k���?�K,kC���F������@t��/�)��2hB6���I'����\��w%¿w//� �.a����\�奻����^��;b�5��?��t�S��z(�c<�θʾ�gN�ʯp��c�/�T?c���l�'����<{0��dlHE4��8E.�W7�su<0͒�����i��H�	���ug
�0��/`�x�#�&�?9��j|�>��Xt1����&w59=:q�E�����1��U�TY�^7�ȊgHGU��+*c'��a�&�>�P┰}m����z��¶N���5;�$�����ޗ��N�Ua5�����T� ��q�[�N�a���i�+l���Jl�D��K�07K��B�ޮP:�iKdq��[_�v��P0��!��`SXF�}+&�n���SHv{��WN=�Y�}�tu�X$!T��Ж��-��K�!U�R�\s̋�J��hڣ�*RD+�%3 =�URi�6OP�<gH+��¡�����1��#$Gݫ��*�-�c���4e��$�,_�7�5��)]2��`U�
��Ή�ݽ6��3�����n�{g�|@u����nVc��g��l��̗/p�R��[���8�8.S�h-���Ȋ�%ܙ��@��#�d(�N��������Eb�����l�ĩʙx���IV���W���l��}�a�f���d��G�HYe�L�T�*)�qI:A3V�sE�4�7+����0d��\��ƀ|��v��aSV6�I��.���WX\Ŧ�U�{�!�-@*��k�Z��Ɋ��EK�<-:3'}�T�D#:相>�_��|J1Ҧ�fE��&dk�I�sFF����ERw�E����:�NUY#��Y�Հ`E0�9g:���jv�.*O6+�2K:���0�K3 ��"N_�^Rj�k�-�Г}�9�/�q&��?ok��2����D�Sﺆ���"T3�������"T��5��>&�x� �iC�b$BEAJ��/G�B��Z�L�R/6kk���)d���U��L �g �C+�W_L;�i�NR�l���ִ�"�V��E)nkΤ#��]֦�f���+�웭�|��b�w��	S���u��	r��|�}�9/�g�Er�)[ޅ4��m@���vkJ!�.l5GZ������4Y�r��� @��.#;��Ѻ���%�5a� �!�pvO!7@Q3@�?E��i�}l���S06�+��
���f)��K��e�E����kG�'t)i6��}���ud ����!ic�Yk�	�4��F���f6뱪��^z@X�:�R�%^keUǆUTyF���p���׹Ng�ނ#�`D��+�R��H)j��x�l�o���R�{i��@b��29F�	��f6GU�d�/����3\Ts>��HD�Qj^e"��<WF(	+��vt{�3|t�����ף��`��eȣ��t� �'�8��w��O{,�l���}�K&y<}�Bg���	��L��Ԑ85������&F��˘7����F�1��9:Ē=�Q��=�"���,�pY�ٜ�k��y3�⛒1�/^���Nݢ�\&ʟ����ss�zQ����,�DG�5���    ���:xG�������lZEI��eIV]�X,��n7�v�u�H5�N"�gag�]r�f���9�"\n��6x�.a��<�bY����ĳ��rx��te�l�!J"XE��&s�Fg�&E�e@�w4wG��2�NSi;G�����ҫ�r��T��CQÐ<}�]yCw��1qìT^��Xb��̹��z���D��1��ln411�p��$��p�� �3�!U�C:�J���]��K&��H?5�!��������I�Bu0'�N��p�c�lO��PS�Ŀots����Y�`�zPJ��#�r�g��8�褃:�]�ϻ{z�v�u�q�tiZ�W�OI�&\#)� ��q7��������z��E��Ř���	�~�t?�Q�#�p.C���Kztn��ss6�ǐ	j�ǔ��w>F&(����Gm�=q�����n1_B��˦Cѕe|��*��P��p�|�������/n #�A������c>�X���8��U��n>�X\�s��� UB+������ƭ��z����5�WJލlqR�*�	[N�1��@� �d&:��a ^<�h�%$`�cz�6�Bd��C��*�����:A}&(�01?�Ud�+�t��I�d����UƢ�}�V'`����]�;7�5G��1����!@^�k�gM_��9���2�ҽ��"_��!�:��,���2�ߤ
�!n�a�j�g��L����1- S�k�W;{��L��:je�|�\1��Z{Q3@$�EK.ҵ��:9�8g[��V�t=D�j��;x�}!	:Q��Il�AQ�u��f����t����N���)�tH��}�*f�dz�/h"�y5�uэ��A�[76��o������f�_�S>om2��₦tt�L��U�It��nh{�L���p(�Dw�C���A�nl��6�m^���+zkg�� fC�Z˲$�O���:��A��U�td߬=zßqRf|y�7��;�U�Z�-�hm�h,�#i!���I[���@�6i�n�b�G��ך�;�߲��#c�-Z��4��T�VF��r��&s|�l>�هc��yةdPFϮH�D/�\��蠥^�.x��$$>�Ej&��7�@R�e5�F�ݹoDCY}����~;_Hw��J��4|�<��:Nf�)����	���_��U�I,�Nث�?�R_�6O��T6k��w}�@�xG�D�o�zn��;��KL�JS�s'兞��xb��e�D�>c�TZ��o3#�DS��V�l���*��QXoz�:��d����Tu�!�X��|o�_{����B={,*L�B]_���d�e�ss��Zdz�>��
�����7�\k,Hm!�t�9l�ŀ~��S㬫�)�	���	��S�M�^Չp��c���XK��]W�� 3׋���C� �;Wf��[p����u�Db��;�8�a ��#\BL;���]�����=Q���?}Ѵ��^zf(z�2ۦ�_����Wʭ�jv �H
\O\���-��rt�UFݕ������7o��-�l	n�7͒?� j	���N����w����=?ӅyoR�mE�ּ��6�6�^�	3g��u|5�D�����K���z��,^�3״a�Z��"ӷ��W{0���:�Ƣ3��QoT£��#�	�S/�G�� ��ו�&�i�ڍq�ò�vsDH�v�"�NǠ�F�RYB����S1�����u-{#Q�7�F���N�_?d3մ�^u�>��==��o�#A��y��<`*&Er���d��u?;t~s����'����=�?���[HE�U�M�t��>��M��n�Fr<oBÖ�&�n֝�dr�r��Fm|�7X�ܝ�K^�nJ@b����1�|��*���>S�Jߢ-��x".��.xk�e�e����y��9;��4Q��� '�������C�+�Q���F���\J������RT�jA�e���Qt���|�1$p�£pz�E�
�����ٷ7[�SaH{�ε9#FR�y��W*�i�/���f����	�#R��Р�`���CVw�D�jW!��l9�+x@����3�d�z��)�������Q�.FҤdV5�9y@ꪴg�9b����"�=�s)
z�iH�KȺB1���Eˡ�lS���nN8V8#����\W��*F�X��
�����N���H��\��'�� =�D�}�������Ku�?q�u��=f�a *С8��r*��.ӷ+�������V�ې�~]��������.�ܮִi��-ZKM,����os�*E�Gc�$X#�E�j�w�
�Ǥ�6¹4ָ4�!ͣ��z,�=-S��-YE%���L+:�U����;]�IO%-�t�$���:�1�.�h��v�E�uQ6 :�D�8B�,����W;p b)�t�vS���D-yGn7�[c�,\��Q&� �*�xF�hJ��,��,L5�����zGPu�@�;��*��A�1ՅS3W�@����j��m�B�/�+�4�f*�Ʒ�qh{�¹#?�A�R�D��NI�L(�"z�邛-��7=���$*���M�bKzQW��p�5Cr�-�l=��V�!x_�GH��N��O�b.���7�F�T�3��";�NqM__7�t}��M�l�3��"��S*���LS� �CZ���{�Eɀ�X=i,Q٘�8���0�DL�>��&��ΣQ6�K��F�aO?��cB�|&�d�G���"�!Z�6E!gDj'ItT��v�;_����U��3#�D9�Hd��֌�Jrn׸r}e��qо9/
����J~yn�w	����`��H$]q_%;W������]TZtU��X-���΁��s|{�~Ȁ}���_�Y�թ��͊���
����&�Dh!��R}�E٬}W�O�K�s_ၶ0W��H�L]}��03UI7�v��[�9�=tUG �2��4sd�O>��r��v�>���M>y˼��h=jy]y��&h+�g¦�F�vbNG�cw�t̿v�(�U��|钳�>�m��f������e���Ch�V�j�^ڶA������F�n�����Zi%xzăK^�Ԅ��2��^���gs�gGDe��rv$}�:zs�^�s���?��~F�$�&;+�:3����F|�Y?� !�{��x�\J9���fY�F�D�Bf�"%�!:{�'߮��j)�u��i���x��e SǬ�>V.��-\,q�� D���^u� H�A}/."R�32�SR�v<�Q/KGϙ��Tòf@#3��V��q�}�h�}��vT���٨q��6�.҉(�R�_d�,O����#�ݒ�3y�"�w�tPP���Ճ�<��:�G\Wy��F�Z�o��Å"��j&�\V-t�
e`�.�l�m�lp�p�g�F�+�Q��#���p���Ws���^�`+w���u��H�dc﮲�Gu��}���n�G������B�F*X��ʸ��ͻ]�i�nO��1�o$ٗEK��ї��~k�b�4yϩ��!I:(d{�T����r��<]&TE�ݕKU���FX��H��������'W��߉�#QÈv~�A�i�X���c�6>Ѥ�Y�H�T\�0�S�;��j��t��ç�}Kz �5�\�����G�1�ǌu��e��2�!�5ޱ�@�w�n`�#��9Z�hV�wܛ�����4| :��PsMŝ���>���}�_������+�:��>��̕B�U�xr3j�����`d3J�=�L����,�5��5�H��S���
_����4���;Z�����q�P?�sů\�9�D|Q� F� *�����O|��$?L��;g��I�y���0��kS�������w2�D>�b�h�ӡ8��I��4�B(��.-��$YJ��M���A��E�����Cd������Ï�n���A9=�VM��m��������e3�]CmÑ�`e����a��垨s;���݅||\2E��|y#|T�c��=\�1I��_p�*m����#|t���Pd<$w�4���	ig�� ��n��x^Ӭ�8�%�1b��F5R    n�d��FB�����B$��$ɢ!�$��xb0[s�l�zK��*�J�Ǚ-Ze衽Pt�e����f74'���x��\�3#ܣj�=.�ypČ�ң���0@"���¨�#ϴ�:�[��Y������ �"�ݱ;��U�����~�m �i�}1{��S4Z��+�4i�Hs�4�%�DB�O�j���� �r�_Ym9ƹ�G[�ո��~ˏk��V:��` ��ۦ&��zڵf����a�}v/���D% I��+����v�I��l���&�Ĕ��M�wC+[�?B��[;wG����O����n�|��P������bD���v�[�����a|5����� ]����7�j��G��l�H0E���r���a�;���I��c��{�@���@Uf�q��Zȍ�t�3+)Z��zT����q���̙�u�F����D���/5��x(╻5��mxx9@��]Y�Xt��E���X�<`Z�`�*�#F�m����;x�bt���yYtv{1�l�^�͇m𯊮c�W*ᶫ�������E�MV�n�=��Z�{��yq���x{H��T���Z�Y۟�|f'-J;���s��ȇ�N']$Ts�?a����s��?M%��O�ϸI�1�/�y��>G]M�=����G����.<�P[��$����9Ҿ��|@(�ja�|5M�g���t rs�
G��^M!,}6�i,4=���8��gB��[�S�Ӡ�ZP�>���G/,��D���E�π�v��Ȳ"��qsDf�>���v��\�-��Ű����#W,�	|���A_����x��gS��QC�*�qH:EM����O�4�e��s�qsu7��t'�;g��Q9ms�b���-�3ȏa�3��lb��|�9v-���� ��vͅ�QE%�;_\ˉ�d����@v���N���dB.�i�JΠw��	���E8D�h9���AH&I3�^����0Dx��3�Km�\G,z0���>{��9��k/�fz<¸L�E�D�������yD	��!͑�m�[������A�U��+��^���.-���"���2fz�_����Y%�}�_�\LI��F��YZ�%�s?�sYGed�eO��O���!��c0��Hu�B9�E��V���8�k[1��a�� �P@޶��쇣��yBc�>�~m>��{/�jH�;灳��:U,flO!ɴ6ìHL�ҕ�5�����b�i�Yk��(��[��`|���,%�F�m���`,��.�ħ=|�����퉁w���KȘ�'O���~7*-�ʹ:��i���C���*����]QnЈ�U�4&V�U�o��:�bL	syt���ĸ��9��|�mu��G�o�CG���{0jFp�yl2L��uCt8+\��[W�e�m���UWdGD��-
c�ܦ�tP�+�b�W���ک��CeD�E�H5���/�E���˂7� WsW������xHZ�	�/"�bR�"7,D��%l���S�~周bDnMlϢH�9) ��l�U�˻s1@p������aL��e�rQ��kmW�v>2��Y�ɔ�r��������-|`\�;j�zHx���I_�+���%�jx]
��!_~xX(�<=;��]f�r��JY���h��Kծ�����<�\�v����3cp�3���h�p
<�y�F����9������/#d�+bm�h��y<\Χ�-g�C��+m-ޱq�R#�,4�I�r��Vn�>XW�9{��2�:�4���Ju�4Okg�����5C4�q%:�"|�5q6R��G{!|�$ugqӑ�G�r��8-��B:�w��P�w���<�uH����)����@���ԯl*a\��ƅ~!��R�!u�ª�B�Pl�m�?c�k��?�V��̾1�g��j�"���7;�p��\e���."��x�C����d@)�������P��C��&���I5b�|���c�&��X��4���,�C̮���𮰘�A$���3(����Ⱦ?W�}LYZ/+p�����C��R��TX���,/h�[tvb�k=-0ܬ�F�[��f��q�P�;{P;h�̮�x�.�����*�����6�� #���8�j�*~��S��\���jODW �(�n�V��1��Ro���i�ϼ"s�U~ʛ���1%�\����X���?�Q��^����͹�ǡV�q9�Ew����8��n�[9�y���7��!�'Rs�y�c	��W�;�%��*�q����p�Gr��7���]�x=Bց��CO���9��o�_�fD�څ������-��aA���ps��h7U٩({�#��-er@��y5�6DS���e�0��'�*%�blf���B�خ�o�n�n�9�*i�����t��@8��lZ!0�mA*�Ђ���MyS���7I��V��m�B=;����ݰ���Ǥ�ֺ�e$zxDJa[��� ����P���p���D~hsq�Z@s"?��J�:<�ynM���z�%9�s���wz��uA�En��]c�Rvb������|���Q�,��n���#ƔS��Z�����9�vYIn�d�f�e��0�Զ���5=�M������=
l~��>���}yP^s ���ȝ�ؔ����-�]0�,��ɐ%3 E��dR�gv��֣�-g�y|ˑ�H�;���cS"����ѽYV���GM߹N��æ�_׆eݹx�����9�'�~]~#I�<mi���֚[�#謨�^tC�,}���PL��|&C��C��Up�n"3� ��<�~��3r��^�}F�w�#AV�V�\d��!�8�n\.wm�C���'ҕ�����&�p��+�GS_�o$�> z�[�t�k�A�ڱ��i�*�&7�KЪ�\伣�n��?g;Ձ�	�ꎇp�(.�3/�E�"����AJ)cfk�'���?�ʱ�P��������CW]�����9O���V1<��z!�}���0��GX}�Ð��R�sm���A�J0�V3ϼ�øm�D�;Y�&y���nt���&$�R�wkR��>�T�[�庮Y��uD��q��d�\�h/X�:#d�pK$��j�D�!qg��v�U�d��������*���RRv[���׳����Dg �	�=�����S��	������a�:���0�+�s7s��CR�^7 h�ݐͭlb�P�ڽE�TDq��e�u�~:24{���*��P�������1ƹ� ƣi;n�_s��w�M�4�+v�H8�EJ�s1��ͅ��2_2�!;�;~�኉ȽZ�ݾIQ4X�;�|���j�)��#xםm��==#�J!S�s��>kO��~�^͠���dQ���k� �}�:����^�	��G���V���w��?�����V�������70�����#[��@	�{�Н�M�ӲWG���AQp��2sS�h�s�L��!W��S��v�s%�c\s�?-��F%u^F���*�� ��Dݢ2ܓ�j-���a��K���KF�T�N+ie�Ƨ�,]����O�pϠ	���^�H	V���
!Z�Z�?p�y|��+1D�&�G0�yP�H�_��An�Uǜ�����i���u2wI�#��9^����KDZ��.}�
���g:0�~pEr���L(�G�tD��L�%)\�2�*�'=Gg���P�]��/�A��*q�:��GG���)�}n�J�U�׃;��AM��}t'p[X�G�q��*�U���H�2��C�*�O9�e�-<����U/}����n��g<����&��B��r1�UWʅ�8*.*��Z���?�t#,��k�7�nY`���;?,���e�����'}�I�蘍�ᇥ��y[M��s�}o�zv�yb�a@�r��`^�8֑Y+�u`���� T��9��f�᨝`
)�=w-R�.]�r�ix8oh��"U%���t^i�`t@p�2��w��/<�썎�U�NA������R1�4��1��g����р��&����t��gk1F����I͍l�|
����G?��o��_�Cte��̃Q=��r�    %���)���0H�9n|j���)�0(��R�T��xG�����m={;<n�+%=��q`!Q�l��!Ɂ08�0麌����1DZPaB3{�Յ!�Ah޼&7g4��G�e�lw\ɍ�7�,� Pd�����0�*�W���q?�!#�+�s��r�2e�f���F_����x ���轢%O-/�f�жH+����։�7N��P��tj���2�T�"?E%��U.�����
>��4ܾ_ #Q�mq7h[R�q7;�t�axZ�I@��i�^V=ZE��p��<H����H�P��i�*��CQ8�
���n+��I#�X,ں�2w�8s�����\�M�Pt��
��8���ة/�"w'<m�P8�ѵ��J|f� Gv�e����Z�`��P�^��OH~Z��=�T��k>��eD�*���7n>�//��]���js�-���ʧ���";`�v%þE�-�. �PN{�b����C��, �
�ef-�ŉ�Gr�Ϊ�߮ '��a�!Փ���	J8�b���Iy�OGJ�b���{�\PT R��7�~��yz�f�	Y���ߪ9J��Im�[�ߦa�7g>-����*��c̎9��[>��cʎ_W��1�*Ϧ[Tv�nE7�x�ll#4ґ]�j-T�	����
=�k�"���l".���h��ư��|�:(�C˜�x~�Rԣ(`Ͱe$�=����G�b]o�1�PS�a�c����/����,F���ı[�B��-4+��&6��7�A�V�ဴ3�]��[;��ͫ���j|�H<�צg�mĢ�}e���"�n��1An��?IC��W��1`R�$rAB������8{KJ��L0�"y��yFu�'��y揍z��`�V^���?����Ń
$z��ǋ�ڼ�Y�n��w�J����/9�SC���[��׊ ��[s��k��bW��+� ��ڮ� �F��ɗ�M��rjO��݃���Vx����	�w����Y��{�d��Fӗ<إ��A.�c�Џ�s�����q������3��ٌ)�l���dXV���񄚩�.�s���k�,s�X�Diв�O��"v����k_`Ji���t*!Q1"���2A��>2ٹ�vi���\�������v݄�#&�1���m/���Z<？�8ث���������+�����./x.�i������c1J���"��׵���-EѲ�2k?e���pw9+�g�z0jFP�+(D�;8N�9��׹��F��{����k{ �+��+w�2�l�.���8�
ѤN���ֈjhF�}�2�\芻尃݆g�}�>;R����(2$u"� ܹ6};��_%��<+R	XD�pQ���Cd1�ri�1��m;ݣ����:cKMOY-��@�*dH��3�d�ws�Ѣg�@�_���[mF5��1ھ�9���Ͳ�8wqRZ�f��wmHA����gFH?bDY�ŕ�Tsu�>Ob.Ԋ����̸4�)o�N�>�DF$�tq�_R����)�'2�Ѓ;���π֒P�2@:���/ܩ{2���R�mN�{��.�̨��T� �_�_.]C���`Pa�!�H����"��u"9�+�AR"�y�Lm{���v����^�W� ';��!gG�k��#q��;���'��v��/0��Y�9Ծ��~��\؛��a��l�-$�9��L$1'D�(�H������ګ���V�Ff�=���'D��A�C@�+��܏D7��mw��']ٴ�}CE݀Jݤ�}�L��$��+*Č+n ��ӮP�
v���i�p;̜��9�Yq��4O[��wf�C�M�,�(��l�p{��֐�d�������
��/Gi�h,S�������@��Kt��J�رr�,��U�8��]���L0´��`=U����^���O�b�x�y #��A98�?��vW�:4._p�A(\��u�7����$>��r�D���	U
}�@���<z��*<�w2��j��(&SE�µQ,\Efm�M������,ƀ��꺜Z1��$�Ñlq��=�G͍�8���^Xf����Ț�e�"���^֋Cޓ��-O��]�3�_<�ݫ��]��Ő��~�]HW�\�W�֑�+��<�����rgx�c������D����u��,�j�p���-��)���лu�9InWe�n�,M�G���mj���`.����v+h�~ޯʄ��̓~���|��]�-ȟ��˵��w�i
�r��u��BO�Qخ���e���6t�1w���,.�k�T#-�Ri�h�結Ԋ7�׎A����yb롸��/XW|�l.=�m<�&�|d��d0�/��ax�k��U|�T�����e���n�Pk_ؒrU��ZcَbP�AS9�P/��<C�o���T����tf�<V]�J�H8�t����]MqmH/4s��NK��!��㬚?{�S�/�=��<�� ���Ste��:<�l�F�ly2ڭ~U<U�z��
$��NHssPru������|�u�.��)������ۯ�ގ?��:��z�:;^<�|����}{u����k�-{2��n�[/��bh�١з���n�ѓݞn�Oi��%�˽�i�<����4�2�k�%����Ń��sg�Tɵ�=%�K.A�J�b�Z�>�{|{�բ���m�z@�U�h�p�z���w�T��q�����HT���dL���������=y$��}�;�$F��z@�>P�9M�X2/�>l2�C�_f{4G�G�6]�f����e�R�Lwl-<iJ*�C/=�f�W0��39�	�>��0�N"�d�'�/���&b��x���}�"9���T)������d�b��<H�f�xD2�s8ѕc�;�#\ޝ�Lۼ8uk�.֍c�E7�I����q�ʽ����u1��A+ZRC�Ҹ��Q���K�!)��� -� eq���`��-��@4��L��g��f�IC�J���J�G"f`��<7;��E�-n���?r��Y��u;��Iy
]�h�U��gE�����Qc��1��?,����ZbXU��U]�X�#�cU��K�N.���;u8��r�p�5����ѥ[�T���I��9��i��ۮ {���,��K�nU]���;�B/e�N�g��罕~[c���y��c�ҟ҉+��q5d��ر�w|ZVn}�I2 �ay�KD��aY��;���hr@��k.�6�b:Eu��~�y���~0�D_�C���̡
�S�/M�z��_E\�ʆ�-�v�m�y�Āf1h7�z��~��cw��QZ��p�~#����4�h��$��H��6}�բ����3ӤF�L�s��IIWb���FY��-�>�����$�g+Q����x}^��,@�
�C�F�)r6�yg�G5��CȈ�]��SM
�^$�?��w��o,y�e,�l�%�R�G��P�/���!-��52���05#��&��.�$�̬��+���%�)nF�Vc���0ى7b(�Y�X���+��sσ/0���#Y������d(�P&>	=�dw��(R��9��LM�h����2#����?�W�Wi��ڰ��D� ��,U7box8��,�ے�ČO:����<�i�S�eL)�p��ִ:S�x,�L9���Vv<*D:����.x�n�~�k��e B��o��ޛn
�.�7�N{x���~ &*�C�@�t@T(��E���dR������4:��gBj�A����VE*�M�P���NG.����T|U��2E�R�5��}Ɖw.�B�=����4��\I]x�OƀL��_аw�v�cA�@��U�	~�ݤ��d��֤&��d�Lm��t��5z�:�s��^o<?�PM����A��1Q�hޭ�l�7l�g��oF�_WD����/ss�U�8FZ`{��6xS��0SOu���s�ð.آڃ���L����4~!)a1��	�u���ƴ;���|B ���
n���0���3^��"ǘ�45����5��������l���:l-l���/'0�J#��,ے���5z���I~�!    xs>���h�F�jOc���OO�6Z�%��l�%�(�>�І"�O�<�3Fh��o�F/3��eg���_е�ֆ���W����������|Dyp�>�W��̳w�ιZ{����6E˒��Zwq�5�(�@)jZ�������YK�=�ۯ�o�m�<;��=5@䣻g�Mv�v�`[o���_�,T6	�J�xY;�6�J�4I�ٯ1ݸK��&�w�|�btY辗�s�w˴��:�TΊ���ͪ�Վ� G��Q��.E�4�S�k��<j��0�0���+ ���e�cD��M���b����U�
I��G͌/�A/q������ő���q̤�dyu1�J� iyP��Ty����<�|S�P~��w�A�[%��YzUů�*��4sw�u�����Pߐ
V�X>��P�!+�l�g΀�=���j��/�msYx:f61L
�K�G�i޶�F���m�N%_�f�IB\��T�F�!j�u���fbk+1�l��7�g(��)8�6��1��yĵFHjP����fE�M�e0p�٢bˤy������U|Pi �ҋA)B��eH�� �r�(��k�ߠ~�%9wzKT�ӹ�[������E��R�6;6��EʋV��5х�X��a�ON5��k�ٓ~�|�'�u^��0���(���=��q/�CI�C����/�9+��Ͼt����\8?��-�H��#�)z�I7����#RgL�bQt���!���=�W��OÌ�_�J�-�����#�������<�m:JKs�]���$ʴ�ט��h�.|�-O�(��I�ҳ���u�f��@|N������ND�<�[g�﷛��>�Q���2w�H���(�d0*��rq�">ƻP��� "�9���f������ *}���~�s,��+�$`m̕uO�¶/:3>�X��&��7��}H��S�O/�h�1m��l�	B;|i�UkPmK������v��.6Oq���!;�]5P����30D�el���@�eb���~E�J9b*�:j$'���Ӓ���=�r!�#��Y�q�ͼ*�77.C�y�R�ܞH.X�z�ap�2���:F�9�gb��>O������}���2�
���=�b"��]ۉ�/�Pt�$�3/Jͭ���ds2�U�"�ڹk�ܬ^?�&���#���*�3Zr �� T��Y�{�'��,�Cv�4-4DҶ�XR�`�xP�*'ZOHi$A��� �*��yJ2r�>�[���6�N���t7��p���\��#	'�a.��"�C��C��@b�</&�ӗ�kz��î�7H�k� ����xD�I�9u�t����և��u���ڙ��y��ksIմ'�ug�aԺQ�><r�)^\�L~�)˃ ��l�k�AU�EXR�>^k�Sr|�m�Zk:�˖C'�d ����-��GR�T;�Rw+2S2$����]Wk��{��A�J�Ν�!�-g��9I1�5(�p���#�0�_�&��0R�fY���m|v4�H��G�y�"�N��Á.��/��w��'4�`	��{:6�.#9�%%ܑTq����Z�.���|aXg*�5L��<"��_��&6�_��<��?]]*%�}e$ ��c�^��e��ף'L�ww���/��ko�t0,$�D�Gԩd��kz�:�c����.�� YiŢ�����A�V2��Ty9d���9��+n���g�o�Fx,̫�܁�V�N
�Z۵�S�3�[�^V`=�կ���d.�Di&���`�<ŦxQ��
H7 U���M��vslca��ל�L�WG,� ���b�ǘ��ҕ,��~���.��#�^����֣ʯKr.H����o���o�t]���J�x#ձ1r�>�Kr��]��Ks0(
S��2�+o�-�x����4��=�_�I{ٻt�ܳ�|���R8�.���E7��Нu��"��͙	���e�#�>���Gy&kx�\6B����V����~��z��?�b������0�4�˥K��c����ߓ�ɱ?�W�ZE�_x_��63*5a��
����,C�2�|�?��Y~�۶X���)e����2��|��,���芳5�V�8��.0&���=#hʩ࢜KqŃ�3ǳ�~�F=|�!&�j��[�|8�i���b��>����
zy�n.Ά����:|W��H�y��zJ�����ߺ�"t$~�!���!�#]wV���WN�C�N%܀�}87>:3��ۀ����ܣE�Q�$-	��8���?����g�><�/��'������a��x�Gw�^��Q��A�������/�$��[&�;���+"@ϼ�����{�����J�?98������a�"�Ւ�"9A�z�K|O+��Nބ��c?X�^ubt3�p��F��
��f�w.Kf{D�]�6h�IS�%��'���I���D2w����HW���wԸ?峃�٬Cq{��rm���(�J��8n�����ib����/%�U����$���|ٰdcX�G0��W�¯V���T�=��t/|s��Y�:][�K"x�w\�i2�j�Kj�o�s��`�6��rg���)s�@��GDSH�l�{Lн!7��x����˷�ШQ�r��"	�s7nv�9-[��a�D��v�{�Ll�`O���贁�k�Pi'�U'��G�bص�9��?���졨����ΐ�j�w<��H�H����4)Y3�I\+��
�rXք�O+4)��?����m����+U꒷�4ާ>��W~��:x����ر��R�DGRG&LQlάw	��L�L�N�?�"�z�1>=�=k�G��N���j�OWw��۟s��S�t�/�2@������"�5�?߿��0�����Mz�	�L����.���~,!�,�?���w�jDR�&�o�4t
�B�C��r�Q`�5KA^�r�������G�@�cH+zW�:+F�l_�CO_?�3n��!WP"Ō!�ب��ik��vI��"M�d�O�v���x$�0"�7z�]�"��1YM��Q���\����tG��F���4����	�̓4w@n�#n��J
�B4@�e�$#L;W5�Bۏ=0��F��՚���=H���m����	�_a�d!���jhM�O8(��a�!��Ff�Q5�n�^��T����NnH]�k[
�F�v�#�����@���3�ϲ��q9��
'��
����N�e�]3`2c)�"�w�7^����e���Xӊ��q�,0b�)�Z�{��N�e�eM�a�~�2C�7��n��[�$6���Φ(6tә�n���f��+r��j���a!� ����-/b?,$�n- ��В��.�TŒo��,��,�hİY������zg]��I9>c��,�茜�eg���륒u �����N�j�4O� ��	S��4�y\��;���4��Q�$/��w��.�ݰ����ݐ(6{4t�������у���,i�% �k $/$ͻλ��.�&�!/V��z�㮈�~��v�ܵ+�/f9���r��� ��X��c4��� Uo�JII�ǥ���ED����t�ޔ�NW��u}Y��H�����\h'�h�����n.���)*E��E�Ee֯�q"�D���8O���2#c=��;���{�n��^Cg�>�V���`s\}C���gv�k��r�9@yN8����$�z�t;�).�i��u��	��}�U�/�a����I�����AU~.E'�ߥQM�[��>秾��<՘���u8s�����_dϴ��7L��Ej�v�NtE'خ٧O����8�PUJ�h��V}�VS��A�*�n�&��3�[*+Z�j�aU��k�e��[�?�eY7;�ʲW�.ąe�\��̣����l(����{�����(�
��/^Q�.�j�Ӕ`�`2@�&���O�~�P�#����I��h!��t���a�ѩ�4i6��a�(���7KN�<�� 49`E~ߗ���즜�O��5ͩ�Oݜ`��=���Б�V}K3�.���\���(���>n�=�������2*fL��:�T�^�>���<�yJm뽏�#"��~��&o"�d:��n��    ���W|��`����"��
o�?�� �0(EI����ѲW��Uoj��d��?�6�@�� �!Px.�\����&�m'
�w�itjk$�0 ��khE�_lt<�ݎ�x��F�+�`i�[�Z���N��o��)����ݞ���go���r(2<4_�%�������W��ܞO�P�2Cq5B��Ü� ~�[|bI�փ`��LXOe�*2׍�`�Π��Z�yI^]0K�s��.��5G��`�����g3� ����#� 3�A���B����K�Eh�+.�i��� �s3s���^�A���ej�{W�o�V_�<$8�
���j��aշ]�aNEnf�\���ޯY�
��o��"��.׾8SiJ{v���^W��<{��s#�s#,6��9��h*��A
�'P~�<����2UB���x�������5��"�vs̐�E�p��Q��a�N�N�zn��-xQ�5�x^F���rB�_��Ŋl�=z�c��6}Ͽu��Ŕ�.XW)Ⱥ��� �vL�=�-�Ö�^O�ܸ3�#��!O���o�����G�����n^�z�,�E�m�wOt�KS�f��w�ꔞؽ�W�0����C9؇���|�틥�k�	�/��h\,�n���2�yA��H"o��qD���Z�b�q_�}�CY�;�����w|`X������`l�`(nR���$-�^G�p���V��_�Ҙ�WS��rɁZ"��ԅt���|=���WC�����C6�}����Kv�����<~_~�ۑ��������Yާ��4���	{�����@o.�PNJn]�����a$��	Q��� ���к�%~K^�	�v@��H:D�C(p�<iݭ�4�����W�X��͵�Sٖ�{&�C�TN,��$�:�X��ƗS-B<7r�N�d�P6�fBА'dG!��ԻnFX�A�� �G��ގ��;D\��[�o�Ǟ�?Z'���}�[kXXc�Zu{Fp�a���b�qwo��v���bo��H������X=e�`�B�,���M���������nM1���-@�藝f�]�E=�����7��6-z!�_P��"/e�@���qc�XCQr��3�Em��2V��~�?8�:A�Sfn���\X �{�=\�7��ù�ܼ��7�Go8��v�B��1v�Z-3u������~5HW�6W�L��@F3y۟�6S�!����8���v[��ƃƊ��E��,;�Ly	9n�i�d��o��1��z�B�2#��/�K���k�m}���t��g�F,nS��wԙ�m�wi�� ج������4�i����uq���[Ѹ�����սlW�״��^}f��n��X����{�KY}�۩w�+y��5]\! ,��S� �7��su"�(�`ۖ�_�/ڥ����޾q`\����l�N:�	���fE��m Sp�_��3n+�Z�z�"���W@"��{:|�48R�a��Yf4�)��3��cI�-g���|K����|�g���5�P���f�|�`���	�s��F�!��уf�Z��S\,䂑w�"�#r����;��=h����>�Z.���VK]�z��pI�O�кI� ��~�k@2�H��>i�q����>��B>�ALd1(���~9��m��H+J�v����U�<Gak��sX����i:� �����k�B4&^���[MD@:q�+�<ܯ~��O�6|�!W���M}&���C����J�|h[����ĭCT�A�3��v�X�Pȁ;-���#�,X��!򤕘}�h�ط���zWر��=9 Z��#����n�'��-M����ZC��gQ��_�܉��i��S(�L��QLlx�~�w�"J��=P��Jb�wt��؂hM.� J��1�e���J�i��h!Y��o��D^�3Y��>A:D���bT���O��E[2���M�Eg��MCj�1U�>KZ���"��8O93�v��k^6=��WFM��- U�h����z�6\^M��!k�v~W��^u�� �����B��2��J�����p��3�-E�~1%��j�&	}B�ԉKvI�úV�I�J?�V1�O�����7��ɛ��?$�v��G���h��W����Ɩ�	��`�����@428�]�B"A����_���s
Cq͐<�-��5y�t+։x[* ��՗qD�,m�G]�K|D���زtC:K	B�Q�5���,H�2ז�f]�2����9}�z���o᫼FV�c��F�bc�1�5�k�LMU窫e-�E����u�;�x9�hY~�e�q�x�����p�#�+V�*)�T�h=6՛����)-����p���7�y�0v����F(n )�����М5��v���a�����{�7�\X'*�&/�VsaN6]���q���tJ*�S�P��e���N)z)�)o�\;���]	��N����f���@xR�?3�--,���2(�`��Q��5A����������:b*2��Օ��ru F�˂�yX[\���9�l��������C^��@��F@rtz���9�z/ҁi������4!#�4�����A�-�w�RS/=7uI��w��䉶���6B�$������lF��9�gP�{�\����5�:�>��'���9#�s�A�N3�d��@>c�ϖ����3�8eK��<H��fUiE��}��ɩ�@gg�����轂z_��7�$�� �Y�4�t��ΒG�Ñ��6��S�)�%?��0�l_�^㵊3�M�z�>�M�MȎ�d)#���A�d����?$��!�dϓt݁�7X���l)T覐��g��h�_���<�2�ʎ��q�܁���F����Rk�]3q��Sy�x`��q�&�%��Y���+���BN ��HK�)*4��6�O���'d���UA����NL͒�UW�v�����y_&����x���f[��}�[�<�<�fP9��:a]F�)��j��R�g$����B�S��=��d� ݑ �9�� �B�:���(���䪻���:�������/�ZA}�]����sϙ����:�{g�dH�c���*���x�]�p�ٞ�w�s��ku���w��X�L�Zww�̢���(N`�L����⛛!yhRN�P���փ�v��������Iwojn<1��&�H��Ƶ� 	wk&G��9��NB�/U^�O��)�*.�Q7�n���dž�BgJ^����� [��L��K�sC�j71-���a�=1�����/@g���W%
w��7n5��^��F��Y���`���=�!q�2_}��T @�z[��Π-�
�1���w�ջ{C�<T=0�y�rM(�z��>�����G�7��hQ䆻�$Y��䯽n&%k�� �͑�c��)ç��Bp��)���� �##��\�Ƣ���2��l����ļ���p2�@��n7�NK"C�H>7�x�]�V�}�rˤ�נe|�����!���}R��ާmq�?'dP�jWܑ�[>#WN�&��6�N��AgŰ��p\:D��Bd\Q���|HC��"�0����7���r�āz��5'li�{ue���;�uH#ut�����h��^0���YWw\��=jʐ���Y��U-y!�>���~�,��H2�/��"F4�C�s0���˅|���E6U��q��?� ��{)���z<��!�=���/���Žwb	�D��+�A%����b��$Tz��������/ࢯ��yKX�Θj��֧�&�G2��p�>��H��T�S ��dDt2�}	.ę;��؇�����M�ٹ:��@��U�X�݊���N2<lV�ג��\{� ���q���p�ն;lW_�l�Q��ƙT����W�tr�l&�:,��-D?���2�G!�V�^���&�2{���"
%'��lj8z��TS�^�-�{��= -`Dշ+�1��ʋ��^���ꛥ�yZP���)-h>zX�h�.�o^��pD���
'5X��;ǿus��+�ޘ���N��QWĜ?��    �
�NVX�1u������h���B[�;��&L���'
n�!��$)R�h�.�"β��������Be�����g�T>6z�/���q�����4�r��aڛ!�`�鲤 =DbA3d��m�X��si�m ,�Y��	J�ٻ�tV��9n�bV�!4��;�A��V�|�wЯ�	�:�X�^םm)d�f���C@{� c�GO���WҰth�N���^;Lڣ��ÌZ0#<B[��!��0'�7��:tDO��'S��+�3�m���q��Sן�Mx�� 8�oT��O;�z�Ų���=��wfY��d��\
�Q2����/��p`i�'��<�cƙ9B��q�����MwrĠ�m��ލ�#nPV\�
~6����� }O�}q�)y3�Ju�ђ��w��UL�t��/��E�+_l�n�	�Iv7r��\G�B��K۴�)	�q.S�JaLڏ���~�TK�P��{�j=yRR�1����`��Sy7Vҕ:�a���7�J�aG��Z��wX�f�`��1��.*���V�y`N1�����T�,88��;��<ҭ}w��!�`�n��t���_B#������gR�J��
%��ZI	Y��g�u���\9��'W���6��Մ���f�������i+�M���xy���s:e�tA�|�+w�$��@HDh��9L�����<��X(���/@�J��z���
�Գ��A[�ġPJQ�K������-��3o�&	
Íӷ �}^Uj���d�*O��ʑ�Z�-�{Ðɞ�1�B���@���g�4��6��١p��Y�No�C�xUm������!��+0�Z��t}tJД9[ml"���mi,��$��������Pp�+9�zm�Iw�ܐ�Fՙ�03�]$ޤ���O���cV^u��d � T���,�EK�XÀ65��'!�0nh4�7��=��ʍ��Vo"\�Ysu��ʈ�Z;�(�#���"=s!�^Z���v��@�����������	кt�놫 ���� ��z��8�:+��$N��<�[;,�i;�A�ou(�n�Xg���O/!BUt�Tm9�Fa���ې!c��괸Fn�����0��0
�п�.CUZ�#�0G��Ր)�Xl�r�Ib��bƔ�K�:CQZ+]ZiI�=����-�f^_M!�����bP~�X�x�#�fQ���!�*�f�l%�	�&Q�8�BA�����Wn�b ������Ss�մ,��v5��h/�VtP�_5O��U9=�-eid>E��(��⧺8�N��xvH�2��sQ��� |$)#���V�^O��{aш�X��ts�ͬ�##6E�^;�߮�زRz�����uU�(��.��� Zo�#洖�rG�������r
�N�6�hj��y)4՗�-5	ΰ���>!�Q�k�Y���Q��;��E9`a������;P苺q�%5�W������
��é~ɵ�^27#�K�/5�|�Wъ�(<Zc,#g=W�IL\��a�+wy>*\P�[��Sz�n�&J;��_C� �v�C������m���F뀛=�����z0�d��T�O�*^��dn�d@����}��93�?tV�s^\t�o僙�
�ECoGl|D��Ӫxbi�M&:���ǈ��?(�0�'w��X�����e���P����l���6�6�k�7J %4��X�8L޿ �	v$�k���x�[�X�E�MҼI��$��f��5Dϙ3faK� q� iZ�(1�bʥ.�xr(:� �If�<?z[T�'��	ݭ��u���
C��Lr��B�Sf���
�3�A0�A����:���/2�����W�Oi0�֟	��n�	�J�F�L���NK5;K�	 ���\X����d"�AU��xkB}'A��o'�6`�ꐄ]}��ܦ�C�+#�WA����ng$k���P�rE���I����&�<Zh0��4���x)��]��W(��D�	��>N^�ɔY�Ӽ75�w���nO���>���i=k��R5 >��:{:�:S�˜͒^U9"1얪E�\����7�~���3��.WAWX}n��z�+��^+��!��<�M�9��Q�%�E�P�t�����.8/0�y���? ;\���n��qF�∳[W͟m��\Hr�N�h{\�ɘ'
L=�B��jy]��[X"s�!Q��Nb=ЎKTrg�媼��w����I���l��u�a�eV���Ȍ��"a$~q��`�ʖ��H̥m�F�����s����B��od��t���s�n������S�[ߩ�X�Θ��]�r�R����)#��v��uuF'���J3�q3����3ft���b�����m)��*�gsz�9�X�,��"����� ��c}2��N���q2�P��27�(�+��c+xLځA��G�'R��I5���(r�$��.��V�3� ��7R��� ��||��0[e�s^SԶL�C�ħ7�Ou���ɧ��] �hf&%��{}�L�S:D�^Lq[�ל"k/�مK�}c_�Y�s�'d��r]�e?V#��"��(�e��K��µ���C�c)D�P�R�Z�5گ�֪@6�z�ˈ�┗��ݢ�mj�p=��'�c`�/����'�˵�>���&���^����[����SaEmt�d�_��ua���\��Y�h��z�b�}���'�c�}b�)2��y8lX�-��"5��F$>B�Ù�:�
�Z��8���g�2�ϋ��-@��!���k�'����-8�.�ܛy��އܻ��ƛYA�A�4ڃD�<ޙ�2=C�0B*Ck:��eXL������qB,aY�~.���� VF�b_m����dM�Q����ЖP߄�86
�����kT�/����M���+#f��x�t�����1�l��.q��Wf����Æ�C(U�-�ҷ���q�#_GT�������o���7��A���۱� ��7�na:������a��I�2����*+\^�atk3���+T~
���T��;@^5���}S���z:BZ����J��RÂ�����4�)ڲ��;Z�K��R�u��r�&�"��>��#'��|V�dD���QY�=7H�c�^��>D�^X"�����Y7g���-��H����.5;=f����C��)��T
��X�N���y��Ik�3Wy����Q�u��r�!ם+���
�}�v���;�Q�91	T��*s�0@��*�6�'�O�)��y����1#��bL�.1�+qR�<a*��Rf�"1��2B��I0)ĠS�h�XǏg#��\$��L�cr�����n�S�d=q�Nu
^�ReQ��Zt*4�hg�b�F$��8����+*��	�>;t3���A�Ǩ���j�4��]9���0�b9� ���dV�7�EG�2F	�A�E�늑����Q�17�P���׈����v��gcAQ�˪�Ԡ���Ӆ��^�i���Xwd��/�� �D5�z!fӲk�1Z}tdc؈�� vd!K��Q6|��̱�V>��5�OM�E���i�)��#m����R��*7e3ySk��3��pf����&v���&H^�í�G48�C;�Rt����5D�n��/#���tTN����C�`��Ô ��-�o�������<K�5/'Ҩ��m�Sw�綣0K�ލJ���:�S@;�)M7�Q_���V�jt��ոo�Ȯ釦��o�����-e,9��E��_&�	�z
�T�Qs�"�T�%`�8�~3�>�-�S4�0�lx�Nh}��(��cս��p,��|�*+�����)@����LJl�������0��˅>mj^(�}����g!�Տ����cO`���O���~�܈�g;`6
����T0����8ӱ�W+kn�w�;��{X�= �ܝ�r�߈�.���h�t��;�VU�����q�o��Tb�[��]+	Z�^�w��Yj��D���_��c@�Eu��Ij��~)�`=�n04�� �  C �B���G��-��Yʏ�#]�>�W���K��:�s*�Dc�-�vѣѓ�Q��<��H�|UM]��u��|���Q��07)�<�M�f�~�/F�p��  r����6.uf���n��O���Mp	��ϯ��?c�� �Tz=���TÔT�CHQ�^}�l�w��72T�I���qS�f�d�+�D�f�oNv!Gs����.�8H����}�<�]P��1ڎ��
����լ@2Bg��J]��	��%�FyL���}}��'�.g�}Ga� �$~C������Aל�=K���;��t(qy�#�ڗ�7Β.j	�E�^t���W}�kvvZa��i��U�䮎����OM~����8eD��o�B)~�����8N���ye�r/Z'Z���r�(�x1��"w#��(\�;�r����\	��s\�����0���(Z}3~�g[�|[��8ǲJ��-�����:��4�����.��O߇�<3�#�c�3�CY7S��=��2�^�_<o��u@�Ƶt������<��DF����"�����p���5�廸��p��%����b�=�{��N-?�S=�@�<0D�Q�t){H��_���+3�y
WX��;���ɠ^r����j������t���pU��	qɀr8��Iޜ��Ӎç?�q���08\�r�[��ϼ._����m�k��8Q������Ĉ4��p��D���I���!�8ꊊ��8��K yc7�w]�?l4s�?u}����v�+o$o�>m0�2��ſ��w�
��F���F,.���ں.�Rp1��7���lVOC�</Oëj�@����b����bb*��ԃ!i�S��G���@�9@Z�qH������YNz�n�L(�W#h6�(5cB�Ad@�n>^)on���vP�Z}釫��;�S�4�Ψr����_QC�ß�����s�*��MqA����	��m�	�5�� ��Ƞ/�_������?���AT�      �   B   x�3�4Vp	s)VH,�M�-��M�4�44׳��4�3��42�30�4�2�4¢����Έ+F��� =y�      �      x�|��r�Ȳ%�������`P;d&�H>2n�ːޘ��t$� /�A^�]�C@�œ�+�|%-��+U��,o��$)p�5=�G����~Vw�<�V�חU���C�~����(������V���W��}7���ٌd�CY}(�0�^}���k5���ćB�������Q��iu�_�׹��P�>�%���՗�yw\=�Nj�5��p�_�a�X��˦[}�/���E���~X�.�q���ح�wG���4vv�h�7at��������iښq5�6�PG�خ;x��n����2)��M�֏�s���(�_�^�,W��8�f��������P0:�2?y1�0�^>�G���M���<��{�qŊh�J��U�a.���{=��qE�|uqq����q��J��2��R����[����~<��via�dK�r�����{}��Ȓ���Q�Ww��]���A,Ԯ.vs8N���75�ř��}\���_&�R�K
��*zjUڭ<o��Zm4'U�:�s��C�G?y�mЪ^]��4�׬լ��I:���}P��N\��^��"_���������N��A������}Ws7�_P�կ$�]]�y�G;��;8�KU�u8������J3*~�]��u�?�O�qg7]������x뷫?��A���h��ru�+��o^�n���`��hX���6/���vf����G��Z#��a0x�7�����L�	~�1:5,XE?��#���6�� wy���Xݩy��<͇�?��>����U�ƍ��I��؏v�R�����tg[�?��fG[�n�*�^��ˠ���Xīˊ�ô�7=씛�Z�s-+���-�g|�m8yGVi[�z��n��s�j�~�����`���x[��[X�����"^��&7s��[��O�&(�C����~�ข����3	;n;��>n&w&�pⶋLk��^`���q�g֝�o]��0N��mg_���.^^©��8|Sǣ3�ƶF3��,wׇ�p����i5�{7W����v1��� g�3�P���o������ח��kY��0�4.�ڂ{u�u�ަy���*4�S�-�	.�Kؒ���~�a����7�E�m�{�a�:�V�5m����+ޙ�썹(�;N�9���A�~�sZ��'����ӻ�[��,~�4���l�8���g/��^������}�x�~�S� g5,(�"���:,w`�vӻ����`��]���i�S=m�Ӱw֜���-�!��7�!��1\є�b�k����o���l�c#K�B�n��������
�upX�c�<*r{EgU�x���7�z]w��ȶ�d��"��8ۃ���`��Y���2Úx��<ZZ)��-rFp��woI�?.����V��xJ{R��VöSB��������ܨw�6��N8��h`5>��qu��ẉo��6p(�������b�É\���hQ�1Z��Z}�n�N_:��N=���m�cu��f8B�th�)���������e+�&��I���� �����un�|,pu�~Zm���]�Y�8�;���;��qt���:�`�a	�؆��@�qW�#nl�0}�ŋ��3\��e�28���~�?�-�����pY�?˶OfN0x��r�����j�����䶏V���-��W��i9�sU�{%1-7���nDL�}7����S�������L��lt�x�w�	�DK�6�߆�~�~P�r����k�\����6`����,l����؞W_�qه�)+�^��2Oj��F�l�#�����? � ���Ms��x�q����xX�)�(��[���9�E,�e�Wg���n7xO�ѓc�L�d�6wj��x� ��t�����uK��
�ۻa��? �(g��"uˢ�_r1���Ot�*��8��
�"A����8;�ic�y#������Im�-��*^ ڰ�0m` G��L�[	P�rZ�"�k�S�$����^�K�\�:%, ����t6���`�v�s���C���0w��P"�>�%���	ϒ{p�p��J�����^�}>�s�"~@ߏqp�����^�t� �~X^ѱ{Tq8��G��2�p��>�i���T�u<�{�܁���p���� �ߡ�x���:�5%�8b������W�������?Cp,�Y	Vd����R�R&����2���ڣ����QԸ�A�1����������(�ڌ���.��V{g�"�� �+��s���.k�O ;]�]t$Y�xh�碋�O�s��F}S��EW]MCX ��n��0F��R�쫻|��ܼZ|�ۍ���w�z��A���������;�1>)�_b`�;�>@�:�� ~��
��|9z;����f���&t7�th�D���	����(G��K�G���^-�kR��$������4�&�"�j&�!�u�0�� �<��9����2`��%���d; 27� �f��Nc=%�s�M�ْ��gй{����B�"	����?�j���Q��lrB�^i��tT�:@Қ�7�WfB|�8L�?�8��6O�
�D�Ⱥ&w�v!ϧ�w�t|�Ć���ŝ����>N:�p ���������YF��8�"�,���r��c�!��p�� �u��:�(���������F}�RT6���!#x�����Qp�`@�K ��A�o�{�U
�K@��9�TM�7y�������w&�2��0!����M#���=r�� �?���� hF95+��ϻy��mCpE�ˀ��sz�н9��2_@��ނ:w���Y���1z<�!Sf���O�C�ip��'	� ���F�ae-,%b��7j�Jb8��Ȍ�¶LG!���M s�a�,���hOr��iT�.���s+q¤���6V�y��ᯧ�q�G��!�δ��x�=�͵Nː��D�m߭�C�h�l����w�[;�X�����C�5\Do����1��ぉ�	���-"ė�����p��Xv��$W&����6C{_�n0=x�U����v�+�$y�bu�����~Z�5�2� ����<��/�%`�OCPk�Kװ����A-�׵��5�1 ��2�;[�8����0��x�s
���}C�]n��Oo�����b%��E�l���_<�<3v �1����b�A)���'�t�$W ���럃��4����Z��1��KQ��sѼ	��YG@�gCw8 T�'���R��oU���XN
2S���,�Ơ��@��35��]��⣠�d�i�-��w�L<�«���?V��t�1|3,N{�Ǽ��{�V�?��Ui<1p�:�n��z� ܣ��O��)�Тq��D�sH��>�v8[�/�SmJj�0����y�2{�%�>��1�Tt2 �_�`ӧ��򢞗��Eޛ�W��٧7�|��% ��wyT��[T����t�o]O���� ����l޸=�Ӌ���%�����e���vZ�i�_�/=���ML���w�*}��s��ݟ�]}$6/���[���н�LE�]�D������bT��Q�G��5	o��;��y�=<�q9Nxz�ƛ ��ڤ��}Gh@��M ���3X��,+ �K��Υ���<�ַ^W_��&��Iv�B��qu��������Ƴ�mi͍e����:Ĭ �?���B�+��"�JE c`�R�x�>��f蟞�Y�*��k���vh��Df��
�<��� ��*qЀC�cyw��Yy6��9�_��b8��~��]o�9,ĺ6��n<:�e�YG����8�rnոS�QHf�a�y�𦃕����	@�����F�DSF���n�M�9���&�'�]L���ƀ*��ki�����"�����4�(b?���*^�aW� 7S|/Q��n����]�HD���*��a�`Q��
1�:�+V ���z5-ηg<U��Գ�Y��( �7<5� tL�l1novر���� ϒ���)&�|ԤL.(n�� Q���������OĀ�^��MDV�0��    �A���G��3��uHh���!�wK~�Uct��d��K���0�_���r�/������iw�L�=���Ꮍ컃w��C�Y�R~��ȶ�S��(>���~�Cz����m�u|�)w��@rҼ��aT�]�wj|�<Ç��
���Y�cp�:�����L"p7��v�8/��뉬1@wX5�Ay���(+}E�_����]s�x�`��n���F�>|E't$��0��c����.�5�H~0�~�t9��mvY��a�j^��!��d�8���`g~��;�r5�F��:�sI�R�x��9ۇP��n[���W��/������I1QPϸ҄ �l(ո+Q����]�Ǝ:+R����v�_���ຈKé`v8y̪��a�0�aނ�Y�
��^ȷ�6��E�"z��g`fi��I��+@�7�$��0tG�axpȸ�n�y�ͬq
��M��'�����ɝ��˄,Y��q�eJU� �D�w��Ȥ#jW¨�"�L��-�Svj�Mp�7����D2-:�2���_��d��;Ќ��mt��K�m-�^�d{��S�#���C���ĥ�P&^��+�6.ů�agv?�0���l6$���kR6����9a�vT?~�{���9�UI��0����8L���N|�� �/a�|����g%�Q��.���9�忒�mV�������	]��A�5�v�/O����~�U=�w��*��Ԙ�G���4h��L]��zT.�<Ɵ�3�#%h�Y-`��n��a����g��Sjx ��SSi�.��L:[��_�QBSs�]���ݜ�x/h��g�h��W��������*	�󿘘v�oXA��(���S�j�;֕��.�q���%W� �?��)�s�l[�aaW>&yp�2%zԀ���>u����G�œB:�+��T��P���]{~=�9�Du%<w�RiB������̅���^����<L32u��q��E�iF�W]�����/�%�ƻ�.M�|	�&��׵)O�zz�0s5�Y��l���n�&xU�C���s�3������5��#�v@ғ3�E(�9�QQN����֜�h�l�����<�s\������5�����E�h&�E+ڐ��Zbj��#ǃYa���8�7�)��f��ʿ!B	�C�F&���Aa�ӥz���W�mb��s:U��H�_5�x����p@y������9kF��5`�s8�Wpm��S'�-W��_V�wj$�r:;��s�N)���ZK��޼),�A׀��t}����l�lnr�#����0)w�u��:�/�$��c�0h����_�7x�M��TD͙�nwG�9��Q�2�b	�,C��4?�ial�2�k@�f��ay�A���#'������f��G>��������4��
�c��:��CS�0�Ո`|*^@����ȉ��;Ǆ�%X�_}7l;Oo�D��}��S�e�����bV��.��I`�DoYh�N�.ʊ�����#�Vd�4W�7u�:�k<srRFn�9��&&�,L��^�(���b ��Ĥ���o��H�u5���	��z��Is?�_ `cf'L;>o"R*i��.7�p���~ٶH��0�p�k�§��]��߰�~�w^ʔ7S��/���P�%ǧ �<���c��7|:�5�_�2C0�g����s�,���ܥ�<�n0�5>�����Vi�l@ ��:/{�_wGwJ��5�yMY�:O�a��Ŗ%OM�kuW_���;O��X�����orX�fz��4�_w!�a���9n�ی�˳���R�5�x3�`D���MJ���_+�t:H��\ ������UȤ�80< �g�{��7��4s]�<m�.�N��<mf� �_,p��;���8�g�n�|�]칷�X�x����p�;��_le��XB�k�a�A7Y+5�(r����T�X��{��w_�T�俺���-��Y�Y�²�~�no�3@�7�s�i�K���v㋞�Kq�K��;��؊�M47�
 ���8�n���az;��Q*�r����]?�n��Q���y%@{}T&�r4�+���G\I�g��`���BH2|�&�ڔ7��	L�G������"u��1��w�.}>�]��<͋0�ţ�����1 ���AA�P�r��Q ��GbI\V��I2@�H�� ;��\ްo���"^2�����CD�kS
`����Ʃ�*H2
@�m���g�vc�G�U�dJ��ҡ4�̐X��.ީ�H�6�*�Sq>{��h����#��[� ��Ŀ�b�a?Q~>����pT B��0���]ׇԎyX|� �#��u�v���E!��׆k"��e �?m��L�92������6���in�!~�0��S���Ы{VQ1zb� ����2hb/d�|7;�D��+�$iC��k˲�'�����Z[�%�*\j��ڛ�|`��n��Sǉh�A?P�Xݻr^ocLy ��`�ߩ�g��d��13��:^���f���f��x�:�0�G��,��#@NK��*���N�cVݽ�I*�_g����l�#z)a�;JC�v�(蓞K�N��Y S�Iv v=��x'�ӂ^A��X �C�1�d�_bY"|��k�yZZ� �;�2z��P#h���y骻��/�b��]'-OO}�%0X�h�:}:��_�i"���;�]�+iȌl7N�%��b��F���_�t�p�6>I>�D��@�9ơ�|:��5�g����Ɖ!s��D ��:Mk2QF�e�߇�{z� �!�_���P;��<�v�~��3�-݋�1�͡�m!��L��2��t���c�m��t�N
~����¥���ҥI9h��_Y��_�4�� ����mA@�0%����������\��?L� !���l�g�3r������#+ϒ�zJ7y�92�X>V��&1.7������['��1���A�7\m��t
ܤR� ��%�41b�t|�IkƮ�a��v� �Q�K+��H����x�k�ělFG4�W+���օH���w����ťl�4�����>L��p�0��i���h��1�,ӂ.��x����qq4mV�1�oH�L`��TϦ�qj��n��T��ɁEAԩ�Vt	��5�X��g� �	P�Ui��Z����Oe����_�Wua�mrF	���HOE�S��;���|�L����_�(����3 ���w������DF�a��a�}^���pVo����]^��O���+� ��jft��!Mڙ<��	�yGR�Ky��uK�}	Q��L8�w��6k��<�����8��?ە�3���9��U�".�Ҧ�)��i90�>��Op|��Is��0E����Y�E�"�׉�Q�6K�'/�fX�����/�3���i��=�9��R'����(Fڅ��\f�#|?X�4l��S�f�ݤ��]L����KT.���.�&�9��$wܨ���F_x�k~���Wu����/Yx;�z��U�����(��?Wᖥ�"���{�񣸱HC�лu9�g��#q2N|S^�L�% ���6,�)�����V���SOoQ^9�u�by�8����l�2�+4'�u]<z�*d�G��M��LM�kRK�+�R��0�gk�܄�����!rL��{</>Phd� ���&坆v�{�L�jgi����dT
�C���'.iބ��t���u),3)��(�<v�K"j�"b��w5�)�?�sX�V�F_R�2�"^��z}r�)�3��W��2k��Ha�Fx���4yE-֦�R��kM��׫�i�/��I�����j�^_�����cC �
�����W��ez��K8}��űZ^i{�m� � @��?�?1_����+��~�M6��o���By{�?�l1����3��i=�ǰ���̆��6:喅�x�����/1��鿝6;0��p��A#s)�
�W�����4�Ĺ֏��� �2C�@=���v�5�u    F�9p+#��n��2�K��7�r��N�Jx����RRu�f8GeG�F_B�XJ�� ���.�.?D%+��"íT�t�K�A�_�P��o'���>����/��1���Q�Z�7G��ЙS_
��睚(w^�p�8���F� ������ò��Ҭ@��w ܸ9!�h�qWm������U�$���Q�N�#�"1������Z�-0�������p"���	�q���G6�FX![<�{p�I'���U��c�ᵏ\(�\�,���q����:�M�*���i9�O��5�I�=F� ��TU�)�$��6��'r�D������C��{]p���:�����Ӄ��:��M�Z�k��RЇ3�
`��H�U��5���?�:(�Sθ��_7갍*)ބE���k���L��>���H��ǝ����7FX�:R����x��u�j��ubMu �_v��	��n�:+�� �M.Aۡ.J}��?G��N�.W�k��AfHp>�c*�fYGI�L����[�jX��I���W���n���t�rޔO�����>L�s�ԡ��[�(?J�8���d�_��X���b�?�+�"�Ԥ �ҿ3:S7p�� ʊ%�qq�9�o��k�yy���2�|�}7��&�J��������DcG���6��yU��q�c�C�fg�;�j )�K�0�ꏺ���<��������hs�Q"+��gIb���2�|��M`'���_;�q�L��� �%���-s3�����D� 4�-���z��K���(�k��*@��D!�DRK�M�(��ԑ��Ai+w3FrYzC ��Y~��2�!ޚ�����)F%�t#\뿼�*?�Ŏ�aK]��^��D���~��r�Ö�9q�Dɴ��y�Q�]�(��o�����#�ݱ����F� /*�5[qv7H�*����㜘��;P�Vﶏ��� �։P�N���r�~��3v�#�Xa�6��5���S8!�� ������G�$������N1�g\^7�w��#Q1���ܴ4Ǝ��満"p�7���_�$�����}�˻'�� �6�	�t�V�K��T!�Z�ϙ�'��i�Px"|��1T�7����p�L�H�t>&^�=)�*�nu�l��ZB~�.R�!��)�FEL��)j,�Wb�҅�=�����u�I��*jJ~��
���j��-\1�G%��Fχ�wy�B���I���]5������?���7#(�=
J�녃Z���qS�� ����v����" ���vo!2-RF�@ԏ��ݰ�fGV�#�_S�5�D;�y��J�"�Dr�0����"��C ���V����ޜ�lg;�X���6vA�&q�/�r����iQ �ע��ԑdk�$xe�~��8���H�����q��-a@t���_u(>�{i��|�+���ڈ���!F�?փX��ȎB�z�V/`
�TO}0�m�1ܳ��c�?��Q��hc �fW�Ml
�+-͡a$���PIIM�!B�4�  ��rPj�M=^��9)4S;N�)��Ws��k����	��	 �:q�/R:�V �^��D�tY �'Kg�u�(�"��Zx:V�y�l�)���ɼ�Q�S��G�@f�X�i$$�8���C��GU�́��=��a���To
�q�z55S�D����q���%�����gL}�G�a��������D�Z�`�G�tI|X��=�/&Gbi�� po����h�8�5���P��� 7v<P'��DK���,a�V;��6�Q�ʩD���z�b��'߂�x��������)V��q��[�q���$6��D�s"+,�0�7������{m�w#��a�v<�_��v����¤��J��{��f�W�"_o��]�<`V�( �_��Q���u K��z,L��K��Ҙ�x7��
��#�.B�/=ң�v�����)Zn��Χ}\�� ��v:�6�m�oA@��;���7&�I�`y�!�/.��)�X ��E!6����[�T�O1�F]u&]*��6�����:���z�%�Yƪ��Q� ��2=��`����^�ʬ�-X�G�s�BF�����]����&�.�,����,�'�[�K��ݬω�kI�}��e鉬��%&��Y�A�����F�=��u�;��-+�<Ӫ�}�Kd���4q
ґ����6H[�Z���K�=��T�LK	e)L��f
�[d�k�yʥnC��Z�Gm7�op��v�V=IԵ~y
��4j&+,K�̹kl����Ʀ@"��r���&m֦�2��_|u���_��m$�[\e�h�H���ey#��i(V���	��E���Y��Q(����.0"��#+�4��V��N �75��`��Ƥͺ�h���P���LNr����õ:9,�R�Q֥������ӎ@�`�θ��}�O�Y����Dĩ���YY�;�q�SOOޒ��1�5�( ��� �]��g8)[��0���&@��ŝq��`���]+��I�iLTv�QXvu��>J�'&Q���.�#d�l��xfXi#�ci�Bx�i�S2���Azէ��1�P��	���NZ[�Tmg>�d��@�ݳ4r'�O�;���NCD'O�,��5��l􄁺J�Dm{S���P�Ly��;\�I�QdC	�ˤw�\E�̸Œ��w��7�N˴�#�X�)�vG�Nc��צ���$+Eʁ��ɷt��.xh,s�$�} �aIn����-G0^n���ǯP�z�)7�<�:����Ϻ8��!L{zq���%K��b�0�o�X������y�i.ԛ�P�i�a"M�IQ��O;Ow)3/@���&c�V��tچygt[�Ľ�9�q���pOc�7��͏S��B��l�Lz}�SC�f�*)ܽs9�_�VITW����;�Ƣ^!�tW��Q8����8z���4`{Mb�+�y�2��Ṽ�9!P���kV�m��5��$��ZV� �zf����%k}�l2!�1`��v������<����A	�^WN��q&�f W<@��YB��6mF�(��Otʔ%V�[��Ӎr�'����y�w�������K��6H^�g�E���� _��{Rv-���w�E���ˉg]
dc�%��d8�$H�W˾��;~x�|��Ó�~�Т?�]pM�!1䍓���|����'�i�p����BEx��>T�����] ��y�8��Mk�*)�r�%
0��6Pxcb���D�*�U���>�jҞ4��d�=��/��&��K �g[�?�T�H��$ |�Ӱ�{΄��Ym]`�����}�29�	oC�U<�"��J���'��c8Rm�%M��q3���x�SZl=��<i�	�F�q�D���z�;�FE��$�eDHG�r�ځ �<�B�eL��RV	6���j�^v�oi���׍���2����U��n
���x����czC��߸��6�t�Fǭ�4iк�o�̧��Ś�H�f`��y���+2�q祬�RSƺ:�<��g��Dzx��-�O
�S'�A�>6ӆ2h��4\ߔ>��ةP��Si�pb�=���0��Խ ��t�H�M�������1�ut6�����ڔp��~�O�+�<��R�)}�l�P
ת1Q�uQ޺�b��̏V&�LX�C�e�h.��J/��^�V��h(���o6S�d�N4\4/?j�~��
�����d`�_��H-)���t�U�`��LS	#�q����ui*��m���2;��k�u;��4U���ESYѣ��y	pRf�ޚڶ�Е�7L�p�����#s*��M��{���
�cPߢ��/�a񹪙f3}�Q��}/K��WWXG;�V����F��c����*ee�an�:>����ޑ�MA!ٽu����f}2[�O&���`'&Bp$��پ竛!pw��[Ü`n�Wl	}��J%,�.u�r#�V�ٴ��O$�.԰��-*�]I���~��a?kf�a�G�;�t�T�ZQ&��=�P#R�Ą���	��xQ�<�mt#zS@|3͇���Y��h��z��CN/    ���̈́���-R�Ɔ[���;࠽���N3��uN�1���Z�K���
��O�slPq��4���=���.V�(`p=�X��GI~V�k��ǴĬ��oxc7$�t�i~�/ƶ�|���:�R�O#\B&.�����%X��^��Q0�������҂�YKRԾ�#����a���`�S����[�"�A[�4����I�=M�7 �T���5�Y��Hm��`�����+�EW�`M#�@�UM�wm�-�-�2t���d�	��#[b��M�^�{���1i�R��9�nw��y����]e���Wߧ�C#�Ի�sM� y(3���k��m�y��AC���gd�]`���eب]T�C�o�S8^6%E��d���@%�ͮ��t�m�%��[M�=JA�~Ϥ.@��3� ��q�
�7�#)����@��Iq�8�H�2����w4KY�M�*�� wj��1�d�0������#DD�,��(��Ś�Ocb ��[0fv��X�6-l�]��^��3�����Q��[��g���m )�{����2x��&���h���>ӯ�渮�$]��&�n}���6�3����F�pZ�I]`��FK��~~T"��o������7mc��{����A�v+�b�|������o=�����1��Z��:a��J����P��o�Ƙ@T���#ߨaYN���'����5�6��x0��ë~Mtx��Q1�/�}P��i.�u�zw��%�vM�|�O[@�W��n�1J"�nZ���Ͳ�T;C� Ӎ��%�%��4��"�_f��]c��l���������)�>���/�� �/cPiS��u)�k�_/�eq����1lW������R[��D=��^��z�ܷ���|VZO�?�H1kS�-m���N���W�i��E�~�O�{����Ŀ_!o�MXDZ �V�n]�Jy��6�����S��`me/��n���e�l*+���n4�F����F-`|sE��f�^�- |��h��]do��΃���igA�Y=���i
y�Z�>�������2�*p!W����=FU�&�Qt�e�#�ԇe�������>&k��s�;���*͆�̂&	ZL���vT����=$.�iG�9� ��kw���kxD��lp�u:���x��^Q�fr��i�@'�5���A�6�
���������"�j��E%��{����6�9���z`����A�>�J���Ƙ�V�)ۣմ|�Χ��b��;�P�n��k���n-d�y�ibd���p-�߈�����.�quv��ct�B�NN.�w�w{XИFe<͔�H�?*$Q�<=���W��|���y��� ��_|J�6��V��*C�X���h>�Eܮ=l$c�� ��=�<4w��[�_՜�&��_�\�/�x�4ʬt��V�RŽ�x�J�����/�Mo#�J��`ڃ���q
�FQ����ns��Ѳ>S���-�1�'�c#V^X������w'��૨P!9i�������o�o0�j]�.Ry��U��*�F��̗��DX�CЫ�^^������E>T������Er���1����ۣ5� �l�������ղ�X:�k
�U%�X��)�}��T�&\r�B�އ���OZ�
V����!l%*�÷4�2�uVi��/p���N��JҐ����lҍ�'6����g�}u���Z��o�V��z��aV�}���F!=���QT�Ȑt���vJ+���rrP%����g�y�^�6̪��B�����H�3aS��H���|�t�>JJP-�V��P}�iW������6�i2:�D:�����S�N�@k�Xg�K̇Ծ����<���T��m+{ݩ�ZmZ��:7���Zt7�n��@���2�S<'�<�2�ޫ�I�h+"��K@I*
KS�D�Joɐ�X∵MԊ�2�{�:͢��Δ�~C�8lY���(����c<?0�Ԭ$����7�:�y���_�˽EO.k�p~�u��%��ש�-�ī1ل�RQI�8` w�17�)Fɬ?��:j�Фa%��Ć�T�9��	c?��+���&���ǳ��2O�k�g����. �m	���)��R7�7*��S�$�X?�n|�F��hY���V�m�肑����Aw��-(r�&}`,|�W"0��t�k��)\<e$�(��۰���k�	�d	��s��T��6����2��rЭ�P"x��?ۉWV����a����Ȓm[�DhS%��#���G�y��gև�����|	�F_a�L������K�=
`)uc�~��O����G�>��G݉t��� ����j�Lv#y���R����k�EN��]$ ������-Q����]ӂ�����MN`yw4wݫ���e�� f�Me�<���QԤ&�c��Z�������̧><.�0�HlJ�),���[O�5�5:a=��n�`R�=��;a ��VM7�x�&"�04��`�9t�Z�X��j&�.�T�,0Eod���y��UI--�瀺���w(�|D���+��(¿]�ڜR�k ����_�&�uZ��XH�ޞbl�&�p���#��:��J��^��)I�����>�)ؔY( �&ĵ����ɱg^�����N���Tڔ˔�cK0��uk�C��fM1`de2��
�� �)7��`�ㄩ)�ϊ8����u��9H���ԏ~��Pj�܈��/��'#nu��$�@���EF�IE�`,��]��G^4��Z���WZ`�q�ؽ��8"y�0�<_���`��F��
�90�G*�Ė��*��ڰ��?��T�� �.j��	Gm��X�&1J'���:!�(�9�yJ)��`�LK�P���փ0���c�x��	��=���SP�6E��EY���Z�AAt�ei�N�I����)�U�F>c{//�kH����I��vx�vi>P%�S���u�9��c�)�<1�}�ԛH<7)������=�P�k� �p��2eJ�x�uQn��y�
�;u}d��m��!�ѕ��l
#V�����19�DE��^�E��5�dC5�=�:��\�2=�M��Rw�KdX��͚��hf��5�	Wd���f��X<��Nkha��*IY��K`,r,u{��>lh��:��w+jE�d�`Xk����kX�:9�ma�G�9�F�ɗ�HA�OE���%u]Z�Î�!b#���������]�֝�ĉ�q��6(�����/�9"Y�OS�F�1�f�=�7(.m]IT�͊��k�d�)�9�d�������ђ��'`~U��uZ�f�i�G���Z��y�4�++A��?�T��Ն��	�;��Kᖤ�20�Y*1�e��@5�2���i���,��n�`�|�^@�9�)�:;�4������5�����e�dC�&�V)H)b�CO���f�`\�e��RO�oRUW:��'�oҴ�h[��,�q�>��I<mL�k^8xo)�J%s	��[���(pm*�#Éz8�Cj;)�}��~5�'宋:���n��lҿ�Ge�8o&�M�⅖H�ׁ��+��'�G0� |�M7�bg�!�����?�J[�)�/��P�PK �ݛDMa���ܩ���>��(a9�"j������7tώg{�=�r����k��-�L90PW�����V*��J��t���a�SI�S?���:��ȇ��Q�9g&ðҦ��`)�b�I�}UQA�kj�_9����\�}v�*��c]�+���CV��~v5�7�u��-}��ԡ���#pV:u\�Z��4��g�U��]}��'Bs�*�ku�zܸg3ୣۻ<�);Q�Nm��0�Irƕ�/��R�cys�k���
�+��Kџ��Y�{ﰄ�I? e��4X�;C�n�7#�[}�%j���������O��Fd��%���s�ꔵ ����TSK����n�߻(���W-��	�ϰ+h���x%�67FD��0��g}�ݫ�O�v��&-̀���7v���!��4�hQ<\���
ޣ
Q�2=B�w���¼����Kh�W?�o����_�    "��Pߵ_=��_��bk��Vҍ�F�����]p���F��<L沣�:m�]�ҽ
w��<�Nj�m|R?�K��]�`(v��� #�Y=G�'��s�ѯ��qArBT���_>O���5,�-��8���`3�P��q-`���$�Q�&x��[s��D�Iȧ��K���֭p����q5J�,�$���x|�b/:	<��vO.?��e50�F9w�wN�Y%F���5.X�;	;�6Ȇ�<�G���)L*�`�0��4��!�2wC�+!�07��ɬ�6��I����%�&	�R�����K`��{
�}�Q+��.��I�)ͼ��K�ʡ|�;�}�z R�)��u��bZ/sD�J1�����Ӽ�D{���~�+�!�Z�uʷA(�7)�	�I��	��=jjl؛Ԉ#}@�5/���Ɂ~��X���6/;���n�F�V�k\}u��͂�e[�~�kUQ�nP!����X�S�K&�i�NI�0��F9�l�f�d	[f4j`-���'x^to��i��?�e���D������	��Yu��5x)r��6N��W�=:a���VS�7X|>N�@r)U�qՈ@r�3/�*L|�������9�����a���q�ș���k?�|�#�v/��3#0�??{�|�7�q=�Z^����,�TN�:�>O{�m��V0P�C��f�7����$=YX�tЍo��r���M��m�x)�����X���]7ũ��*��j`�8&�aq�=\��W�;�Y���R��b}�����3�[���m��n&]��G"���8��|�xJ��A'�ZW�+�I?�f�/C�%��hV�p�a߹��m2J�[ �Jȿ���(��$�+���`�R�CDJb|UU��jS��P��FV6�u������mܫ�hb�t,��ϝ��"4,��YE>�m��4=I�.g>�� ���x�ѳYI��Q��0K
:Ѕ��L��q��I�S v��+�ꫲ�C��ł��ps&500,��~�6YʺBE�v�qHh7�ׂ��k%b�Y����Nɞb�1�S
$�㫛Ej���I��V�q�i�u���)t�lS�,=N�1N����
�MӆG�5[G_�u���(�ʓIb!\}�6�#YZ�Kޔ�+�e��+�ʒUg����Y�`��.P;e�@����S�/�)Oc&�����/���Q!��h�>�+Ʋ�IP�bb�Y�!�w�}q�V̹�q���<ظ��(��n2�B5 S��i�6�9����Pr+���Q����K���pQ�II��"	+-���<��x���{���O^
�J�0�ِ.m�Ě�T�گGI���9n���Y P��L�W*� +}i�����;�+�7:��a�ۍ6s�+n��b(���f��d,��\"EWɴ��߬��2!�%�+�БXJ�1� ����m�h��"s�+�`�m;�;�FB�t�f�o;� ��-�eU:b�M!�Ā�gSHM�6��H�Fd0�1�!��<�.R�~PȒGOY䙢DYI{z���s.�l�Q�����>b9����j������>a:����g+Y���uhflZQS8 q���?/��9pg��uG����׼V���J
���Ǥ�i��|���{����e��K�Žq���Dv��I�3�	�����zոJ6�y-\�a%�*[$�빏��ܾM0p�ʳ5m����m�	�O���M` ��{D#n�,\_a' ��_X!������?�mwr1}C#�ˍ�]���roJ5eqtʛ;�LQ= �҉U��s��.���F[����]Y��o�;�-]���d�O��bC�Z��u��(?ly���T�7�M��ZpNho�:������`U�I��OP�k ������XEǅ*j�d�ӏ�k��e����̕�=�ڝO�e�ǥ���(����B��H�O�0-x���y�:�9����E�����w2�#f��0��LU����.���"u�usq�A]��r�ul���dH�~� gOօ���}�2mfca]�:R�e
��m~��lM�ߧ-l�(l"��q]��9�q�A?�K�Es�ш1�LKX�uY9]� ���I��a`���y�n�oj8Mo�qIB!uiB׷�S�Y��.�+�����L��L��`T���yڽ�Q����r*c]6^�e�Ê�3Z���7��o��K�p�՞�U�w!�	J7B�঺*Wߧ��cu3����dM�a`����N)
�3Ya���9�$��C u�\����+��,�PWسtX���.��ЉLT�i���*�_UW��r�o��C#Pަ��0���1��D&�>�Z�/T����Ǚ�r��.\�k�}�e+�K޵։REкL�avi���7��hN糮M�?Nr���f^�����)ϱ�b������1�<�3j,�����e7�D�3����ʛ��!�y����
ExE~��!�CfRf�fA���i�H	��f��cQ�Ki�kV����1g��C�j�{@�|x����k���n4��S��S��l{3�,�e*�0�1�
Sq�9�����I왮ov�D��H�,=����g�\�:���X������?m~qc��=�*�ڐ8u5/ݱ�Q�S�'o��/0�Z]�G��A���ը=`�#�-�7nm�y֨ؿjW-t��<�jinb�
+�%�k.0��'�2=+$u2�Ǳ�G��l`?f�]��7"cK�Z| !��)tD0�X:��@J�DSn�Y-�E��ϼ��ޔ��Y�ZWYi��Ӫ{�����<�&������hc>$˘K��-�KUQ`���7����1��n����oUVZ ۫�؀��{}}���*�j���N�<ƳN-�,p�C��H�!Q΀�U$ύ{}RX�}�PYkݱ��l���+�kp�B}��X�32��j/�W_�e:�$_fe
��$�RK�9�Ow����OT6nV��o/�5���!i�zz
V�.����_���e��qS�F���s8^g�=(]i��A���.��.5�!��>={��:��M����gQ�:�EY��u���|�3���j,K�qp7���?iZ��������?�uӠ5TX]���ɡkB��ZW�}����HK��$ʺ�2������kKlM9tXĽ�uz�g��No�~���������yNئR�փ�J)_u˰�쏋��:�����pb�n��,�x�0| �ě#wF�qk���@ꯒ�ZkΛ���e��30RwB���{�@i�p���U��Ep!�_E�.ɜ2�4ЄR >a/�V��x��	���][��$cmZ�'~e-�`�V��ܪ��p(�%}w�K����i��B�.��M�S|Έ�f��dIL	΋W����J���Qo�5�`4�~uv
"!E��Yiş���i\�6m�#K#��m��o�{F�D�"�"ώqc4�� 3���>r�����,x�W��C^��e��|u�`�Xw\Q��2�㬬��Uy��dRKC��	1�d�W;����|be�T2.&���뀑�qZ�p�v�d�y8�*����w����c�������X��pC�[���4�Ǔ�ڌ�\�TsPO9�I�$�)�|
j���rLs4�����,��*��z���=g���iYլ���tD��)�bRZG2������V!�����~�k<,:&ۡ�0�I���3yCT3@O�Z�(yź6q�8I�syV���m���Qg^R?����1��I�2X-��B�߈1�7��h��Dp�EEY�8��!��նԽ��G���%���K4^e�g!aƂ�0��"q]���6,��a�4�|�������J2�i�N?i{���\�)'pRϐl�����>��!�}�l�C�&�fi��&m|�_Đ��k�׈�)jF��3�z�E�<_��&���Q7����;dr�q��V�O��_�Y��%��]\l���L[c�az�[&i�s;㟱ƙ�(�F��]�Qw�<���驊j�Qb��P����nԫ/�n�ZM�[G�sWW���L`�z��c    �u��e"�0�\ݜP��>��֙Id���v�ß�����1���E͇��9GJ�&�R<m��@N1�|:�O�1ꑒ�c&�<17�:Ñ�}&��΢)���B�	l=�M�ʿ؜�(zO��>� ��k�t�B���r���H��@0p
[` _���3MTj� Lʹ�5A�a�qx��UOX~I��If���V���j:�?8��<�h� ��R��O����;k�L
�ru�/�S�v:Т���q�Sـ�2���j�1��a�iH1i�'��)i���v�Fg���������̲����������lg���73=�.i����f`�Ȍ�A�F��W�`=ߧ��_&�T"Cm�rB?i"&�J����������<m:��{��4na�|I<�aUÄ}b��[?��H�i��~
z�Lf�ִ���M�!�lQ�j�o�89�Ќ�j����]��[teg���Qm����vtb���ب��Mi˭:_�5l��8f5u����\��BG�厓y���g2ݴ@'�.^�Lȴ��&zs�WC���5i�ě�����i;����n_yTh�}ɋ"�E��y�w\:�t?tꠛ
�=�xK��L���3��Y�6	����rB���Sd���m#u�/��>���B^���>ď�z},��~Zf-ju~IA3�5�|T��'a�ӯj\�.��������}W/���޵�Pbe��*�2���� �K�miZ������ޡ�~��i���H��=�čm#b:�i=b�!.��J<%�T�oy��Q蓴'/CG��yz��g�~���~�G?�U�a'��\�0ђ^��ϊȌ��1f����I���^�7�o��߁U��ƕ&�|�`��+�.\eI��r?��eT��¨��]�B��
"p�c;8"[/z�H&������q%��d��J�,�#��u��&r	^�\ݧ�i�Gń���T��oC�)9�J�Q^�&�wٽ�D颤�Q���Q���	���4yWj*��hhY
�!�h"����(�ĵ�FF���$�����E��2�Y�mv��Q��6�G���3����s�t
bU��ɉ�=B�4��R��~���"ܫ!�Li��k��w]����}�`g�����v'�Up�����Hh�G���1rt��\���3]y�E�@M}�u$,�[^0T/=�ô��x�Bm�"� �L�~�K)�w��0MV8�NC��uݍ�]�(q��_�y���Zq��BdvG��Lc�M��u�a�⼴����M�4h��+,U��E��Iz�s�Pq�l ��D![r���\F�����9w��ݸ�g@��
΅��}=��?�q���*�j�O�N�'/٘a���s�[�K���j��Gk�?`����
*��jz��
Lw?/�P?�䷼�P�.' u�� }��1_D�%Q�p*X�}�mԪ�c��=�Ɣ9'�6�8����Ҹ~g&|5.�z{�ҍ?4_#D�R�2�	��o����<�� ^g��\蒒[,�|Q`�ˬV�cC[YA����U�5_q�����
.M{��A=��F�e���ҳ�D3���Z��Q��Q���C��`�F�p��TL�%��t��r�l�iQC�6ތWﺟ��=�#u���B��KC���r�]۠�~s���
Y`X��p��*�D�QG�[�Nr�I�oJs=���	�Ǜʔ)"�z��e�Ro���= ��j�o'8�~�0�|�:�x��1G�L�Z.�+�]W���t"Zu���,��Y�)ؿ[��O >o�{,��K,��D7ʈF�|����0��0���=2�2���u�C}��F��i����޴�d�@G�?�*�F�(y?�\�^�`ö�z�ɿ��}�lA����A�[�o��|�[2řZ�w��E��t;�n;p6�H�%����®��p�ҭ׶�Ɇy���0������F�C����g_}�}���Ή����,٥	Bu(��n��4a�
 �SoճR}T�B{��8���ϡ�Ef=�a�p��ݏ^!�d��VB���u�!��M��(�����c��t�E��Ǝ;���Iߔ�$��I�.���l�G�e(,)Ν�VO�^�2��j�����O�5:`�&`�Q<,�t(��s5+<��V�(9�,-�s�)� 
�B0ڮ�c^�/
�I�s��w��6����/c�0R n���(��S��p�~<�%�ʩ\?�Ȱm�C>C	��uM4et�b�l ]�R����5YEV+#��,�b���2CТ�"|��	����j��\���_+�y�ܓ$%!*p��Q=!i��z6��.�3����Z6.�c*�9l���)m�l\��n|����fE�c������
I�c_�ZM�L��K+lOp�G|���u`'�M>t��L�K�V�:n��)҅5����t=5�)2Z�@uDk���F�Y�b�ɯm�л�0EE�IQ���pg8m�?D�.��: ��y��ۄ%!���:�OZ}�-�6H�%BwR���@u1 ��m�՞@���)S�_̘��FKo�k�É²`(ȋ}��D����N�<5�-�X�iiZC'�>V�1��� %���D�kl�\�Q��΢n�́t�q��v&MeK��(��i���dLa���pم�hf}xe���Xø��҈�,>��2ʢ� �|���H{kn��D�C$���iQ{7�������D���K�h��4��0o�&E�F:�:�\5�JEH�\�G���*v]�w�i��娄̂AB ,�x�QkUo}P:�	�Y{Q�h�<���m��z�L��7����<-/�O�Tk����b��jF�Q2��϶�E�I���S�M��o�ò�3����e��֕7ĉ0��:wXtW����q�G|��o)d����i���`#!�4��xxUa��2�B��Σ���%�Hm(
 �U����
*(�jZ���HRI �0Tp>>��LBkB�z���9�C��thc.�[�Ϸ�6�<�~�Es��RH���vk
\i8ip����В4�@�;l���e=���TIzA4�&�H9f� X�0�X�z>t��8w�7)�s���iIw�$�!K�{�Di�63�q:�:?��G"k#%�va��J:�+����꺘'ݿ<���Ym=��bگ��uju�� �;dW���e��&�m1�{�P�{T�@e6�E��7�wԽ6�	,c�-iΆa3OOQ��͵lu��G �Y��Ј)_�nt�W�ݼ�ߜ�khJt_�MɌ�\���6��'ASѢc�"N_�H[GfiWц����u���d��֝R8WN���)3�LS�{6�6�M�%#K�+"�w��|sZ1-/SA�1M�'C-�z}�PZ�+QA���LѨ$� ӡ�$�7�Q�t�,�c�šd�w8�AX:}|�MP�����:捚P����Է�S-�&�zn�3eYط���D�Q"������Ђ;��ɲҒ���;*�UC�Y�!Y��l5k.P���H/K��_�V. Kn�Q�Dl�v�d��}���{�O+��Rƹ֡�G�L6bB粉ƃw�#R/�tpkZ�$jdRf�0Y�������EbieUjp�{߅�"�	�H�PD-�k_�f.8b[dU#f2�A��	")^V̋قS	�&�{Y�P����"'���U�~U:��L�\ZZ�f�Ưt��B�\\�j�\�����1�7 �֑,t<�Q�r~�D^N�g���m����:�4U������
��+���}�n|����NsZz�����mJ�|��`�6��5 �i��Ho{��isU�Y���n��e�³uNĒ�4�������1����k��r1�����!P\��S����H=:�
���o?������_>%�;%s���\��!c�U����DX�Ye�d�����֫y�o�S�H�}��i���>``�d(��pֻ�יfu�`$6w�����xJ�w�ڰH��`[�������qcQ�0,�K�tӓɋ������,31"�ӹe]�2��QT.]O�b��>.�+I^�~���1��k�����NK�%����>��s'�t$�#��l�o�^�fJ�I���Q'x>��g�]&�ij��%u>    cT�)N�9&���ҼV���0Ior�0Ġ��؅H>#�>�:���v�w�q��3��(����R�V��G���vB,I׃"�>����;
ک��f-~�XR4 Q#A��m5�*:72�:$d�>�Y��%���)�j���H~�5l���V�_7Y����i���QH���Y�U�-G/�`	dsc�`[t����SzH����ס��v��+�k���㵬�HJ�/����R�6����YݏDV��_>��t&1wل���u^�+� R�ub�H�c6��5�&��%yI�Ԛ�A�pF6��Zs�׷ڪT��qC��k�m
,u��'+�09��t���d���7Z-�J@YxOb���]F��`�{�1<�_���5X2�-2�0���Qٖ6t3�}L�J�M[�nV�vE�,# �\a��N��jʯ�=X' HQ�FB,�-7�%G8d��"*���1>u�[��	` ׳=L	j)Z+�t�������жV�nT�=b�G�4
������.5o�)J��\O�i�1MVZ���r8������O�VE�1��V�C��L������݇�QǦ�����a�L��{�$5���,�:J�%WV���:����^	\d9Φ0Q�w�P#��@�H�ԦhW�XK��Q7������h��j0dp������ع"&�ѿ��h�5c��}i��jw��\B��"	e5eԚ���u:x߆�ܱ�d��1Q���x���D&�����y�_��c�<1�`�~U"W�oJi�j<�HY�1�}U6���N� ����YԷ�&���V ڌD����i'�32PS���KJҊ,D�T����	��\ݮ�j��o��V*��	鵩�Q����^�BdQ���<<��*sTڠ�7�~�1��JZo^W�D��u���>�j�z���6@�u�/��AO�����*߫��;1�-Y������?�ϬVg[�����!�EVq�`�F�l�z��)�75����
��.��`�lepL��I����:4���^��2�y���/oS�	�t\��M'��1�{}4���vH�<�O�l�;�6�Hp�3�tS�x�J��g�e��c5��p\3I�X^r7�֟��v4ܤg�;2��^}}ް�a<0��1�A�mN攬.�hj����I�#�w��+�;֬�`�\�����]�E�.�1�&]P�`r)���p��nG��P*`ةt�yiD�/"�c��*�V�b�wuW�چ�dtl�p��c�y*"�Qm��[.{��yw
�Yo�a�t�˳���M�D�.t��0���&�
/5\�*�4i.�����س�ME�fVd����F���/c��OAZ2�`� ����A�%��j�S�j�?䋌2��"��8���X��v>��w���l�H!)�=bp��KЏ�aɤ�X�nt����Eҗ�Fs��-�N�I7�F4�7�>�׾mv�Q\њ�h��'?�i�����ŎX���綏rn�����T'"ug|��C�ode��������ȍlY�k���I3�̖�!�RRHz
�Tg�7w*��(�3"=v��Ŭg���t�-� �4���ͽ�}�	��D���4�]��k�3�V�mc�?�����<cs�J:fj좒26��i,#,nD.��TY�ӪS���
�w���=>Ϩ�����,06�L5^+G�)xs�N>�26C9w���1�U&������8�%su4��u�O��^��ʓ�s��8��(�l�z ��rɴ��;`�b�%A˶(Th�ƹ��SV~�M_m-���0^���tnڎ7`w ����1Kw�t<y4���h��e�z��6�M�,�����'�M퉓p{�PIW�l��sg�a�	T�z1#| �q9󨗍{j#�^�Wp/|�
�1)��O����TV vV[Q�s45�r��p��1�#�������թǏ�y��8�;5�\��3U�Z�g��eUHSիߑ������/Qrژ����~ޏ���ٕ(ڊ�B�F	�ݩ��d, ��r�}͵��VĲ]]�2��2���hݘ*ycp���Tʗ��OH���IBj�8���Gg���n�z�'K�M]a�~�tS�$)4u�����e��i��S�&��s2C�Z��#ֱP+w��t��~�H8+2�l���J?���+X_Lݡ�Y�l�5����Up�����O(�;&�KL|�3������	�����~������*��.U𾛦Ƭ������@�X����S$��1
���9y�Cq��z�W{��n�$��L���	��v�X�����A����0%
O(H�۶�������,FUM���g�zʊ�\~�4&�����ה�������d�u�L�tx?���T������D��tW��Hp��$��U!Td�؀�z������S/����+�;�<#��l�[��z�gh��ƕp�@:/G�o�miǢ`x2#4a���~��<8C8a��!�c�q>�;�8���2=��
��V�^Fŭ__^R�����/�(�z�*M��AK�8t���X��!�Dff�۷?����
w�G��r�q�I��Ϙ6(]���ӭ�����\�~�ܩ���,���[4|�П�>X ����J��#�M��"�����+����$�+���吺�m��a��ё~�����J�b��F����S��r(�DǙr�|�����	\
Ӽ's���
� �Л�J<!�q
0��6��OD�����)�ˣll��>�#~
��->C��lƴ�m�7/��E��X����wI]��(�gv���G���H;�����P�d
�����;M�Q�<
v�0�i�󀴓. }��2%u]롟�2�өkKg���R�?,��9	��cU15Ý��[d�u��pO�? ���ctr��`�<B!���6���BE�����̑���Ѻ���o��0!E���n���._�J�Ep$胭����$U�mFI'��7����
\
�p{�Hl�;����f�Ǯ�OϬR�=}����D�$M(?�&9��ۉ��7%�B��*m�w�C&M*EA�mt�Xo�9��xq]��ڢQeu8�#,�+[�F[��vDW"�+^˜�h;�7�:���i�3�)��<�����Ş�sH�wzt�ہ��DEw���)X����v�8�Gd�M�������b�������p�HRi�0X�1) Sa���C�M�m��n��#Ę�w�?)�p"�tAB��>���z�1ҕ!��j?I�Fa;LL`a�~�\[�w������mx�����mF<�pQ5��z���>�{�����+Ds�1!D�!�8��MUUV\Ď�f$=��̬j�v����˜��O���q`���p>A�B���ax��7��f�y������凱R~H�(�hk�lr9c?C�����BI6�a�k�<�	y���a�#9��>ҏgÝ^�>�VHB��!{�gPk��Z��܏��K�quQ�1�&\��)�ƽP�&�xt��)%o]!�V���Vg�6�N ���k`,�t�i2 W���Z�`��w��c�:�yƑo�ԕ�"5�;8���$�n:�s]qDX���{�������^����핦j����03��N�,����U�O��;H\��"ʏx�
Y�F�ΎE���y�be�g`+�[����}�)��`�z���e�#�Sy�Uj����v��������A�)td�}0�Hz�}�P@T���N�ۈ�-J�?�_����с�"!F:�* vu(��"3����Kd�vȕ�nzOF}D1�	�^���ػY�x��쵄���_�眭�a�Yz#
�E�F&�3���I�C1�*��o�2?�L�����"��S�;q�q�����rT8��dB��Q�׀-R0�?�nKJ��#�Io�Q�-�:,�`(�puo���9�R|�ǳ!��.Y�A����^ݟ�E�B��:d�~u�1M�o���A�o�\F�%Q4��P�P+;C� ���2��X�VD�M�V�v�m�7��Zr���1�w��.�0B!0k,n    ���S��8������a�s諿Q�J����� ����y]��-t=���(���o"��M`����Vov	ex=��B���X*�~�@Y�S�;5�>��O��G�Q�	�u��0�6+Sw�2zy��e-D?�q�cTO~E�x2q�*�b��~��/o�*��Ӊ�꤃_`����hvn; ~x���|�H���_�p�
!���a-gK�=;�@G?��H-5��?ɵ4�q�D�G�� F��d�j�a��zu�K�x�]68�0�F�U|� l�K������|Zo�x�xA��l�_��iӧ�����FF�G/��%8ʗ�)sha�`z A���#Muib�r5�e|�����v�!�u�D�'�&�f� G1D���Y�Z���(:g`]c���HT���=2��m	ƈ�G��X�˨��z�-�{tJ�ۣ��S0��~����1���V3�n+��d��Ԫ����)���k��0�3�,l��8�W�n��~��~`j�^��.���p�T�YA��Lq�}��L3����*�Ab�L&�>L��[n�y�@�и��d��5���	�K�Sq�~@���cJ�=<���]��p��a��X�������<b���vC��t �c ���m��6B�,8{w��C'&7��1���C5���A��v�~;�"��[�C���>,�֧�60jV�C�2.�9l�
����e����"��d�*!��ۨ3�V�nB�ɷc�v�A��>��e��۹�j�rK89�f����a�Ē�#� �|]!�jnQ���y
� C�`�yY��"s�kd����r=-9s��u]{Zޫb�L~�f�}]7p���}�S)�)\O]L�Mv���R� '>f��J����u5����@��<-;�\�dJ��8��d�����ة$h�f?P����8~�c�4=;�u`UD͒};6���#���~�D%��[?���	����P�Ii���Ѧ5l�-3$�v��v!/h�Z7��:~>'�g\���.`��s!�	��)1��1JY�Ȁej�~��9�g��
������r�dF�����ϰ�8��QG�-,|���n�̟�y��Xl�l$!J���Z`4_�X�u�NVH����e>�=CY��+w�H�%���Z���Bŉ��}&��0�-��� ���2D�Լ�����>]�w�2`Ir��L��jY�A���(鸜�!��lU�!���;���-�}��O�Vp�,=l@6}��x��z�iD��;p���uK����gXȔ�T�bAa-]M�}����'��W��l" ׎e�m��L�
B�a4�S��Wi+�)��״ɊE5�hխ�À9���U�d�e�~^�G+,?����g���}�VbZ���f�,�ӡ-��p�V0G|Ό�H�0���.h�^�d���CV]��2�#n����{/��;H�}��eY~�[�d�`���p4USw���M����<����0l�ie�j�5��_:�)W'�� ��B�H��p�f��ݢ�p0�,p�� ~�6+S1bY0��6�߄��8��z���~)�DGu�'?7�W(9o������)�.�v�<PU�"�LF����4���q8�SI��4֑F��q��M�1S!�3��D�
Q�7�~�q�\ǉSPs%A����n��~ܥ��
Ƶ�J��W�<�pB�`���`tZ��^i�|9G��J�~Nr�>�C�ૌ��+*���B��z)�B
��n�_�~$fd�u�u����!4iۢBVk��z3�6	�����	�p��5������&�V'�øI���.�r'N����Rt�|Y�F\=2�÷�F�M�"_�?Ȱ��bz
{�C&��;�ٰs��(��1���|��3��]�����,�v���z2��}�˖�|.XYX���A?�~)��� <#$����J��)oyk��ݜ��03t��q���{x`������3"�ˈ5�����y����{?�����h��r���}(����!�U<:�~�c���>�&b������O��l*a+�?�fwW�6�K�ϵC�&F����z����b��Q�K��-�0po�J�!�O��r`�jDm��	��c�zuyڹ�[68�3�uP}u6�/P64M]���\�ڛ�����L��S�dVo,� ��;6���I��dy���Tޫ�J[�X]-���ۏ#���Gحy'�A��j����xt������(V̢��<�aOe��T�
Lu��m�L�V�i���J ���C�h��Cv(B�USS�mn�S�{�B~�$��Y��{��w!�S�D�!<h֓e�&���h\��.#�ulrR�F@��ʂ�tq8#@r�׆>O���GDAy�sC����4�fW
�Y�i0/�Q�hy��S�@�������t��-`�;�31�GjfC��<�o>s�,Km������q8�G,�g�_f4�At>m���)�0l�������@jNl���w�d�K�μR	}��)���~�F�kx�ߌ�>�b%W�����+�p|"lM�B}D��YB���_#ms��'���o��>�q�܏�t�Z�L
:̞�z��[Z^�Z]ƑRO�CB��4V���e1�0�J;pp�j�!Q<J%`�s��a�aɡ���5\=�q�̖�5��S�"��*���m�\���!,��>�&�	��z-F��~���E~Q�ȚVX��*��yH9H�yoe�,� ���>Cÿ,!7-&�-~F~�����Җ�%�$gUϦUl�0�R����2�^�a�x�S�*K�j��<��V?�Ăl�f�`aEWې��?�c���,�a��%6�=9Y��
�*�w�������Tk<m	�)�@o�IbS `��5{��=�{!�MQnpZ���Cȴ��u���TY���vW�dj��<������~�K�S)�z@��Ú[&�W�B���o���c���+o,�l�ʰ�N�	r�͖\���.��GJ����2c�,�X6Ҩ��{�T"N(iٿo`!qo84V��2K��iNʆ�uv��#�]
���e��N(��� 3�a�� gɒ6	vƻ��c��e��T�5�=���U~]��f)�.:�����1RE���"I��]c�d��n�t���X�R/Y ��ZY���nxJG��a�{��ijA�-�)������a�����x�I���-�)5<����h�B�r�4i��+�<M�F���Դ��ؠ���b�]<��\^�:��H��E˞�I����8<��0*拍����AׇC^�`����̽�������I����N����4K\b5�\t���0�ܧt�p�Xg�#c��1�dU����������g�H��+�M���S��i��XT"�d!h�yRTŇ��V�"�żl�����H�^���-���O�x��D���yٟ;Tq?��D�A����f��EY>���&P�a8`~x���8��H9�ZXl�iodW"�D]��6a@v�#�]��y� y���������1���!���Q�����L���Z؁�A���`'#�H�)Y�AԶ+q<��,p�f�uQ�v|�xV���y��]}�p7E\���t�ܶ�����Y����1��>��0�1�H��-����6������]�\�RwIxф�Dd�t�d�Hb'�L��4.k�F�)ռn"\���6���py�S�Oٗd���߳�m�}�G�#��-1��D+��i�����`��sR��ljE4f����[��Woc��*>�y�����[W\BXZ���]r�n|�n �]��zd�x�S�՘�؆��vJ5v���N��#��i�4�>AW���©;���#��`���ե#f�wl�muJ�R?�q�o)|-���O�@.5��\�Λ�t���l�A L!P����Tv8~�-�h��zP�C[P]�-����}Zo�Зm��R��J4���U�,sV��><�8�`�j�s�~S�	�l�ң�1d�n���/���    z��8�d5�'�02e��s�@�9m��b��-�٢��l�%9OCh�l%Zǩ�:;�ړ�SH�8����],�7�E�?Mx/�_i
�h[Ga	�c`��hQh}���Y�װoު �Fִ��gj [�"�N���zH1VUT�l���xy�˨�,�ɖ8�J�(�2���v*�Ո�Y����)��]]T'D���>E]$�񢮹��Af�3�5�� �6�X���1��]�i��X�)R��;��'p'�3�T�d>q|"9�m�_�Xo?�H�q�q؁P��w��G
K�'0�}��c��H	yyո�|3'♮���¨��)iw4l�7�!�/�؁Smx�1Q���K���՗�&�W��uњJ��f���v6���}�+)�K8#t�"W�f�i'�ԇ����Lk�Е�
Y�����x<,����>�IQ�9�n�w��	w�3~a0������g7wZ�>����ϼ��i�9�_���A�ip�=��ߘ�Ylh�?F��������H\��`��4߆��^*�6�T�$.��(-S�.��f�)�[�48]j@��I��(�	�9�a����dтFb(g�)0��i�
��Ŵ�1�(��xb+�,��f���%�-��>ݼ8�0a��o�Vr� 04��۟�P
�J���
 p�%��%��o��նP��q�=�3Zf�|����JD�$�;"wQ̱�\V2S����%�6:xh���8�sr�ɪ�E�Xj遙�RP����7����t�X"�;��vaGYVi��k�0�Ud]�����z�E�D�p�x���b?��������j9�N��T$E�4$�؟��GF���dY��㸫9�?C�pr���3�֗��'n>�6����>��,�U�������N?�H���+uk)��aU�>C�Yб!X��s�݃��̛��䁤�Mb��9.�l�P�QE�T6�׷��8�T�Vج���2���j�5�|�JE��R�k��]�
��� �����;H'[3���FEUa�C�q��k`��O���<��52Ff|	Q�H�Bi!��ņ��v����-��:�0Jv�h,���Y(�!vR���L9�����A�gf��ڱ�&��qQI�?9�H��M˭%��p�s�'��K�b�������	�Ŋ����#4}��bz|��(}#�~��'+���:�w��t�WHk$�K�����x�v�,�e�!)����xH�$��1`���sN{���$���f3,�bE�oy��I�Y'3���y�Qǐ�+���_Lې�9&!��d""�mw���¬(�Y���7��� �ezo�V�{y����5�b���Ȳ��X�m�C���"u�X]p��cV2�\_,��
~�~�y�$8��	�gJW���ĥc��/l�Շ�Y�^�(U�*�$����B���"X*���%oo�,�F�C�y�y����턪7���c�5z��*�L�N�E�sv^��l�΅X�|�Ѿ�ڿ���F@�p���<�Z��]��F�@і��D��!Q�Ō��:�*s������1�������(���,�ܲӾ��y�3!g��fS.�S���ۍ&_�*�RU�O^OOY�Y��5R�v�CxLGQ�_�K�p����!��=C��J��8~X���6��m�էs��S:��,�e����tnw�t#��.hΛ$z�Qo��\T�mo�]���%��fY�H*�y���.M��<�@�p���}���<���^���xZ],���]]t#���XP���ҏ��>�	�����?�,J�~�<2C�����I���� ���j2,��(s���@��p�(�w/r�`�C u��.�u����2i��I��X��WY'����W�yJ;�M+JS�r�+��sÚ��4��{q2A�ż��g� OS���ȯ�[�f0St��˴qr\�1q��/��]Eq�9W�bF�D��|�Ԗ#���T�Į|��\���\�-ؖ��3s/�_WD�mU�nN;ħ�Y|��a��*e?HJ��hƶU�x |���L���_������������{W�C[;$1�^�c�%mzy��m�In˙��'��b��<K5���/�x富w�x#7	n+!�o���k'{��x�Xz�֕�u���0*�f�u���Et,�d?��'3G�0$w�������2ڊ_�1[e����%�����^n#�R�����šV�۞�߳Z���?������]����i�+jel�n�Wo�锐�~ּ#������i�m���!��SۦZ�>Yw�)򴶩c�ϊ+���}0���MC:U�C;4z�Q68�q��ș~�>��Vo�p��b8�m�h�͸?��ߖ�lmӭ�9�N,S�"��yo<$���H���/S���ġmL(�]ep�m؊*�Ќ§+S�V�N�5XfzE,ajE�i,�?����"T���;���ϐ�b�'�0ސ�r�����v@	b4�P�m���H��P�r=(z��c��p��eD��,��T(�nOpC�n�Bn+�|���Ϲ��'&~��h�y�O,�`[Tr���k��{�W%�&8*a��W_O�M.RL�����j�"�a ۙ��L�w���O�0�}�R�ؗA4Ek���?��nI?�{�ΎZA��8�'=�8.a�o��Ǭ��f]Z�Wg�[ԇ{إ��z�eS<�k�e�&��i�guY�m�0���U��j-���jX�U��r���m�z��{;_1߆�	�?����4yh�{��������G��c���(W��6mwV^nQ��V��������m��}��9i(:�.�%��Wo����k��m<@DAU�w�2w�P�]�/IS�@ڮv���)���D�y���?�R�w|XQ�;�rUɇ�vr��ag��Օ�Bm�����]|ɛ�ܹuA|���=,��tWDu��j;lR .�y���D�U�I�"uQoj���v�x�#Ö*Y�Z���=j��2�6+m�ʎ'����0o~��f�8�
Rw7$h�>|�S��)���1�7	_�!��GH'��q@{���[nۺ�����ɰ�g�B�
��3'����C�7��秬�ʇ<ZAô�w��Ï^^Y��@��u7��W~� |}|H�&j#C#~]�d����:��a`~HǏ�[�X���t }PG6G��X
� ����a��Щ���o6��ݣ�ļ�����Z�ȇi^�,�P�t���u�F��EP���g�Au8���e�"V m�0�O����Ѻ'�#��U��ջ�­���zY��Mh7�c�W�������/�7Ӟ�*�~���eo�m"�(���u@���G�ۃ�qЀ	S���(���7��t9�!�6K�l`C~�Q���4���H�4p�ѫ��:F����)�?�q6� ��A.�����:D5X�i�ɪ�O�
���Br��i���������E �彙�6���	�h�$F�K�"��{��>K���)�S޵몄Çp>���b���i)����>Ă���vU��y?�9*�#N��`g��P)/9�:h�\��ǘt��Y.,���� �K��iwFn�{�7:U�(�9�g���S]b�9L�����9q��6Y���3��7�-�9U ;�t����U�β7:ŷ=^wr��#Q_ȂF?��*�j�i�e���ܮ�ĀoF�x���D���5;>���aƮ	����˂o4�/ �C\�>�`[�6�BI�c�c�tQ�9A�u���5*���,as�]`�o�v�rIO>(�5�f��O{�DYGTv�!I�S!����DmiW���W��-��9!w���p"xu��`��9��x�Փ:!�r���o}""�N߉�#�/��z;	��bS���`�et��넲}B���x�����\�}���1j��%�>k8��fŏ���C��T�q�*r�w_@@Հ��P"�_B6A6�&����8�3 ���G�+��;)�uR�pl�̰u��6��I�\���5��~��CH���%�)�����ƌ    N�ņ����Ĳ�/�?չ��;��_[(�6][�����=��KTA*Y���v�`7�.��hX�m�����:��f�
��3𻄇�{���׆�Z�׌ �;��y;8��L�s��X]��0� H
E��P�|=M�S��e�еz�����vö�>��Y�k������r߯�Mm����⟐at81�V3ͤS*������a��=� �k2"���G7�.a>��u¢/��Y�M�w�t����4�S^�J��[LIΧ��(�bֳ�:�A~�M�@k
PQ�#nd�^���Z�˝�=���PD[^1����]�?�
*�NU>"D�xVc���NՎ%�b�*��~J{�͐v
�\��s"����oT� u9�ɝ(��:��nH=q��8�����f�;!�;$��F��A坂o�	��0[R��=T������c����+i?���K7I��M��
���r�&l�#>��;rz�����MV%�Q�9Į��h�u�	ߐ8�yy�.��;C�����`��@KOU�Sb͈�?:�z9؁�+�.���|�U�{p�{�%�k��-'I�Ëq���Kڃ���qXk�6}Fw%�=M�1��`�(c��G���'@��<���+�n�d#��5�Su%Z�L���Sʛ`�z�/�Ï�1(�����9��Ӽz?���~̠o_,�&U_#�/����֙��"&��t� �w#ר]ʦ�H>TUٴ��y�Xl��WU5����f������(����qtS_�x�H] �U%l�sm�S���UI�C3�`8]���(*/����VPE�\UV���q��3��{E_9R�ωF����U�`H�ZS@nT�g�_}�7� ���V5F����*���K�U �����VQPo��q�b�y��s~�T-���2uVW�#0�>��;�� ��ʯ\��ɰ�@����]U݅-��F��+�o�Za�����nxH���p3��h�?b��z�n�֨�by�\����#5T�(/�Ȧ�sT�«'�?NO�c�,��Ƒk-�-*�l69״��!{��T"�u�d��SL�)T\8���,�*e�T�5���؏��6d�{�(Oi%-C�Y7��r�9�"i̻yX��p��2�Q��Uc�8�Mv�3P=���H�{W�%����Sk@v��y�-�qJ4�&�/����(����-��NJTb���d���س���3F6����v���N�nS�0x���~����U|9!�7_�!������	v�"�X'��R���/~yj[�nS��s�������}��vO�f���c��#��o	1��q�5��Dp�uI�/1�����{��M��j��������w�@�h�q�P�&#K�Em=YQ���ڗ��1�;G�)�C���/ɪ�Ӭ.G��QZ+^���$�F&b�| 0�9D_�	��D��:����j��W-R�Z�]��+��V�q۠�_R�؏���Ӷ�w�=R�FtBW��)�y��}��rZ�E�Z�* s��	������: �ےLa�kp.��ـ�(�	�a�����gBM�J����ÉF��\u����΄W:�{�^�}���?��{>f#_���|8��OZ%������\V�����pw`�p�jWΙ)K�`�r1�8�J9�(3�{+"�A�+P����3�9',�S�r�!<�1Vn��T�]o��Iģk
�R�S�	=��O��@)��X(f�W�)�:��&���/������빩��0pJ��'p��g���2��R��B6�C"�S)�-9�b-�!J��/�q;�O�ߗS���޹oT&�l�hݟ��)]١S���n��]�<��5�pT��'g�B��p�w1C�T�$;a	�4
��N嗞 -W!�C���=�J1Z��n1x@8k�W8������Ĩ��t?c����u+�M�1�q�at�k$缃_r�4�%��5�D�,���\x�I��p{LXM>��<��D����&\(�|m.����7"TB��d�)�/Y�)�c�)xΔqNV'�"�@3e:���V7�=��e$:
�fg� u1C�L�?c�E�n^ʰ�W���Ţ-�\W�u߶C���A�FZ��&J���˺
uI�?�&v6�=�R:d�δ�+�z��!������qt���U��K����.v��3��0E��+3�x�g,���P�����*�]K���(�����uebNJoR1�5�ɹе�P�=e#��A^�n�p�[�OC|�M��]%�
e��O]K�m��[x�.��8���tݺ_?�1+Ӿ�^S9��u(Y�!6�9k���=�5:S��jd��UW�v�gm��a�ǧ��Xn����p|N�0P�zu6"�
�3�$���u��M�1])S��A���W��4��qhT��*�3����W������Q��g�=G2���MxjPK�jG�\A��O7��(>���
���.�q��$@ՍA����@ /V��(Ai��3p�,���=��w�]q_2ļC�K6߿���K.k!pl��xز�.�]��4�d�~6[J�k���,g�@����a~�6�yŵ�@�Tv����$T�J-4�#�k0?�$�-��0�F-��c�L-+����K��R8?-kH���_zTA�-��r�/Բ��ns�$$�ؑ�#E�R~\���TE�����q��4�ϣ&�ލg�'4L�Ð��V��y���Ùq�"d���ʾ_v�7ɜ�:�e���P	�(Ii3��ᶷT��/9�u�����u�#6�v���h��:C��z7����Q�k����_�w(B�E�t�ǀ��\�9П�st�E�m�s��U��R�6~{8Y��X���
��[�!\V�խ��g����Y��U.RQ�l���D^�����(��
O,|��?��n�d��mڲ-��$6�S�( a���|a@�J��
=B\�Oq�Y��0�I0<"���~9@��
w�Gv�gч�t�kȄ�X�YwA*�3��]P�%�Nw�B���s���zݥ��ˬ��}����-�#�[���>Q���X���������z��?r򊲴���AQ_P14�X95�V��R?c�0UX�Cc��F�o3�!ʭfY�[<�#&|)l�]u8]�Uҳ4d,�$J�4��]��Fl��,�R��LZ��r��%�9�hA�xuT�tig޿��̭1�-�����)�<d�|"��V��R��S3��Ɣ��e����#��e#�My�j�l��!n�-D��[RwNB8	E���5*��0�鑉����r#k�4�����Nu��*�.��=���Յh�6��AZ������Y�Xc����F~;_�M�e_�$��ľm����=h�R��� �+y�4jTZ��~��'ց[Y���$�ڷÜ�y�h R�N�-�@�9�NYX���)��htk�a��{ۑ�����Xc�FǷt8=}~�L��ֱ�a���㒂V&�b��������x_�T�/o9L�+A�A����+�1	G��Þ`��(�X����OsB>�]d�.K���ca��W�%Ra-/�[L)#�H�yc*�ն/~d;�k��w��L�%fݏY��1+��J��ϙ�"�4u��-�$SZLޮ���{_!2��k�>=CX�ZD��7�|�$V�R�� �c�W�-�Iۢ�F�����D��]C/	�M�����$<{ɈfP5��o�]�9�E��������^��Ĥ�M�rDAR���𢋋�j*�U`�tY����MS;l����i��'2���gL#����epWS"h��y��I�&�n3F��+�����:���åʝi��l��'Ľ�ʏ���Y���1 <�9E����u�ٌë�&�ۗ���=�)�m�#��?�v���*�^�������)J4��fpd1Zn���V\���Y���n��G��~����8g��R�n�87)�PaD��e̪kL�  �-���� ���A&���jC�-<�^�-�����.Xf��>'*{ )q��e��i�t~��f �Q�߱�3���X��d1     ���g��lM�ٹ��R��vx�rGC_I����1%z���le���E���_%�E�dV`�Pt�T���"�bb�h*�E�	y��c]�����#��h�p�8��a��?�� (�{h=�PE�b���!�kJ9T��N���H�U��|B2o	·8H��ӂx�����J�`�FJD�1i<�#9����Y푑G�vr���k+���*�U�51�8;MQI�%�y�l����hr�x_~�a���p�'QQ�n���Ə���q�S�	l�����H]1���{�Q_r�{��pi������N��I�tpN�@e��?�9+�?��%�g��
�"^;�.���墨	�"���P�VG�ԃ���l�"��>����^�g�&��0���l�4�7�Yȧ�d)(j�^�u�nX�8���'Fe����H&Kd�Q��G���x�9�ΨH��qx��&�B�n�&�o�\��z;ݱ�,}s����'���T�p@Bgy
 ��-��B"?QL��s"�S�qZ3�7��x�A�Iߚ<�ElY2W-ė���ᇍ��`w�SM�*]�n�ᯐ��hPK�!<ؙ�~�@KAE��x(�}���]ƍb42�<�/�!�W;Q�5kZy�)i1SF�Ƈa�ٹ]�ڨ���Ð�I;
�a,� G8 ዃ+�@/�H����7F"���>o�a2c�����MϲaeV�5�[}�-?�yX���R!�ōQ��|��/��չ1.)�`��8�� Ma,{�3�E��'y��*<���$���y�OI�����������s�ꆗr�{?n�D(Z�Q�N�&1�u���y;��G�~��"�*Xw�a��5%fwzU�+KU����.��Ҭu�&2);�aE�ܠ��[�j7EGAِ��+��'(T!f5F�l<�	�H~��A�+�ٌc�����5W˸��
ei�D
���+;u]�bv���NN�9D]�F����È��0f�1> v�k����^ 3m�V��9w�͒x
�œ-�=�j*�:X]]�]cSW��q����A[���Y�'@(�c�+��2�1(�:JК�/,8��p�����@�wm�w��5[��s�)�,q���`�|[��t�ɏ����h����m���ƚl��D�����,O�G�؋
#�y@T��a��u�|8��}����
��|7��f�x�jv8�X������X�%��{�/��Έ�
^�]�diE���6�Q�H��Gv�b��e�fޅ��`�V�١:�Xr�+߃)�= �ᶥ�����n9Ɏ1ߋJ�x�y�CT�F��W�7�=P�����Կ�Cl�ے&%8�~�g#���������
�e0�Vr��.�t���U.�lS����vy���N����?�.�o�.T�M�3�B"J�pX V�v�b�s< <+i/:r>z�p�aZ�}�B/�\�[T-����n9�"������	m��w6�
�,��b��0�1��ٺ`�c��
0�ގ���U��P��q>�6i�5[ζu���i�'����,�)$��d*73E�p �ˁRq*)0�I�8�D��2X��{$��-��ۢ�+�����&�<���.d9��41���[ � o�w}V�lI:��,�K�2-�`(-k���D�W���kS����L�~��N���zr|�ڐ���hk.���m!�Cy�5T��3���Tp�	J�DE�h��s�,��`U{���1)ȴ�_v�ŝ-�G/�e��)�9��������gF�����l�0W��կ�����}���� V	�r^YL1����ݏ}߷�)�������3U���RI�ɪK�Aq3Qi����-n���."������B��O�m�8�X��c�T7j�CD�ෳI��%+���
K�a~r|�w�31�(0mm&���&�A�O�;ϛz��|��8V��ت��~�(�.���e�?�-�WgN��ڠ�c?�>���}^thI�,*S!�p:lG��޿�7M������5[zYP��I3�8��
�ud�a�D�+z`)�Y�\��vo��o�@�����lY�̻�- #��t;G�⤻���^�Bj��߹�=VFC���/�J]���.B��Q�R�^�U�d	·y��c�y�WW�ӈ�|i�Hz�k,L�����w[.�f	�s��pFW?�V��]����~�ñ1�/�>h�z�\�̷��(���;�>��Z�a*`���.�m,�ۇ��	u�߇�t��﫫���W��p�� K���3�����pK�{�kt�o����`�"=*���L�"$[��1�S8�m1M�0m�%6�J��K����p�	0Ď�
�ӠR�Ah(n.�8�$�@]G��uz��q���~���3������eW��u���,2�it��6_���*2_�pv��z7����~z
۱5;��2�������V!��n�����4'х_��s���1l��u#[�}�x����n3m,�O��/�Q��<�}��Ս���K�5�)�o�ZT�L	�)�7lE�߶�.��e7^�T����r;��)W�����C�u[�dC�����o��[�NX��O����'�)'���K�X9��Үrf)���mWH,�a�`�B�����6��v��@�'����LW\#�C�s9\���zr-gs�Ʀ��yCH4����)��u�܀�w8�S:���F8y �<u�$g(˨U��@���'=���i�kf86l3!��+"���a�+��>#�����\|̘���-��m�:�Tj���$&��Rj��V{;Cx�KcE.�rk��I-o]���\�1U
�4����X�/}�����km1��ö�g�jIwU������y�b\X�k�UH��#�"���b�����OYTB���`_=��N>��nW���~�BV�ڻ�WZ��)�v} z(P��֌�M���4Y?��ł �K4�[��Ю���a
Pɥ���u�;�_C���u�f�*���*����#{N��>��j������[�?q��	���2�_�2�n�H6u۪
P_�C��<d�0SNK��Σ;R5V\����/�ǣC[�`,2��wpΣ�eU�:kV�����ۊ����
�RX��E�#C[4U��K|_��M�3j�r��zp���tP���9N�%R���D=BPE�Q�|�U8�w�����t ��ӄ�~�(� ���\��>���B������t?�-F�M;Ar˷ˑ�{�����h�g?�� S�2\�6��@����vP����%�{3<ͩ���(`�,U"QDjfpV����
�l�ʘ#�ק6^��2�q*�����N}�"yCWt,j�Z���ۿY9��ٹ�7r ZM���s���[���a׊sm��tP/H�����L�Y]��J��G`����H�.�v�&��ml��ݯ��?~U�l`��{�1�L���Q��`!��IΣ��ej��}��ͣ{1�Wg'"n�~�C5U�.R
���m�Vqr����Xa��BL5���*t�����w�	�颷cwvSy���%�S)0R� 8'|s��Mo������^��^ �ue{������(��h8�D4u�zo�����M]�Bۉ��m��uQVl�ZѢ��[�x \_���`��G1���ʡ�]�����EYoܤ��uF�����A�B5q(>�EK	A�ܚZ9��|�C�a`�W�7V�~	��Ǒ�A��Tŕ�4���L��B��`iQӸ0{��0���d�A���4�<`Y&��-�T`(�~�/���栟����-8\����qXj�+�M��݆���3�-����DfYh���r��C�u'0ӱb{��
��S������XT�p��r⚝G�B9_�Mu���D���v|����|I!R*�Sru�b��t5�s+0|�H~:�L�mb�=���a�jk�&d��m]du�P�|�f;<>&�*:WJB�+:9&�nb�ӄ,Ц	���PV�b�O�X��]Y�U�<�YvW��3��Z4��K�H�3:����՚o�+Yq�&0�8X~��#   �>mw��2Nʍw�C�h���a9�SovS���n�|��e��df�����5ȥ��}�7�'t�68�0=�����aO�>$�C-�B���]�����G"�"x��P�
4=]O�.e+��y>��Be7�ie�
e�x������Mۮ~��!g�#I޷�u��oF;���"��!���rٌ�S����f��F�)x |Ր��#`g<����wl�W4]����n��9rݻV6�Z;�%fɓy��	���^X:�v��j�O�Ko���_���Z&=�]�����tn�T}����Z��쐫 /|�ܶ�|ߐBq� �@v
�+��϶!���2�a����t�x ��st��|�|F�3��.���kZr:0����LL��`�R[��0�^�����Qg�o�(���w�W�(��OvI�q����ٲ��Q�a̜C�4��ifL	ӥ�R�F�@;�zmkz��ؕ�!	N�e��s�3��F�\b;T��FW��cۚc���F�����嚧�����!YJ�a��BQou�h�X]Ψ�~9��F_]sK�f
േHUdI�������S�c1orC���up��F�+�s�%N��7x�Cyn�UH�\w(����M� ��ꕢAzD@ ��e�&kojG@8���U�E8�nr�Ҷg7�I�x)��S�Ӱ[�D!���>r�we�gZ7�|3�ƾ)�q��(��G���h�6�� ��VS��+Q͍��R�6����*'�w�]�0 ��^1$�ۢJ��1�]�JG`��	��8�J�P���7�}�}�8�DRTGj�����"�b���'���)`w�s���d3X�JTV��~�����d�_��t��]��?y� B�~�Խd ��1��G��e�>Q���gh𿡐��B��+�� m�Dr���;��4�(�_V�1�J�䋺�z�ZW��Dm?�~��R��'nq�my#|Z"�`�Z]B~'	[ç���s���rwp�RZ�ʁˬ�Vr~,����oD��~݉,����y��_X�-EoL��rH�/I�!�9���:�6n@��]P���7�7ǂ�k(]�Ш�2�@Յ�M�2�1O�E޾��SJw�&��i,IU����>���!*\��ϵ�{30� �
��z�t�˃�"�x�r�X'!���֪��*D�b���U�k%>RXB��aPy���Iq�1���$TKec0�!����9t���h�0�AD��u��	Ke��'K��n}׍Z*#�����5���,(a���c²�]QO�i���v,#؄��<v��|�'�l#�"�6�,��d��M ��_��OfF����=�+����CcDp��٧N^���̳���1����!����:�ウ.V*�m���|�c�;�����я��1D�*�h���g�IP�%]�s`XB�R���!����m�%��ל',��{;�7/q�`2KF�-�����	9בֿx��p���,W�m#��ݐ�uN~�n��ݡ��1[x:2�_������&]      �   N   x�-���@�v1���^�,�g<9��D!�b��f�ͥ~�a�8����%_b���؇���8��5lF�R��9H�L�s      �   ~   x����� ���v
���"^fq�9Dc"�	��O��b��"���i�׹�Ƌ[D�V�V,A��	�%eK%o_��H6�^�7*E���9����7��T_��'��w�Gb?��*���>3��PuF      �   �  x�Ŗ;n�0�g��@�ǜ%K�l��9Jh��2�6N�A
���h�h�b�q�|��!��c�>?f�7��d3Z�\��iʚ ud��{ � ۣu�򖊈�z�hb(���Eǡ"D,�J�g��\crR�L�6���r@ZA�z�*���"&��h[�ɳ@O�r�"?p�֜lD]�ێܣ:�]�[{Y�d�t��J�./7�¼�n�h�0� P�M�_���lN�,d��{����R�_���v����*ɕ�ȩ 	0�JzU�Yw�l�iN�i�9�5�y�x�������-t;W̧���KeD̑@��Gw���>�Ec� m6"m�fwh`.j
�m��fluG�(��&��c6��y�bGilaE�a�<۱E�QV� ���	�      �   �   x�e��j�0@��W�Ȳ�s�!�R:v�E��L�Ȯb��S�������ލn$!���$���!%���8s�;��N�;��Tc�����M�m|�`�Jʘ.b�$W�nW�&����9E�t~0��ZX�f��
[�,��w��X�����_'4����ugw�4�p��|��A��X��B�sAYY&(�sal���P#�U�����߻ck�(�9��.���b�q`      �   P  x��T�u�0�U��I���"R��_Gd �^�d�<��e�98��bYN{|O3�տ���cڱI�~�m�(t0Ʀ!���۹���85��p��9nX�53Ƚ���Ş�̔�1l��{�����s^"3��e����E��a�+���Q��i���� 7����#���[����Q���fk�-�"dŦ��T#4	E�o-J��HR8y�:��8�S2��	N����qr!��↋�p��E����5f��)\zIE��������}�/ �j�������}	D���Im��5��ږ;��q��8q�9V�}�����4� �$�      �      x�}}ٱ$;��w_+��(�;)#d���CLt�A�_��WVsA쨟��O.���/���<�G�}�)+���nP�ox��A��6�ڿ���)|._?W ���*�~��+��K2�8�v��+������g����S������	h��$�)�����g3��~	�=���,�R�,���dS�3���O*e~��ρєˋ��4���w�t|�A>ib���F������j�{W�W�jIC��&l�ޡU��s~��\d��0��L��M���=�����-��MHe�k��H�K{>u���{҉ǎ��r��=�%��Y=��6i�z�U���>�Y���7\�|tڹ����Y����>��oB�-�y�{)��Ֆ]"�j:�p�`aM�V>��/��@�{�:�p[�;��t�}�<װ�/W�[�g�ȸ"������F�������|ג���+u|��yE�]̐o�3��6���&�[�������M{5�?�1'%�%tD��s��q+��:�H[?Î0��9C�0�ҕ�;�������5�e���˜�v�؄�����RW\8�wǇ�Y����:�@8�Ӟ4�}���ߞt�`2uꖇ�*�|*/`D�R�C��g=vkzS�M��p�}-���������<�>�����_m�i���RJ�Gw<
�;����Z����m�V�ն��pjCI!�G�u$��0�}i��g�xx����l�J��~\S_�Yn������Z��^��J��r\a��/�3t˞��u�I��6?)�9ws������	�:V�y�=0����3��c�e�3��92���s��;�N����kDs+��%m�f�*K�_�pʏ�:0;�~���Br�� �֟{�����J �Koa��y(�dD���B�9�;�.R��pJ��Wv	��x���h��Z�ԙll�h�%��~����:	���jƏ���qz 6\�#�1��!�I���N���7$��JFx}�'�uBK9�"�.g�)(�H�rm����U^NY�7��]�@����^󰦾�:Τk�z@�yT���� �(��\Tg�7�bU����f�9)}���\oI�$�۾	h��rD\4��J ]�0-*PQ�l2̤��
����r��v� 饟�<Ӗ����&������nFxB�-Y�G�[�hK֧��lr�~�+d��o-,۷���Q8L| 9��h���&�8����k10����s(��ϱ�c�%x����� <-��:e�c@����˴y`zZU.�k@��6m��r�Dz���	��C�Ǻ����r���6�q��3�v�/�x"����47�rh�d����hOڻg��GA���+0#��p2i���a0;7�F�n�%��b�l_�T�q4�Tp���-BR�q:l�c�'5����{��P��N�qv�'�[�:r8�R�~g�%�050����o���a㉌]��iBg���_���F�_bXB�4x�3K�ۄ��&\���-<zU=�p6+��6)����D�l���>���u�h�ҧ���D4�e�޶�?�+��ؿ��@�Y�,�д��.��@�u�_G����5�H���}&egѴ��d�������^��G���T������y$���!�𣖍�4���XF;&����O��4�D,�s��G3��[�?����o|d�U��a�x�N/Tz*�{̸��󸳁N�w�_�O%��$�����pΖ���H؞8}<���F����0ۀ� X��4|�.�K�>�-�������LXۺ^*:]�K�Y����{��Ou�}4�o��u�df��p��E������\2ץ��������v�������
��*/���5΋�y��3UV'K%�4�c�����[>̔�#�:&C�Ll�LO|�d�s�F�����Y�gĵA4��@��=�^�ް��"iM�/�t�_?����C��ŘBtm��1�E%N8�Գ��O�s�.)𳖋2��}�_��hK��k�J�a}{k7c˺�'z�2�����fȢi�OxZ��5">೽��w>�
��1
����~�fx��z�q�ɳ<�.�&;?�\������ Җ��A^A(O�܂4���������`�!�� <�\�o�뇷���\�����ѽ87>�#�m���W�4m#�r��+������Bo��ˣr$)q���|��b�Z���-��yX$ ���7?� ����{u��8y�+'����������cx����d>�Hy�K2q��&F���$�E��G�)���ڣ�]�8֮�$S^�;�[xx�{��ʋ�fN�x�6�Z�:<�E�r�tei��^Sf�<�KU�>�[{� _w@�<BQ�8�17��1?!m��K7?�ͽ*���H���YX��xm&PEQr��D;@�h�s)/�$����̛��5@��5���K;[�'����� �#"�:5(L����m�q}[d*�������vH���cᚿ�w�+\�����Ѿ�!
<U�b�|�e�!��l�O�+����yH��֑Hy����*v��`Q=����xQ�3Ն��Ui�2���mJ�q�`G��E�0>�1[������;��Өf��Wso���:cd�s�ƽ�����-l4����9[GJo�ܼ�8�O6C[v���i���8��g��QP��&�qq��a�*WY�Ϻ�No�X�����.�����X�7����'��b���%6źd���b�fX��r�M�V�-L���v�݄���Elw�Ϩ�Ecx+r��N:�=�Q��g�I�=�H+^�(z��l1~�ٓK,m����/�F׉;�����,GLea �ڒY�#�N�?��S��_��VX���=NG���t՝����29���M7���bd�^�(i����y�4�`|�NA�o�n���n�ت���`m�I'��]!��s4�����I�?j�c9�\S�b��쳑}\�~M��O��-�[6s�ţGd��F���6�_�s��OF�4{�p����15��Ālس�s�c m�hS�N������Ill��������I�ި�qq�_j�'0à=����ə�Bl'گu]T(�<gyL"��6�6�?�����!zO����XH��H�V�
�1 �|�AE�Cڹ[��g1����w&�����n��s7_-��ØV�{�KW�������J�c<X̗f#Ћ���T"iD�7"a\���g�sG��;�x��P�
�}7��w+�5��丼�'�Ww�O3�͋���u��3���1(έ}T��hT�[�96_s��ԏ���CoOrD�/n6=�5a�z�G |����f��$<�db8�A�pQ�a~b��&�ǳ>�4*Ť#��sz7�X�~k��O�ǆ��
8�·ior��,�B�ѣHg���m�z�X��ŏ'x.J|�M������,I�Ps�u�z"*=uF���q%�>m����q�L�y)��av7h�!�õ(�3�}�~�E��[Y6��{k���(��?\t@����67_�#P$f�Eܘf��T��N`	�>�'��݂���J�����2��}����{�͐$�M�ِ��1��ݍ��l��6I>;���FG�[ǭJZ�y�΍K��K3gA$-���&OVs�Oah��W������#�����3�F�[GJ��*p��t�S��K-����U���U�p�{�����3^�rt^�q�����I�l�\�2a�>�?o�K��ts�����	�<�IaQ�z���<Y�?���<<�u\I���$-8A�����a���醣�p�ggw��`�.n�k&
?��o�a��HZ�o�3j��#��Nԍ��2o����������U�ȡ�b�t�3�~h��E�-�\����v�4�nQg���(�]���u����N��C?Ya��G��we��z��,7	c��{q��IE�n�[0ؿ��U"���?N��Y��X;���g�B�5Ȧ(�'\$·�4tz4�b=�F��A��0F�V1���2+z1�E�.�{ȇ�i2~ړ�Iޜ7+�|��9�f�}8:�� S�ƻ��t$~�BA����    VzOo\�(���HDښG�7��!Wi�T_�1N^E����r����T�;���
ҳzqo ?z��!a'-;�K��Q�b.�H���I� ��Π�x��W^�${c��I���#�oA��� �< �M|8K�F�)Z�����%�)i�?��؛��7����[�T\��M�#�@�x,�F�S.��}�|�B�s7ĕC;ߦ��|�jތ޳]
��Yf�@+�F3� ��*p�iY<�� "�)��$O��s��Y��<�+{#��[��9��q�!�����z�"�>]܈��bnxV� �Sx�-\�3�%S"[lD<����#���Ŭ�g�cK���)�.�|^�rD6�/q��3�o|�"����\,�5מY�Σ�����\�-�=�=p��͏�OAm�?su��66�U�lč��=\^D�LX%Jr�Z!w�R�HA^�ڋxR�2>�aE��q�8�*��r�dW�&/ >����_���²���]W���\xJ���{�����K�A��ۻ��;xf�E��z�)����Q�Z��z�=e�O:������6�_8�j��:@�K�����0Dy+�'���<꧞$t�;C,��RU� 8�n�7U��.�!�(N��+G(׉Ub		[ơZ�NO�K���]j����#ɦ)��������a
�,�
2�b&`)���!�m_���@�N��� o��K��B��ʹ�\���/K�9؊��O'�ͅ!�*+P� ����>�߻�TM˓��xqȞ<=�㭄�`j����J��3Z5��-�u�Q����c�j�샷��9!(}���d��z.��P'��S��=�R:���>��&�r)����oF�=.:�(RM'��&�<Bɺ��ī!��n� Z\��ݍx�0=�� �(2��vb�0͏��Ts]�j��a��nl|�H�`F�RD�s�!�����<��^4�%�[i�NZ�߇��T�aa�l	~hE�� �ϳ�K�FX�Kv���TT��DMҜ7e��u~�+XI���b�����cR��d_ܕi����e���[� =S���g�x�z�x��e n?,�Z��⊊��?N�����[ʝ�o���E�����~�.���e/Cܾ�����������n�^p��xw6�O�G��*���nW;��b�/������	�q���H
��3��I���#M�Ŝ��zȲG� �H�!�D6�r4���,�^U��&n��Z����PH
.���G'M� [lA�{]�"S8d�Z��H�n맛 �8���oa��x���RAs��R�:	-��4����U�������J�ꍷjQ�����KU�CÇ�Bc����q�ϙ�l�㛖�i7
�R]�t�`dW'�/U\��R��+�;��=�0�w^��'��-��Sq��x�a��*�Ie�j5�d�Ӱ�+�f3|�C���L?=d��Aq<�H�Ɋ��6�ǻ���H�}�>l��o�i�yɀ��C��ALR/@b�Đ(��]�2/m��\�0*J��ev�H{C�.\�xđ �۽<MQe���S�.�2<k�	9g�4-��>/�I�,�D�8���"�ߴ)^�䄁��U�c^��!]
�|i�)o��{9**Ց���=�6I>��q_�)>�(�4��|�D�WI������ض��-�p�� �@1������S9�_�6|k�-gz�[�Xn�V��S'ꪡ@:�Xes-�?��c	>]6Q�>,�C`���P�~ρ~e�ӥ���	x��NVy�"�e�RE٬��v)<�o�b����b�uKr�^QU�U�p1��Ǡib�e��Sw������=9�9��bv�
�e!�4����+�I�7G=b,��>5���n�*�͌�4~:���qA/�����{|Y>�N7s{|QDjuWt �+~>o��uy �7�6��]̓�����.�#�<ݕ��'��#�-�:�-;@�]�&Wc�0T�"k����"bI�}f2#}^�I�&�=$�f�~.�O��vѽ+\%I��A�B����\#�O�D�]O�g���R�<r+��,7��/�#�HR��j(����C�H�E��y&��I��cx�*�5�E:]l�?b��O��B.�6�_�[=�Hݒ���ş��,w'_�*�ƹc��iv�H=	��F|�^8�A�;�C'<�rDzSe|=�X�����K�pg���!���R7䌪[_�e�E8����W·2�8����+�v���Gw7��Q��f,��;�l�A��q�������d�R5�xWM�¿+:=�E�|52C\]=.�9/qq(�5f��;��ܝ��}F�i��5H�_L���7��I��[O����~j�0�� ��(a��8U�/o^�q28OR��b|�22���{U��ٽ	[���^�gů�'�X�Td�^X���R�񸄡Exzf�y-KqWd�D�ش\�y7`�M��G!��K9!?�bI�g��FfKi�ӋYW��7E�}����g���ˏ?/N`�3�y�l>9B��PZrn�p6��7�n7�6�"-	N���A"ӏ81�OȚ��f:v�\I
Ѡ�%}���~7_~���J%�������|�!(��=�[�PR"~��g�kq�r��(Y�@��!�f?��+��.���=�p���[�2��"aVԜ8-\Jx;	��]�E�a�k�tqo��<\y�B�&���:FKǦ9/u�Q}h��T���0�;`���"���blٛ!x�������K(�\y�d#s?��#�xt��|W\��r&͸��r+��\M�ڙt:��{�f�c��z�l�g	�\�����My��ȷ0@������g��]���$#2��ُ�G9���O�)q�4cE������L�B�8�JV'��Q7�e��x�{�'H�jh�N`v���vI�s���(��A,'ׂlO��1[�K�U}�')�fBr�\i���>�Z�|]�{��Y�&�Ts���G���`�;�E�;y��8Q�d+���Z�Y���9�nƋ<�w��_����j'��r<=v�������Ȗ�!�v,�4>�ҦC{�Q4����I!;_�<��Ŀ��D�\W,4^��yXWAqH�rk��>Z���Nn���F��E�9�hnu�d"/�i��^>�`9T�u�����/�_H�]�M'-1�}�t���VRUN�PK����b.�hUklS�`��h*�:=$�hay~��B��R����%x�JKM�di�ەĚq웥��|q�].��]C�x6"����Hox���G,[7G�G���i���*I���9;d�����G�73�\�'p��"��*��HU���s���$�*�7�Z(��z�ޮrz��K5��?�?�ŗS�b�to0���#+R�M͵�k��p��5-^�M�@@��]�wR����F\ly/�&�{*���{~�����9,e�]�*�<"�^#�J��2�56t[|���:Ŧ���CEan�7U�Ή���x�-��}_�a�>ҩ�6'�|�4_7=~��Z�2ž��!����ݦV�"�.�S�nF7Ys���y#�:���G<��~v�m�kΔ_��mT�hGqp"8�3y.�#x��K!<��N��t�TY�����Q�f�\�����9޵h �J��{5�t��&����z�Q��CP������k�e4�T�L֡��AվR�j�Ѥ��C
>����[N�Ąo� y�B���!��x��\�ba|r��Cr�����}(a݌#�bo\��\��f+dr3L}�����D=dצ'.�46��T��� ^�f*x֖c��^�]Ul���]�i��x���$mkL:��ԬӠ����aq��v���-kEc��t!��s�8P�W��N#<5���b�,Yۑ�\j�V=��4WʍG?�:�8��k��Zi��&� /����G��+ؤ���b��6�[Gu�8ġ&u����t(2B*w�C�H���o]�����r�e��4��H����s��G��b��ŗf��K�����#%N�h��q���m:�y���ltM�    Ƌ��������q4�ߝ�+���sS]-��?�h/͢ь�g�τ�E����J����7�m�����O7qVώL���CE��P��S�5�=��f��eL�΋G���MŌ|�婤�7i�1-�>���kh<}�S-�����8�n6\)oU�[Y)5R��<���xs�[/�B4�,���^���(-���?�g|��By�HڷD;����7��%�v\ �`�V z�-x9W��$BZ���@XF9�|�n��z��Ӂ��R��Gv�\a}[��S�c<���ѩa���^����ZFMD�=�N/>��Y��5q�����t1���~>YG�4Fd_'-�́��W�M�HJz�_Ċ������2|z-/�7G}���"��d�� �\`<n���oED-g��l��<�ٚ;��.j��Sϒ�Ǜ�ˎm��R8��ȟu�\E	��e�A�L��S��N\^C��U���rX�y]>��t��/�~�ܮK+��&�^�+�ud�ۀ3�3kF��V�VOxy\ZM�{b��� �I�`��4�ʓ%�E� �j5�Qow�sF��C����ӟVy�Dux[�cUS�d�WgJ���m������qiO�˛���bl-��ً�y���V 3�'צ��M�qvH�S�g�'��|=����"p���i���ռ)]͋N�Ë��|�(�@�FLQ�LC^��ֿ�=����ꩡ$�]k�{p(5p��r*\���ӱ�b:DZP�R�L;pԸ��8�zU�Ұ���YǄ���f�j"O^�s!���Om.n��2��ŭ��Y�����:"�	o��vS��H����t�)�ew�$�)BLJr��iHC��#5;��-�M9k�W�D1i��{�����~,� H�2����ڂ�l� Ј#�O��8?鄫������1u�^$}��,6����IWOO��Y{�����Z,Ic��q0Y�/�u�rv�P'<��(�k2�J���	{a��z�
����Զz���a�޴U)��;D�qj#pbDOu�ͦN�ak����75�bA;Z���,�皏��|�nδ�Ҧ���MO��."��I+�b$I`�)�uXn��P��/�l�D�K�I���]�r�zE�3�����%OPL#J��|�/䃼��2����K�tG8�~/���#������<�i�WW?M?O�����1��o�ß/�1i.�\!�n��H����aS��h{wz��ڇ��<�z*4s��7MT�T�^^Eg\��tsѺ(��Ϗ�1s��wxw%��p)Q�]�M8xD,�!���Fw��#e�?�(���{��<%���.ɔ=�����ŋ\�))~UzS���7�7�g/4�.F=G��
G|u�;qz������ҵ��͏,����>��&�	a��z���9a���$�b�)�=��DԸ��Ԙ����'m[��1�H�e��Ba�u�(�'V)�3_\�\�y����!�{v8l�6I�`�.��n��.�O�G���zEb��Zċ�O�g�>{�mI���Bs�d����P~�W���M��_㳷���ŋn�K�;P�]~E|11ܺZ�.��Z���
�t���Ee�ײ'��ۤR�q���Gܠ�����r3
.ŪO���:TK�-�mm�5��z#�j������_�g���)v����K�3�i#���6�n7�é�H[N�~S�,8&��/M���p�<���xm�I�,I��,N��E�օ�$�/�ߌSH�,��ť��wc����'�'��� \��Bޣ{���&��o�ia~��x�L�%"Op列�â|\E�;�Qx�*�ձ��"i㥂;�DQt�4ݏ�-2~��{q�PBM[��x2%��+�ͽ���p2kX�����G�)��U�$/3pk�KE�:�%��I/�vTMM��'F;���b�BoXԂ7��w�,��R\od�_ds�E�-�)z5.��_w�>,_j�M3�G�C55I��n��1_�&�b�XM@rFqv��v�RS�x�hW��h|ŸK�ͤ�5��i�\C�K�����m�_�>tx#�x��4�Иr!'����BZ�b�Rf#��E�R�U�6걹�]�[�R�O��i�w������A��VU���]���3���Kud#<u_,~?���q��x�A7.���^Jfz{_�0�W�ɲm��UqIS>W�3���f���I±j)^�^ ^ހ�y	E]�HB��}5��Ɓ9��ۇ�VD:G5����>�2�/کky�`�.��Q�;�2ղ�l	��D��{󳴹[N������D��/�~<�1�Izaw�G*5�q#��C�3�>1e?gx�G8����\��m]l��U��z���M���AԳ����lY�嘇�\�ZSb��4ّ(W��(f6��l~��rt���$�q㜢�\�j��{�����ֺ%���F��'�KS�)�o���S�ug��V��I)0D��q6�EpʧH4�l��aN.��wb�W��yi�fQ�A{��fk�D�č�DM.0�]ݫdQ����%<?��[����i��;�ߴ��v�H���o������&��*�Smd�ZW����q&�g	���魔=���ـY?VR�V��٬ۭ��'�6q!����V��S\ t��ƻFڑ�?�ᙚ�FR�ܛy�"i��NN�,��fV�x-7ܴ�"U`BP|�^"����4>���o�:W5!�=,f� 	tdp�n�#e@6�cڵ�����>RAG��+XH{��c�
$��:�����}�V+mP9�w$���K�Q�.�d1�� �c����?j�!YZk�s��,�1��4׈K�}S<
v�S�K�_ڦ�)AhV���/�9)�z���U\�o]��Ũ|i�P
s�S�$J���#%�Y��x76�JQ�RtA>���b�� ˧e4���E���x��j�����#���O21&�z��$K�?�W�-�}�CV�%�z�7�.��9��ݑ�I�k�{H�65�2ӓtW�6�>n�13sB�@�2����4��':�V���c�*i��s4Ër ��F���b �gL��2^J�J<4�^>u^�[��"�ժ�GA M2��BR<�t���Yx��RϢ�)x3�@���ys\���	[2�1ίI�*�*_j@��Oy�*7��@�!��4���li����ɧIKr�B�cIֽ����}�P�M�hbԪ?o�ƭ5�#���
�]B�̼}Xo�J�O2ڸ�� �r����.Ҕm��I�RMC�Fi�K[l�3��š�vVtu��BN�U�d���4��~�ꏋ��,t�z?q�����S;��m"$��ތ8��M`ץȭ�h�5%�1Q�4�O)!�f��b������˘�1�<|0�q\%P�@��DII�����yu$p֥�ݑ�`��KI��]�ZC�5M�rD���;%%�xv�����a����A�gk.T,��yX�9����i�ٱ3��M��ezI�U�*+xp��{L�H��^2?��g���;/]`���[�h#*j�<�''���K�8�~�~*k�
~���e��
�H��I5w�iy�g�y�
��g/N�i�#��K^��O�;x?]��]W�h��_G%{#e���όG+�\dt<:����@���5���'*Q���q���K�Cvbz#�h��=	�S^���j`�&%�����U��'�Z��t{�+F%� 7u��H���<��=SڌL3���^�kg�N��s&��}���F�K�ΘK�C���,�������Q})�\�������d���-CO�W瞉åX�y��%OxR7�}~h�u�Z?%�u�ӗ�!������쵞�(o���<%��y���Q�L�����R*��Ņ�ğ���k-z�����ňĹ�͟�4��08��S�9\������E���g�^���7<N�l�r1����J���j���Izz�z�,ҝ/ì���$���D||�i/��* �j$DOX=,P�X>��O�-~�Un"��R�h Ɂ3��te���%W���;�>�T�i/��2�h�Q�w�a��Z��Ku+e�dp>�yI.÷ Vtu4;�T���x*�4�x��:�L��W���i-��$r�����x�C���񽅱|� �
  �� �@P)�ta�<��F=�{�t��,�.�G�e��ƞ�pu���	�r�<�T����f��{W��w�d�^�ц+?�.囀�,��~(�8�&9g�g�;�x?�lѝ�l
��|x[f���KE��6���-ro�2~ir)U@A�?�ܸ>�v�8.��u��R�rcB֊����Wpͣdp'I�>L�sK�RL���q�JqA�7X��X�G�U��1^dL���M�K�d�[�/�3�~LA	������
��+yG;׵��-ODƏ3;N��tR퐒��b���Ϋ����EI޼%<���͸�f\ꩥ�~�)��5�كf�۝������̛/��Amd�BtG!���h���)y��Z����z�>��D�x�i�1�A5k��n�f�K�b��aş'��-���v�Y.2�X�}��8=Ԁq�x8�ط��^�3��ߟ� ���v�qr�0iSk�	![�lθ�=PJO��s9?�<����S��9�gv���K4��ͩW�񩵣)zo����8�Z/z-��{s%�)�\�EC?O�:�2m��9
Bȵ�Gu��A):�����f�{�$�x��w����;(�4���遗�[Jp�:�(Y�>��QV:�#*�9����U<���g���<�a�1Zr�T� [5��|o�8����q���]����u��8i�T.W(�t˸yHu8�}L.<��[T�s�tk*��!u�O⽃n�QЯ�Y@G\�|��V�#�'�!�i�u�=����`!��F۰$%}(��޴�
����^��j��~ ��{;[P�cl�~㵀��A6]k���R�Ũ;�k������Q���?��[z\�8�}3s�D��\����J���l��K�j0eI��c��t�퐚٭"W���ۊ�GAͨf9[�&�1�SZYX4R��x\jc�;h&1��������ݕQ���~�E\ .� ��ЃV領���G�R�s}�z���$W*J��4�hx��T��-�lo��^`�lL��Q��(��g�IeaIyI��^M�\08��ƹ�_ܔ�`&�BSu��9Nn���dď#O�9�YG��b�����U�{+y4�L�ߔ�5kD�\�j��w�#�0/V`+g�/G� VWłagV��oT�Ko��q��y+�Y�Y �O�t��+��1[}x���rz����S�h����3��� |*O��}��ts1�]'�kE�Z���k�.�(�����-t��
������LG��bV�!��R���Ra"�"ca��s�du�hb�L���N<	VN��n��9cn�;������gu���s���I+x���jGR�e�3�0������Sy� ,=��D��R4����e�S��0d����'s,��]nV~t�	�ŬJ���JS��c%��wڻ����$���%�:���E� �Z�8P���h�o���Q��;��X�;G2�*b�2cl\������tPH]����� (���re��o6;�u��˜���E��n�,

�a��.s�ǣݏ�R�(s�"�,�39ǓE����Fu�\�.�ef7��7�0X�U�X�n���I#y��!b~�G'��~�2yo��j  ^�U&�}I5'W28��A-^
���2������;��צI�*�?�#oeW$��hK*f���'՚���*=\��<�$��n�`l��̲jwvxX��|�"�p��rp�U�Y~��֨�%S�<	�wdܜ���8�����/���D�v�c	����5e���_�­?��1�\�^�>v��	��f�_2��#C4��J�ǎ��_|�{*-Z���`y�R�"~�#d��Iy��)�a��XǉNd�&��,��6�6��FsK��8!N�\�3���!^�6��a~�0���ŭ�CKV�c�֓�.������vA˷��5�DBNߘ�[����\{�>l�����
YӪ�ƣ�����bQ'���KZ���,�����%�U��]@��.�)��o����ǭC��i��8♻���O-9s'����yS��ǽ������1A�p��l��f3�,��V5�D�<��uʢ����s��A���h��8��/�*��ԭ]o�2>Y�G��������n"8�e����]�v�y�:fM9���9�	�(Cյ$'�OåF1
��)s���5D�t����k�7g�8��[%�U���BD2m� _Mu�0����zr�n�l�&'Q2���d"_Dč��[��kfj'#~	�����
_�����.�$�6Lei,�JS�e�E<Y�h<�ݺA����_��%��3���x\����KX��;,���.���oW	�3�߿==����C�Ns��z!MƵ���_���g-)x��u�}g�K8ǊK�T��側}���=͵��2Wb!ξN���i�Zh��6�(7Q@rH4��:� ����oIQy~v:Z��Ӯ��?,y�Ni�'�*�5������T�V��U�����cB��M�p����G�1M#��*�������x������j�*�6��L#��\��@r����y_�~)T/x�=����4�|h��yf@1I_|�GW#PF���E"sZUi�њ�V�	A`�M� =�|.He�/�6.�hx?I�����Hrǰ+������.)فS;|\ډ|��WWW��5I�Lbh<\�^��[[f����c���Y�0s�����̸.���������z�      �   <   x�3�tL.�/�2�Щ��\Ɯ.�E�`Q΀������".S����Լ�� 7F��� IT�      �   q   x��9
BAEѸ�*\����EA10L�R�.��޽Cx9p;Y���#'b,5V�b"[�H=1��z<�<��Wb.'���Fц�?�O,��h��c%g͹4{���Fr�7nC  �"�      �   x   x�%��1B�P�>И�^��:֙�}T�P�0����8����BN��X,���=�^�<O���6R����8�g���p2g�E�.!`Ӂ��`.��j4��������Q�����m�|     