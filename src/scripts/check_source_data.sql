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
