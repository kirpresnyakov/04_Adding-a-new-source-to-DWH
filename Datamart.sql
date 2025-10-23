--============Подготовительный этап=================
--1. Проверяем. что таблицы источника external_source: craft_products_orders и customers содержат данные:

SELECT  * FROM с.craft_products_orders;

SELECT  * FROM external_source.customers;

--2. Проверка дублирующихся записей(строк) по ключевым полям:
SELECT *
FROM (
    SELECT *,
    COUNT(*) OVER (PARTITION BY craftsman_id, product_id, order_id, customer_id) AS duplicate_count
    FROM external_source.craft_products_orders
) AS t
WHERE duplicate_count > 1
ORDER BY craftsman_id, product_id, order_id;

SELECT *
FROM (
    SELECT *,
    COUNT(*) OVER (PARTITION BY customer_id, customer_email, customer_name, customer_birthday) AS duplicate_count
    FROM external_source.customers
) t
WHERE duplicate_count > 1
ORDER BY  customer_id, customer_email, customer_name, customer_birthday;

--3. Проверка даты рождения craft/customers. Выявляем клиентов/мастеров из "будущего" или очень молодых, если на платформе есть возрастные ограничения.

select 
	max(customer_birthday) AS max_date_customer_birthday,
	min(customer_birthday) AS min_date_customer_birthday
from external_source.customers;


select 
	max(craftsman_birthday) AS max_date_craft_birthday,
	min(craftsman_birthday) AS min_date_craft_birthday
from external_source.craft_products_orders;


--==========Загрузка данных в DWH==========
--1. Создание временныхтаблиц для данных из источника external_source:
/*Создание временной таблицы для измерений*/
DROP TABLE IF EXISTS tmp_esm;

CREATE TEMP TABLE tmp_es AS 
	SELECT 
		cpo.order_id,
		cpo.order_created_date,
		cpo.order_completion_date,
		cpo.order_status,
		cpo.craftsman_id,
		cpo.craftsman_name,
		cpo.craftsman_address,
		cpo.craftsman_birthday,
		cpo.craftsman_email,
		cpo.product_id,
		cpo.product_name,
		cpo.product_description,
		cpo.product_type,
		cpo.product_price,
		c.customer_id,
		c.customer_name,
		c.customer_address,
		c.customer_birthday,
		c.customer_email
	FROM external_source.craft_products_orders AS cpo
	INNER JOIN external_source.customers  AS c ON c.customer_id = cpo.customer_id;

/*Создание временной таблицы для фактов*/

DROP TABLE IF EXISTS tmp_esf;

CREATE TEMP TABLE tmp_esf AS 
	SELECT
		product_id,
        craftsman_id,
        customer_id,
        order_created_date,
        order_completion_date,
        order_status,
        current_timestamp AS load_dttm
	FROM external_source.craft_products_orders; 

--2. Обновление таблиц измерений в DWH:
/*добавление новых записей в dwh.d_craftsmans*/
MERGE INTO dwh.d_craftsman AS d
USING (SELECT DISTINCT craftsman_name, craftsman_address, craftsman_birthday, craftsman_email FROM tmp_esm) AS t
ON d.craftsman_name = t.craftsman_name AND d.craftsman_email = t.craftsman_email
WHEN MATCHED THEN
  UPDATE SET craftsman_address = t.craftsman_address, craftsman_birthday = t.craftsman_birthday, load_dttm = current_timestamp
WHEN NOT MATCHED THEN
  INSERT (craftsman_name, craftsman_address, craftsman_birthday, craftsman_email, load_dttm)
  VALUES (t.craftsman_name, t.craftsman_address, t.craftsman_birthday, t.craftsman_email, current_timestamp);

/*добавление новых записей в dwh.d_products */
MERGE INTO dwh.d_product AS d
USING (SELECT DISTINCT product_name, product_description, product_type, product_price from tmp_esm) AS t
ON d.product_name = t.product_name AND d.product_description = t.product_description AND d.product_price = t.product_price
WHEN MATCHED THEN
  UPDATE SET product_type= t.product_type, load_dttm = current_timestamp
WHEN NOT MATCHED THEN
  INSERT (product_name, product_description, product_type, product_price, load_dttm)
  VALUES (t.product_name, t.product_description, t.product_type, t.product_price, current_timestamp);

/* добавление новых записей в dwh.d_customer */
MERGE INTO dwh.d_customer AS d
USING (SELECT DISTINCT customer_name, customer_address, customer_birthday, customer_email from tmp_esm) AS t
ON d.customer_name = t.customer_name AND d.customer_email = t.customer_email
WHEN MATCHED THEN
  UPDATE SET customer_address= t.customer_address, customer_birthday= t.customer_birthday, load_dttm = current_timestamp
WHEN NOT MATCHED THEN
  INSERT (customer_name, customer_address, customer_birthday, customer_email, load_dttm)
  VALUES (t.customer_name, t.customer_address, t.customer_birthday, t.customer_email, current_timestamp);

--3/*добавление новых записей в dwh.f_order*/
MERGE INTO dwh.f_order AS f
USING tmp_sources_fact AS t
ON f.product_id = t.product_id 
    AND f.craftsman_id = t.craftsman_id 
    AND f.customer_id = t.customer_id
    AND f.order_created_date = t.order_created_dateWHEN 
MATCHED THEN
  UPDATE SET order_completion_date = t.order_completion_date, order_status = t.order_status, load_dttm = current_timestamp  
WHEN NOT MATCHED THEN
    INSERT (product_id, craftsman_id, customer_id, order_created_date, order_completion_date, order_status, load_dttm)
    VALUES (t.product_id, t.craftsman_id, t.customer_id, t.order_created_date, t.order_completion_date, t.order_status, current_timestamp);

--========Создание витрины========

--1. Создание таблицы customer_report_datamart:

DROP TABLE IF EXISTS dwh.customer_report_datamart;

 CREATE TABLE IF NOT EXISTs dwh.customer_report_datamart (
 	id int GENERATED ALWAYS AS IDENTITY NOT NULL,
 	customer_id INT NOT NULL,
 	customer_name TEXT NOT NULL,
 	customer_address TEXT NOT NULL,
 	customer_birthday TIMESTAMP NOT NULL,
 	customer_email TEXT NOT NULL,
 	customer_money NUMERIC (15,2) NOT NULL,
 	platform_money INT NOT NULL,
 	count_order INT NOT NULL,
 	avg_price_order NUMERIC (10,2) NOT NULL,
 	median_time_order_completed NUMERIC(10,1), 
 	top_product_category VARCHAR NOT NULL,
 	top_craftsman_id INT NOT NULL,
 	count_order_created INT NOT NULL,
 	count_order_in_progress INT NOT NULL,
 	count_order_delivery INT NOT NULL,
 	count_order_done INT NOT NULL,
 	count_order_not_done INT NOT NULL,
 	report_period VARCHAR NOT NULL,
 	CONSTRAINT customer_report_datamart_pk primary key (id)
 	);
 
--2. Создание доп.таблицы load_dates_customer_report_datamart:
DROP TABLE IF EXISTS dwh.load_dates_customer_report_datamart;

CREATE TABLE IF NOT EXISTS dwh.load_dates_customer_report_datamart (
    id BIGINT GENERATED ALWAYS AS IDENTITY,
    load_dttm DATE NOT NULL,
    CONSTRAINT load_dates_customer_report_datamart_pk PRIMARY KEY (id)
);

--3. Инкрементальная загрузка данных:

/*определяем, какие данные были изменены в витрине или добавлены в DWH. Формируем дельту изменений*/
WITH
dwh_delta AS ( 
    SELECT     
            fo.customer_id AS customer_id,
            dcs.customer_name AS customer_name,
            dcs.customer_address AS customer_address,
            dcs.customer_birthday AS customer_birthday,
            dcs.customer_email AS customer_email,
            fo.order_id AS order_id,
            dp.product_id AS product_id,
            dp.product_price AS product_price,
            dp.product_type AS product_type,
            fo.order_completion_date - fo.order_created_date AS diff_order_date, 
            fo.order_status AS order_status,
            TO_CHAR(fo.order_created_date, 'yyyy-mm') AS report_period,
            crd.customer_id AS exist_customer_id,
            fo.craftsman_id AS craftsman_id,
            dc.load_dttm AS customer_load_dttm,
            dcs.load_dttm AS craftsman_load_dttm,
            dp.load_dttm AS products_load_dttm
            FROM dwh.f_order AS fo 
                INNER JOIN dwh.d_craftsman AS dc ON fo.craftsman_id = dc.craftsman_id 
                INNER JOIN dwh.d_customer AS dcs ON fo.customer_id = dcs.customer_id 
                INNER JOIN dwh.d_product AS dp ON fo.product_id = dp.product_id 
                LEFT JOIN dwh.customer_report_datamart AS crd ON fo.customer_id = crd.customer_id
                    WHERE (fo.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_customer_report_datamart)) OR
                          (dc.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_customer_report_datamart)) OR
                          (dcs.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_customer_report_datamart)) OR
                          (dp.load_dttm > (SELECT COALESCE(MAX(load_dttm),'1900-01-01') FROM dwh.load_dates_customer_report_datamart))
),
/*делаем выборку заказчиков, по которым были изменения в DWH, для обнорвления в витрине */
dwh_update_delta AS ( 
    SELECT     
            customer_id
            FROM dwh_delta
            WHERE exist_customer_id IS NULL        
),
/*делаем расчёт витрины по новым данным */
dwh_delta_insert_result AS ( 
    SELECT  
    	T4.customer_id AS customer_id,
        T4.customer_name AS customer_name,
        T4.customer_address AS customer_address,
        T4.customer_birthday AS customer_birthday,
        T4.customer_email AS customer_email,
        T4.customer_money AS customer_money,
        T4.platform_money AS platform_money,
        T4.count_order AS count_order,
        T4.avg_price_order AS avg_price_order,
        T4.median_time_order_completed AS median_time_order_completed,
        T4.product_type AS top_product_category,
        T4.craftsman_id AS top_craftsman_id,
        T4.count_order_created AS count_order_created,
        T4.count_order_in_progress AS count_order_in_progress,
        T4.count_order_delivery AS count_order_delivery,
        T4.count_order_done AS count_order_done,
        T4.count_order_not_done AS count_order_not_done,
        T4.report_period AS report_period 
        FROM (                 
            SELECT 
            	*,
                RANK() OVER(PARTITION BY T2.customer_id ORDER BY count_product DESC) AS rank_count_product,
                RANK() OVER(PARTITION BY T2.customer_id ORDER BY craftsman_id DESC) AS rank_craftsman
                FROM ( 
                     SELECT
                     	T1.customer_id AS customer_id,
                     	T1.customer_name AS customer_name,
                        T1.customer_address AS customer_address,
                        T1.customer_birthday AS customer_birthday,
                        T1.customer_email AS customer_email,
                        SUM(T1.product_price) AS customer_money,
                        SUM(T1.product_price) * 0.1 AS platform_money,
                        COUNT(order_id) AS count_order,
                        AVG(T1.product_price) AS avg_price_order,
                        PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY diff_order_date) AS median_time_order_completed,
                        SUM(CASE WHEN T1.order_status = 'created' THEN 1 ELSE 0 END) AS count_order_created,
                        SUM(CASE WHEN T1.order_status = 'in progress' THEN 1 ELSE 0 END) AS count_order_in_progress, 
                        SUM(CASE WHEN T1.order_status = 'delivery' THEN 1 ELSE 0 END) AS count_order_delivery, 
                        SUM(CASE WHEN T1.order_status = 'done' THEN 1 ELSE 0 END) AS count_order_done, 
                        SUM(CASE WHEN T1.order_status != 'done' THEN 1 ELSE 0 END) AS count_order_not_done,
                        T1.report_period AS report_period
                        FROM dwh_delta AS T1
                        WHERE T1.exist_customer_id IS NULL
                        GROUP BY T1.customer_id, T1.customer_name, T1.customer_address, T1.customer_birthday, T1.customer_email, T1.report_period
                            ) AS T2 
                            INNER JOIN (
                            /*Эта выборка поможет определить самый популярный товар у Заказчика.*/
                            	SELECT 
                                	dd.customer_id AS customer_id_for_product_type, 
                                    dd.product_type, 
                                    COUNT(dd.product_id) AS count_product
                                FROM dwh_delta AS dd
                                GROUP BY dd.customer_id, dd.product_type
                                ORDER BY count_product DESC) AS T3 ON T2.customer_id = T3.customer_id_for_product_type
                            INNER JOIN(
                            /*выбираем популярного мастера*/
								SELECT 
									customer_id AS customer_id_for_craftsman, 
									craftsman_id, 
									count (craftsman_id) as count_craftsman
								FROM dwh_delta	
								GROUP BY customer_id, craftsman_id
								ORDER BY count_craftsman desc) AS T5 ON T2.customer_id =T5.customer_id_for_craftsman
                ) AS T4
                WHERE T4.rank_count_product = 1
                AND T4.rank_craftsman >=1
                ORDER BY report_period -- условие помогает оставить в выборке первую по популярности категорию товаров
),
/*делаем перерасчёт для существующих записей витринs, так как данные обновились за отчётные периоды.*/
dwh_delta_update_result AS ( 
    SELECT 
	    T4.customer_id AS customer_id,
	    T4.customer_name AS customer_name,
	    T4.customer_address AS customer_address,
	    T4.customer_birthday AS customer_birthday,
	    T4.customer_email AS customer_email,
	    T4.customer_money AS customer_money,
	    T4.platform_money AS platform_money,
	    T4.count_order AS count_order,
	    T4.avg_price_order AS avg_price_order,   
	    T4.median_time_order_completed AS median_time_order_completed,
	    T4.product_type AS top_product_category,
	    T4.craftsman_id as top_craftsman_id,
	    T4.count_order_created AS count_order_created,
	    T4.count_order_in_progress AS count_order_in_progress,
	    T4.count_order_delivery AS count_order_delivery, 
	    T4.count_order_done AS count_order_done, 
	    T4.count_order_not_done AS count_order_not_done,
	    T4.report_period AS report_period 
	    FROM (
	    /*в этой выборке объединяем две внутренние выборки по расчёту столбцов витрины и применяем оконную функцию для определения самой популярной категории товаров*/
                SELECT     
                	*,
                    RANK() OVER(PARTITION BY T2.customer_id ORDER BY count_product DESC) AS rank_count_product,
                    RANK() OVER(PARTITION BY T2.customer_id ORDER BY craftsman_id DESC) AS rank_craftsman
                    FROM (
                         SELECT 
	                         T1.customer_id AS customer_id,
	                         T1.customer_name AS customer_name,
	                         T1.customer_address AS customer_address,
	                         T1.customer_birthday AS customer_birthday,
	                         T1.customer_email AS customer_email,
	                         SUM(T1.product_price) AS customer_money,
	                         SUM(T1.product_price) * 0.1 AS platform_money,
	                         COUNT(order_id) AS count_order,
	                         AVG(T1.product_price) AS avg_price_order,
	                         PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY diff_order_date) AS median_time_order_completed,
	                         SUM(CASE WHEN T1.order_status = 'created' THEN 1 ELSE 0 END) AS count_order_created, 
	                         SUM(CASE WHEN T1.order_status = 'in progress' THEN 1 ELSE 0 END) AS count_order_in_progress, 
	                         SUM(CASE WHEN T1.order_status = 'delivery' THEN 1 ELSE 0 END) AS count_order_delivery, 
	                         SUM(CASE WHEN T1.order_status = 'done' THEN 1 ELSE 0 END) AS count_order_done, 
	                         SUM(CASE WHEN T1.order_status != 'done' THEN 1 ELSE 0 END) AS count_order_not_done,
                         T1.report_period AS report_period
                         FROM (
                         /*в этой выборке достаём из DWH обновлённые или новые данные по Заказчикам, которые уже есть в витрине*/
                               SELECT     
	                               fo.customer_id AS customer_id,
	                               dcs.customer_name AS customer_name,
	                               dcs.customer_address AS customer_address,
	                               dcs.customer_birthday AS customer_birthday,
	                               dcs.customer_email AS customer_email,
	                               fo.order_id AS order_id,
	                               dp.product_id AS product_id,
	                               dp.product_price AS product_price,
	                               dp.product_type AS product_type,
	                               fo.order_completion_date - fo.order_created_date AS diff_order_date,
	                               fo.order_status AS order_status, 
	                               TO_CHAR(fo.order_created_date, 'yyyy-mm') AS report_period
	                               FROM dwh.f_order AS fo 
		                               INNER JOIN dwh.d_craftsman AS dc ON fo.craftsman_id = dc.craftsman_id 
		                               INNER JOIN dwh.d_customer AS dcs ON fo.customer_id = dcs.customer_id 
		                               INNER JOIN dwh.d_product AS dp ON fo.product_id = dp.product_id
		                               INNER JOIN dwh_update_delta AS ud ON fo.customer_id = ud.customer_id
	                           ) AS T1
                                 GROUP BY T1.customer_id, T1.customer_name, T1.customer_address, T1.customer_birthday, T1.customer_email, T1.report_period
                          ) AS T2 
                           INNER JOIN (
                           /*Эта выборка поможет определить самый популярный товар у Заказчика*/ 
                                    SELECT     
	                                    dd.customer_id AS customer_id_for_product_type, 
	                                    dd.product_type, 
	                                    COUNT(dd.product_id) AS count_product
                                    FROM dwh_delta AS dd
                                    GROUP BY dd.customer_id, dd.product_type
                                    ORDER BY count_product DESC) AS T3 
                            ON T2.customer_id = T3.customer_id_for_product_type
                           INNER JOIN(
                            /*выбираем популярного мастера*/
								SELECT 
									customer_id AS customer_id_for_craftsman, 
									craftsman_id, 
									count (craftsman_id) as count_craftsman
								FROM dwh_delta	
								GROUP BY customer_id, craftsman_id
								ORDER BY count_craftsman desc) AS T5 ON T2.customer_id =T5.customer_id_for_craftsman
                ) AS T4 
                WHERE T4.rank_count_product = 1
                AND T4.rank_craftsman >=1
                ORDER BY report_period
),
/*выполняем insert новых расчитанных данных для витрины */
insert_delta AS ( 
    INSERT INTO dwh.customer_report_datamart (
        customer_id,
        customer_name,
        customer_address,
        customer_birthday, 
        customer_email, 
        customer_money, 
        platform_money, 
        count_order, 
        avg_price_order, 
        median_time_order_completed,
        top_product_category,
        top_craftsman_id,
        count_order_created, 
        count_order_in_progress, 
        count_order_delivery, 
        count_order_done, 
        count_order_not_done, 
        report_period
    ) SELECT 
	      customer_id,
		  customer_name,
		  customer_address,
		  customer_birthday, 
		  customer_email, 
		  customer_money, 
		  platform_money, 
		  count_order, 
		  avg_price_order, 
		  median_time_order_completed,
		  top_product_category,
		  top_craftsman_id,
		  count_order_created, 
		  count_order_in_progress, 
		  count_order_delivery, 
		  count_order_done, 
		  count_order_not_done, 
	      report_period
      FROM dwh_delta_insert_result
),
/*выполняем обновление показателей в отчёте по уже существующим Заказчикам*/
update_delta AS ( 
    UPDATE dwh.customer_report_datamart SET
        customer_name = updates.customer_name, 
        customer_address = updates.customer_address, 
        customer_birthday = updates.customer_birthday, 
        customer_email = updates.customer_email, 
        customer_money = updates.customer_money, 
        platform_money = updates.platform_money, 
        count_order = updates.count_order, 
        avg_price_order = updates.avg_price_order, 
        median_time_order_completed = updates.median_time_order_completed, 
        top_product_category = updates.top_product_category,
        top_craftsman_id = updates.top_craftsman_id,
        count_order_created = updates.count_order_created, 
        count_order_in_progress = updates.count_order_in_progress, 
        count_order_delivery = updates.count_order_delivery, 
        count_order_done = updates.count_order_done,
        count_order_not_done = updates.count_order_not_done, 
        report_period = updates.report_period
    FROM (
        SELECT 
	        customer_id,
			customer_name,
			customer_address,
			customer_birthday, 
			customer_email, 
			customer_money, 
			platform_money, 
			count_order, 
			avg_price_order, 
			median_time_order_completed,
			top_product_category,
			top_craftsman_id,
			count_order_created, 
			count_order_in_progress, 
			count_order_delivery, 
			count_order_done, 
			count_order_not_done, 
		    report_period
	        FROM dwh_delta_update_result) AS updates
    WHERE dwh. customer_report_datamart. customer_id = updates.customer_id
),
/*делаем запись в таблицу загрузок о том, когда была совершена загрузка, чтобы в следующий раз взять данные, которые будут добавлены или изменены после этой даты*/
insert_load_date AS (
    INSERT INTO dwh.load_dates_customer_report_datamart (
        load_dttm
    )
     SELECT GREATEST(COALESCE(MAX(craftsman_load_dttm), NOW()), 
                    COALESCE(MAX(customer_load_dttm), NOW()), 
                    COALESCE(MAX(products_load_dttm), NOW())) 
     FROM dwh_delta
)
SELECT 'increment datamart';
