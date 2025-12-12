-- 1.1 Создание базы данных
DROP DATABASE IF EXISTS info21;
CREATE DATABASE info21;

\c info21

-- 1.2 Создание типов данных
CREATE TYPE status AS ENUM ('Start', 'Success', 'Failure');

-- 1.3 Создание таблиц в правильном порядке
-- 1. Peers - таблица пиров (базовая таблица, на которую ссылаются многие другие)
CREATE TABLE IF NOT EXISTS Peers (
    nickname VARCHAR PRIMARY KEY,        -- Уникальный никнейм пира (основной идентификатор)
    birthday DATE NOT NULL               -- Дата рождения, обязательное поле
);

COMMENT ON TABLE Peers IS 'Таблица информации о пирах';
COMMENT ON COLUMN Peers.nickname IS 'Никнейм пира (первичный ключ)';
COMMENT ON COLUMN Peers.birthday IS 'Дата рождения пира';

-- 2. Tasks - таблица заданий (имеет рекурсивную связь на саму себя)
CREATE TABLE IF NOT EXISTS Tasks (
    title VARCHAR PRIMARY KEY,           -- Название задания (уникальное)
    parenttask VARCHAR REFERENCES Tasks(title), -- Ссылка на родительское задание (может быть NULL)
    maxxp INTEGER NOT NULL CHECK (maxxp > 0) -- Максимальное кол-во XP, должно быть положительным
);

COMMENT ON TABLE Tasks IS 'Таблица заданий';
COMMENT ON COLUMN Tasks.title IS 'Название задания (первичный ключ)';
COMMENT ON COLUMN Tasks.parenttask IS 'Родительское задание (ссылка на title)';
COMMENT ON COLUMN Tasks.maxxp IS 'Максимальное количество XP за задание';

-- 3. Checks - таблица проверок (связывает пиров и задания)
CREATE TABLE IF NOT EXISTS Checks (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY, 
    peer VARCHAR NOT NULL REFERENCES Peers(nickname),  
    task VARCHAR NOT NULL REFERENCES Tasks(title),      
    Date DATE NOT NULL DEFAULT CURRENT_DATE            
);

COMMENT ON TABLE Checks IS 'Таблица проверок заданий';
COMMENT ON COLUMN Checks.id IS 'ID проверки (автоинкремент)';
COMMENT ON COLUMN Checks.peer IS 'Проверяемый пир';
COMMENT ON COLUMN Checks.task IS 'Проверяемое задание';
COMMENT ON COLUMN Checks.Date IS 'Дата проверки';

-- 4. P2P - таблица P2P проверок (отслеживает процесс проверки между пирами)
CREATE TABLE IF NOT EXISTS P2P (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    Checkid BIGINT NOT NULL REFERENCES Checks(id),      -- Ссылка на проверку
    checkingpeer VARCHAR NOT NULL REFERENCES Peers(nickname), -- Кто проверяет
    state status NOT NULL,                               -- Статус из ENUM типа
    Time TIME NOT NULL DEFAULT CURRENT_TIME              -- Время действия
);

COMMENT ON TABLE P2P IS 'Таблица P2P проверок';
COMMENT ON COLUMN P2P.Checkid IS 'ID проверки из таблицы Checks';
COMMENT ON COLUMN P2P.checkingpeer IS 'Проверяющий пир';
COMMENT ON COLUMN P2P.state IS 'Статус проверки (Start/Success/Failure)';
COMMENT ON COLUMN P2P.Time IS 'Время проверки';

-- 5. Verter - таблица автоматических проверок Verter
CREATE TABLE IF NOT EXISTS Verter (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    Checkid BIGINT NOT NULL REFERENCES Checks(id), -- Ссылка на проверку
    state status NOT NULL,                          -- Статус проверки
    Time TIME NOT NULL DEFAULT CURRENT_TIME         -- Время проверки
);

COMMENT ON TABLE Verter IS 'Таблица проверок Verter';
COMMENT ON COLUMN Verter.Checkid IS 'ID проверки из таблицы Checks';
COMMENT ON COLUMN Verter.state IS 'Статус проверки (Start/Success/Failure)';
COMMENT ON COLUMN Verter.Time IS 'Время проверки';

-- 6. TransferredPoints - таблица учета передаваемых очков между пирами
CREATE TABLE IF NOT EXISTS TransferredPoints (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    checkingpeer VARCHAR NOT NULL REFERENCES Peers(nickname), -- Кто проверял
    checkedpeer VARCHAR NOT NULL REFERENCES Peers(nickname),  -- Кого проверяли
    pointsamount INTEGER NOT NULL DEFAULT 1 CHECK (pointsamount > 0) -- Кол-во очков
);

COMMENT ON TABLE TransferredPoints IS 'Таблица переданных очков между пирами';
COMMENT ON COLUMN TransferredPoints.checkingpeer IS 'Пир, который проверял';
COMMENT ON COLUMN TransferredPoints.checkedpeer IS 'Пир, которого проверяли';
COMMENT ON COLUMN TransferredPoints.pointsamount IS 'Количество переданных очков';

-- 7. Friends - таблица дружеских связей (симметричные отношения)
CREATE TABLE IF NOT EXISTS Friends (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    peer1 VARCHAR NOT NULL REFERENCES Peers(nickname), -- Первый друг
    peer2 VARCHAR NOT NULL REFERENCES Peers(nickname), -- Второй друг
    CHECK (peer1 <> peer2) -- Запрещаем дружбу с самим собой
);

COMMENT ON TABLE Friends IS 'Таблица дружеских связей между пирами';
COMMENT ON COLUMN Friends.peer1 IS 'Первый пир в дружбе';
COMMENT ON COLUMN Friends.peer2 IS 'Второй пир в дружбе';

-- 8. Recommendations - таблица рекомендаций (кто кого рекомендует)
CREATE TABLE IF NOT EXISTS Recommendations (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    peer VARCHAR NOT NULL REFERENCES Peers(nickname),     
    recommendedpeer VARCHAR NOT NULL REFERENCES Peers(nickname), 
    CHECK (peer <> recommendedpeer) 
);

COMMENT ON TABLE Recommendations IS 'Таблица рекомендаций пиров друг другу';
COMMENT ON COLUMN Recommendations.peer IS 'Пир, который рекомендует';
COMMENT ON COLUMN Recommendations.recommendedpeer IS 'Рекомендуемый пир';

-- 9. XP - таблица полученного опыта за успешные проверки
CREATE TABLE IF NOT EXISTS XP (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    Checkid BIGINT NOT NULL REFERENCES Checks(id), -- Ссылка на успешную проверку
    xpamount INTEGER NOT NULL CHECK (xpamount > 0) -- Кол-во полученного XP
);

COMMENT ON TABLE XP IS 'Таблица полученных XP за задания';
COMMENT ON COLUMN XP.Checkid IS 'ID проверки из таблицы Checks';
COMMENT ON COLUMN XP.xpamount IS 'Количество полученных XP';

-- 10. TimeTracking - таблица отслеживания времени в кампусе
CREATE TABLE IF NOT EXISTS TimeTracking (
    id BIGINT PRIMARY KEY GENERATED ALWAYS AS IDENTITY,
    peer VARCHAR NOT NULL REFERENCES Peers(nickname), -- Пир
    Date DATE NOT NULL DEFAULT CURRENT_DATE,          -- Дата события
    Time TIME NOT NULL DEFAULT CURRENT_TIME,          -- Время события
    state INTEGER NOT NULL CHECK (state IN (1, 2))    -- 1 = вход, 2 = выход
);

COMMENT ON TABLE TimeTracking IS 'Таблица отслеживания времени посещения кампуса';
COMMENT ON COLUMN TimeTracking.peer IS 'Пир, который вошел/вышел';
COMMENT ON COLUMN TimeTracking.Date IS 'Дата события';
COMMENT ON COLUMN TimeTracking.Time IS 'Время события';
COMMENT ON COLUMN TimeTracking.state IS 'Состояние (1 - вход, 2 - выход)';

-- 1.4 Создание индексов для улучшения производительности
CREATE INDEX IF NOT EXISTS idx_checks_peer ON Checks(peer);
CREATE INDEX IF NOT EXISTS idx_checks_task ON Checks(task);
CREATE INDEX IF NOT EXISTS idx_p2p_checkid ON P2P(Checkid);
CREATE INDEX IF NOT EXISTS idx_verter_checkid ON Verter(Checkid);
CREATE INDEX IF NOT EXISTS idx_xp_checkid ON XP(Checkid);
CREATE INDEX IF NOT EXISTS idx_timetracking_peer_date ON TimeTracking(peer, Date);
