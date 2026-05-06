# Реализовано добавление данных из нового источника в DWH.

Общая схема загрузки данных  в DWH: src/images/Schema.png
src/scripts/check_source_data.sql - проверка того, что в таблицах источника есить данные;
src/scripts/loading_data_into_dwh.sql -подготовка и загрузка данных в DWH;
src/scripts/create_datamart.sql - создание витрины.

