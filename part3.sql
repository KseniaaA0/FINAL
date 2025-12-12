-- 3.1 Функция для читаемого вида TransferredPoints
-- Функция преобразует двунаправленные передачи очков в чистый баланс между пирами
CREATE OR REPLACE FUNCTION fnc_transferred_points_human_readable()
RETURNS TABLE(
    Peer1 VARCHAR,   
    Peer2 VARCHAR,   
    PointsAmount INTEGER 
) AS $$
BEGIN
    RETURN QUERY
    -- Основной запрос вычисляет чистую разницу передач между двумя пирами
    SELECT 
        tp.checkingpeer AS Peer1,  
        tp.checkedpeer AS Peer2, 
        -- Сумма всех очков, переданных от Peer1 к Peer2 
        -- минус очки, переданные обратно (от Peer2 к Peer1)
        SUM(tp.pointsamount) - COALESCE(SUM(tp_reverse.pointsamount), 0) AS PointsAmount
    FROM TransferredPoints tp
    LEFT JOIN TransferredPoints tp_reverse 
        ON tp.checkingpeer = tp_reverse.checkedpeer  
        AND tp.checkedpeer = tp_reverse.checkingpeer 
    GROUP BY tp.checkingpeer, tp.checkedpeer
    ORDER BY Peer1, Peer2;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fnc_transferred_points_human_readable IS 'Возвращает таблицу переданных очков в читаемом виде (чистый баланс)';

-- 3.2 Функция для получения успешных проверок с XP
-- Функция возвращает список всех проверок, за которые были получены XP (т.е. успешных)
CREATE OR REPLACE FUNCTION fnc_successful_checks_with_xp()
RETURNS TABLE(
    Username VARCHAR,
    Task VARCHAR,     
    XP_Amount INTEGER  
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.nickname AS Username,  
        c.task AS Task,        
        x.xpamount AS XP_Amount  
    FROM Peers p
    JOIN Checks c ON p.nickname = c.peer
    JOIN XP x ON c.id = x.Checkid
    ORDER BY p.nickname, c.task;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fnc_successful_checks_with_xp IS 'Возвращает успешные проверки с количеством XP';

-- 3.3 Функция для поиска пиров, не выходивших из кампуса
-- Функция находит пиров, которые за указанную дату только вошли и вышли один раз
CREATE OR REPLACE FUNCTION fnc_peers_never_left_campus(
    check_date DATE DEFAULT CURRENT_DATE  -- Дата для проверки (по умолчанию сегодня)
)
RETURNS TABLE(
    Peer VARCHAR
) AS $$
BEGIN
    RETURN QUERY
    SELECT DISTINCT tt.peer  
    FROM TimeTracking tt
    WHERE tt.Date = check_date 
    GROUP BY tt.peer, tt.Date
    HAVING COUNT(*) = 2  -- Должно быть ровно две записи: вход (1) и выход (2)
        -- Проверяем, что время выхода позже времени входа
        AND MAX(CASE WHEN tt.state = 2 THEN tt.Time END) 
            > MIN(CASE WHEN tt.state = 1 THEN tt.Time END)
        -- Проверяем, что нет дополнительных входов после первого выхода
        -- (это означало бы, что пир выходил и заходил снова)
        AND NOT EXISTS (
            SELECT 1 
            FROM TimeTracking tt2 
            WHERE tt2.peer = tt.peer 
                AND tt2.Date = tt.Date 
                AND tt2.state = 1  
                AND tt2.Time > (
                    SELECT MIN(tt3.Time) 
                    FROM TimeTracking tt3 
                    WHERE tt3.peer = tt.peer 
                        AND tt3.Date = tt.Date 
                        AND tt3.state = 2  
                )
        );
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fnc_peers_never_left_campus IS 'Находит пиров, которые не выходили из кампуса весь день';

-- 3.4 Функция для расчета изменения очков пиров
-- Функция вычисляет итоговый баланс очков для каждого пира
CREATE OR REPLACE FUNCTION fnc_calculate_peer_points_change()
RETURNS TABLE(
    Peer VARCHAR,       
    PointsChange BIGINT  
) AS $$
BEGIN
    RETURN QUERY
    WITH points_given AS (
        SELECT 
            checkingpeer AS peer,      
            SUM(pointsamount) AS points_given  
        FROM TransferredPoints
        GROUP BY checkingpeer
    ),
    points_received AS (
        SELECT 
            checkedpeer AS peer,          
            SUM(pointsamount) AS points_received  
        FROM TransferredPoints
        GROUP BY checkedpeer
    )
    SELECT 
        COALESCE(pg.peer, pr.peer) AS Peer, 
        COALESCE(pr.points_received, 0) - COALESCE(pg.points_given, 0) AS PointsChange
    FROM points_given pg
    FULL OUTER JOIN points_received pr ON pg.peer = pr.peer
    ORDER BY PointsChange DESC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fnc_calculate_peer_points_change IS 'Рассчитывает изменение очков каждого пира (полученные минус отданные)';

-- 3.5 Функция для популярных задач по дням недели
-- Функция определяет самое часто проверяемое задание для каждого дня недели
CREATE OR REPLACE FUNCTION fnc_popular_tasks_by_weekday()
RETURNS TABLE(
    Day VARCHAR,  
    Task VARCHAR  
) AS $$
BEGIN
    RETURN QUERY
    -- CTE для подсчета количества проверок по дням недели и заданиям
    WITH tasks_by_day AS (
        SELECT 
            TO_CHAR(c.Date, 'Day') AS day_name,  
            c.task,                         
            COUNT(*) AS task_count,          
            -- Нумеруем задания внутри каждого дня по убыванию популярности
            ROW_NUMBER() OVER(
                PARTITION BY TO_CHAR(c.Date, 'Day')  
                ORDER BY COUNT(*) DESC             
            ) AS rn
        FROM Checks c
        GROUP BY TO_CHAR(c.Date, 'Day'), c.task
    )
    SELECT 
        day_name AS Day,
        task AS Task
    FROM tasks_by_day
    WHERE rn = 1 
    ORDER BY 
        CASE day_name
            WHEN 'Monday' THEN 1
            WHEN 'Tuesday' THEN 2
            WHEN 'Wednesday' THEN 3
            WHEN 'Thursday' THEN 4
            WHEN 'Friday' THEN 5
            WHEN 'Saturday' THEN 6
            WHEN 'Sunday' THEN 7
        END;
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION fnc_popular_tasks_by_weekday IS 'Возвращает самую популярную задачу для каждого дня недели';
