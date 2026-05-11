--==========Загрузка данных в DWH==========
--1. Создание временныхтаблиц для данных из источника external_source:
--Создание временной таблицы для измерений
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

--Создание временной таблицы для фактов

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
--добавление новых записей в dwh.d_craftsmans
MERGE INTO dwh.d_craftsman AS d
USING (SELECT DISTINCT craftsman_name, craftsman_address, craftsman_birthday, craftsman_email FROM tmp_esm) AS t
ON d.craftsman_name = t.craftsman_name AND d.craftsman_email = t.craftsman_email
WHEN MATCHED THEN
  UPDATE SET craftsman_address = t.craftsman_address, craftsman_birthday = t.craftsman_birthday, load_dttm = current_timestamp
WHEN NOT MATCHED THEN
  INSERT (craftsman_name, craftsman_address, craftsman_birthday, craftsman_email, load_dttm)
  VALUES (t.craftsman_name, t.craftsman_address, t.craftsman_birthday, t.craftsman_email, current_timestamp);

--добавление новых записей в dwh.d_products
MERGE INTO dwh.d_product AS d
USING (SELECT DISTINCT product_name, product_description, product_type, product_price from tmp_esm) AS t
ON d.product_name = t.product_name AND d.product_description = t.product_description AND d.product_price = t.product_price
WHEN MATCHED THEN
  UPDATE SET product_type= t.product_type, load_dttm = current_timestamp
WHEN NOT MATCHED THEN
  INSERT (product_name, product_description, product_type, product_price, load_dttm)
  VALUES (t.product_name, t.product_description, t.product_type, t.product_price, current_timestamp);

--добавление новых записей в dwh.d_customer
MERGE INTO dwh.d_customer AS d
USING (SELECT DISTINCT customer_name, customer_address, customer_birthday, customer_email from tmp_esm) AS t
ON d.customer_name = t.customer_name AND d.customer_email = t.customer_email
WHEN MATCHED THEN
  UPDATE SET customer_address= t.customer_address, customer_birthday= t.customer_birthday, load_dttm = current_timestamp
WHEN NOT MATCHED THEN
  INSERT (customer_name, customer_address, customer_birthday, customer_email, load_dttm)
  VALUES (t.customer_name, t.customer_address, t.customer_birthday, t.customer_email, current_timestamp);

--3.Добавление новых записей в dwh.f_order
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

