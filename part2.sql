-- Процедура добавления P2P проверки
-- Процедура для добавления P2P проверки и автоматического обновления связанных таблиц
CREATE OR REPLACE PROCEDURE add_p2p_check(
    checking_peer VARCHAR,    -- Ник проверяющего пира
    checked_peer VARCHAR,     -- Ник проверяемого пира
    task_name VARCHAR,        -- Название задания
    check_status status,      -- Статус проверки (Start/Success/Failure)
    check_time TIME DEFAULT CURRENT_TIME  -- Время проверки (по умолчанию текущее)
) AS $$
DECLARE
    check_id BIGINT;         
BEGIN
    -- Используем ON CONFLICT DO NOTHING чтобы избежать дубликатов
    INSERT INTO Checks(peer, task, Date)
    VALUES (checked_peer, task_name, CURRENT_DATE)
    ON CONFLICT DO NOTHING
    RETURNING id INTO check_id;  -- Сохраняем ID созданной записи
    
    -- Если запись уже существовала (не была создана), получаем её ID
    IF check_id IS NULL THEN
        SELECT id INTO check_id
        FROM Checks
        WHERE peer = checked_peer AND task = task_name
        ORDER BY Date DESC, id DESC 
        LIMIT 1;
    END IF;
    
    -- Вставляем запись в таблицу P2P с полученным ID проверки
    INSERT INTO P2P(Checkid, checkingpeer, state, Time)
    VALUES (check_id, checking_peer, check_status, check_time);
    
    -- Обновляем таблицу переданных очков только при начале проверки
    IF check_status = 'Start' THEN
        INSERT INTO TransferredPoints(checkingpeer, checkedpeer, pointsamount)
        VALUES (checking_peer, checked_peer, 1)
        ON CONFLICT (checkingpeer, checkedpeer) 
        DO UPDATE SET pointsamount = TransferredPoints.pointsamount + 1;
    END IF;
    
END;
$$ LANGUAGE plpgsql;

COMMENT ON PROCEDURE add_p2p_check IS 'Добавляет P2P проверку и обновляет TransferredPoints';

-- 2.2 Процедура добавления проверки Verter
-- Процедура для добавления автоматической проверки Verter
CREATE OR REPLACE PROCEDURE add_verter_check(
    checked_peer VARCHAR,     -- Ник проверяемого пира
    task_name VARCHAR,        -- Название задания
    check_status status,      -- Статус проверки
    check_time TIME DEFAULT CURRENT_TIME  -- Время проверки
) AS $$
DECLARE
    check_id BIGINT;         
BEGIN
    -- Находим последнюю УСПЕШНУЮ P2P проверку для данного пира и задания
    -- Verter проверка возможна только после успешной P2P проверки
    SELECT c.id INTO check_id
    FROM Checks c
    JOIN P2P p ON c.id = p.Checkid
    WHERE c.peer = checked_peer 
        AND c.task = task_name 
        AND p.state = 'Success' 
    ORDER BY p.Time DESC         
    LIMIT 1;
    
    -- Если нашли успешную проверку, добавляем запись в Verter
    IF check_id IS NOT NULL THEN
        INSERT INTO Verter(Checkid, state, Time)
        VALUES (check_id, check_status, check_time);
    ELSE
        -- Если нет успешной P2P проверки, выбрасываем исключение
        RAISE EXCEPTION 'No successful P2P check found for peer % and task %', 
                        checked_peer, task_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

COMMENT ON PROCEDURE add_verter_check IS 'Добавляет проверку Verter для успешной P2P проверки';

-- 2.3 Триггерная функция для контроля вставки в P2P
-- Функция проверяет корректность состояний при добавлении P2P записей
CREATE OR REPLACE FUNCTION fnc_trg_p2p_insert() 
RETURNS TRIGGER AS $$
BEGIN
    -- Проверяем, что для одного Checkid не может быть двух записей со статусом 'Start'
    IF NEW.state = 'Start' THEN
        IF EXISTS (
            SELECT 1 FROM P2P 
            WHERE Checkid = NEW.Checkid AND state = 'Start'
        ) THEN
            RAISE EXCEPTION 'Cannot have multiple Start states for the same check';
        END IF;
    END IF;
    
    -- Проверяем, что записи идут в правильном порядке: Start -> Success/Failure
    IF NEW.state IN ('Success', 'Failure') THEN
        IF NOT EXISTS (
            SELECT 1 FROM P2P 
            WHERE Checkid = NEW.Checkid AND state = 'Start'
        ) THEN
            RAISE EXCEPTION 'Cannot have % state without Start state', NEW.state;
        END IF;
    END IF;
    
    RETURN NEW;  
END;
$$ LANGUAGE plpgsql;

-- Создаем триггер, который вызывается ПЕРЕД вставкой в таблицу P2P
CREATE TRIGGER trg_p2p_insert
BEFORE INSERT ON P2P
FOR EACH ROW                   
EXECUTE FUNCTION fnc_trg_p2p_insert();

COMMENT ON TRIGGER trg_p2p_insert ON P2P IS 'Проверяет корректность состояний P2P проверок';

-- 2.4 Триггерная функция для контроля вставки в XP
-- Функция проверяет корректность добавления XP при вставке в таблицу XP
CREATE OR REPLACE FUNCTION fnc_trg_xp_insert() 
RETURNS TRIGGER AS $$
DECLARE
    max_xp INTEGER;        
    p2p_status status;      
    verter_status status;    
BEGIN
    -- Получаем максимальное XP для задания из связанной таблицы Tasks
    SELECT t.maxxp INTO max_xp
    FROM Checks c
    JOIN Tasks t ON c.task = t.title
    WHERE c.id = NEW.Checkid;  
    
    -- Проверяем, что добавляемое XP не превышает максимальное для задания
    IF NEW.xpamount > max_xp THEN
        RAISE EXCEPTION 'XP amount % exceeds maximum % for this task', 
                        NEW.xpamount, max_xp;
    END IF;
    
    -- Проверяем, что P2P проверка была успешной
    -- Ищем последний статус P2P проверки (Success или Failure)
    SELECT state INTO p2p_status
    FROM P2P
    WHERE Checkid = NEW.Checkid AND state IN ('Success', 'Failure')
    ORDER BY Time DESC 
    LIMIT 1;
    
    -- Если P2P проверка не существует или не успешна, запрещаем добавление XP
    IF p2p_status IS NULL OR p2p_status != 'Success' THEN
        RAISE EXCEPTION 'Cannot add XP for unsuccessful P2P check';
    END IF;
    
    -- Проверяем, что проверка Verter (если есть) также успешна
    SELECT state INTO verter_status
    FROM Verter
    WHERE Checkid = NEW.Checkid
    ORDER BY Time DESC  
    LIMIT 1;
    
    -- Если Verter проверка существует и не успешна, запрещаем добавление XP
    IF verter_status IS NOT NULL AND verter_status != 'Success' THEN
        RAISE EXCEPTION 'Cannot add XP for unsuccessful Verter check';
    END IF;
    
    RETURN NEW; 
END;
$$ LANGUAGE plpgsql;

-- Создаем триггер, который вызывается ПЕРЕД вставкой в таблицу XP
CREATE TRIGGER trg_xp_insert
BEFORE INSERT ON XP
FOR EACH ROW                    
EXECUTE FUNCTION fnc_trg_xp_insert();

COMMENT ON TRIGGER trg_xp_insert ON XP IS 'Проверяет корректность добавления XP';
