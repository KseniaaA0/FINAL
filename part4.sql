-- 4.1 Создание тестовой базы данных
DROP DATABASE IF EXISTS info21_test;
CREATE DATABASE info21_test;

\c info21_test

CREATE TYPE status AS ENUM ('Start', 'Success', 'Failure');

-- Создаем несколько тестовых таблиц для демонстрации работы с метаданными

CREATE TABLE test_table1 (
    id SERIAL PRIMARY KEY,     
    name VARCHAR(50),        
    value INTEGER    
);

CREATE TABLE test_table2 (
    id SERIAL PRIMARY KEY,          
    data JSONB,                          
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP  
);

CREATE OR REPLACE FUNCTION test_function1(param1 INTEGER, param2 VARCHAR)
RETURNS INTEGER AS $$
BEGIN
    RETURN param1 + LENGTH(param2);
END;
$$ LANGUAGE plpgsql;

-- Тестовая функция, возвращающая таблицу
CREATE OR REPLACE FUNCTION test_function2()
RETURNS TABLE(id INTEGER, name VARCHAR) AS $$
BEGIN
    -- Возвращает тестовые данные в виде таблицы
    RETURN QUERY SELECT 1, 'test';
END;
$$ LANGUAGE plpgsql;

-- 4.2 Процедура удаления таблиц по шаблону
-- Процедура удаляет таблицы, имена которых соответствуют заданному шаблону
CREATE OR REPLACE PROCEDURE prc_drop_tables(
    IN pattern VARCHAR DEFAULT '%' 
) AS $$
DECLARE
    table_record RECORD;  
BEGIN
    -- Цикл по всем таблицам в схеме 'public', соответствующим шаблону
    FOR table_record IN 
        SELECT tablename 
        FROM pg_tables 
        WHERE schemaname = 'public' 
            AND tablename LIKE pattern 
    LOOP
        EXECUTE 'DROP TABLE IF EXISTS ' || table_record.tablename || ' CASCADE';
        RAISE NOTICE 'Dropped table: %', table_record.tablename;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON PROCEDURE prc_drop_tables IS 'Удаляет все таблицы, соответствующие шаблону';

-- 4.3 Процедура получения списка скалярных функций
-- Процедура выводит информацию о всех скалярных функциях в текущей базе данных
CREATE OR REPLACE PROCEDURE prc_list_scalar_functions() 
AS $$
DECLARE
    func_record RECORD;  
BEGIN
    RAISE NOTICE 'Scalar functions in current database:';
    
    FOR func_record IN
        SELECT 
            p.proname AS function_name,            
            pg_get_function_arguments(p.oid) AS parameters,
            pg_get_function_result(p.oid) AS return_type    
        FROM pg_proc p                                 
        JOIN pg_namespace n ON p.pronamespace = n.oid      
        WHERE n.nspname = 'public'          
            AND p.prorettype <> 0             
            AND p.prorettype <> 2249         
        ORDER BY p.proname                        
    LOOP
        -- Выводим информацию о каждой функции
        RAISE NOTICE 'Function: %, Parameters: (%), Returns: %', 
                     func_record.function_name,
                     func_record.parameters,
                     func_record.return_type;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON PROCEDURE prc_list_scalar_functions IS 'Выводит список скалярных функций';

-- 4.4 Процедура удаления всех DML триггеров
-- Процедура удаляет все пользовательские триггеры DML (Data Manipulation Language)
CREATE OR REPLACE PROCEDURE prc_drop_all_dml_triggers() 
AS $$
DECLARE
    trigger_record RECORD; 
BEGIN
    -- Цикл по всем пользовательским триггерам
    FOR trigger_record IN
        SELECT 
            tgname AS trigger_name,   
            relname AS table_name        
        FROM pg_trigger t      
        JOIN pg_class c ON t.tgrelid = c.oid  
        WHERE NOT t.tgisinternal     
            AND t.tgname NOT LIKE 'pg_%' 
    LOOP
        EXECUTE 'DROP TRIGGER IF EXISTS ' || trigger_record.trigger_name || 
                ' ON ' || trigger_record.table_name;
        RAISE NOTICE 'Dropped trigger % on table %', 
                     trigger_record.trigger_name, 
                     trigger_record.table_name;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON PROCEDURE prc_drop_all_dml_triggers IS 'Удаляет все DML триггеры в текущей базе';

-- 4.5 Процедура поиска объектов по имени
-- Процедура ищет объекты БД (таблицы, функции, триггеры) по заданному шаблону имени
CREATE OR REPLACE PROCEDURE prc_find_objects_by_name(
    IN search_pattern VARCHAR 
) 
AS $$
DECLARE
    obj_record RECORD;  
BEGIN
    RAISE NOTICE 'Objects containing pattern "%":', search_pattern;
    
    FOR obj_record IN
        SELECT 
            'TABLE' AS object_type,      
            tablename AS object_name,   
            'User table' AS description  
        FROM pg_tables                
        WHERE schemaname = 'public'       
            AND tablename ILIKE '%' || search_pattern || '%'
    LOOP
        RAISE NOTICE '%- %: %', 
                     obj_record.object_type,
                     obj_record.object_name,
                     obj_record.description;
    END LOOP;
    
    -- Поиск ФУНКЦИЙ по шаблону имени
    FOR obj_record IN
        SELECT 
            'FUNCTION' AS object_type,   
            p.proname AS object_name,    
            'User function returning ' || format_type(p.prorettype, NULL) AS description
        FROM pg_proc p                 
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'     
            AND p.proname ILIKE '%' || search_pattern || '%'
    LOOP
        RAISE NOTICE '%- %: %', 
                     obj_record.object_type,
                     obj_record.object_name,
                     obj_record.description;
    END LOOP;
    
    -- Поиск ТРИГГЕРОВ по шаблону имени
    FOR obj_record IN
        SELECT 
            'TRIGGER' AS object_type,    
            t.tgname AS object_name, 
            'Trigger on table ' || c.relname AS description
        FROM pg_trigger t          
        JOIN pg_class c ON t.tgrelid = c.oid
        WHERE NOT t.tgisinternal        
            AND t.tgname ILIKE '%' || search_pattern || '%'
    LOOP
        RAISE NOTICE '%- %: %', 
                     obj_record.object_type,
                     obj_record.object_name,
                     obj_record.description;
    END LOOP;
END;
$$ LANGUAGE plpgsql;

COMMENT ON PROCEDURE prc_find_objects_by_name IS 'Ищет объекты по имени и выводит их описание';
