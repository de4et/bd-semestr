DROP TABLESPACE IF EXISTS fastspace;
CREATE TABLESPACE fastspace LOCATION '/var/lib/postgresql/fastspace';

DROP TABLESPACE IF EXISTS slowspace;
CREATE TABLESPACE slowspace LOCATION '/var/lib/postgresql/slowspace';

DROP SCHEMA IF EXISTS core CASCADE;
CREATE SCHEMA core;

DROP SCHEMA IF EXISTS monitoring CASCADE;
CREATE SCHEMA monitoring;

DROP SCHEMA IF EXISTS integration CASCADE;
CREATE SCHEMA integration;


-- Users
DROP TABLE IF EXISTS core.users CASCADE;
CREATE TABLE core.users (
    id serial PRIMARY KEY,
    plan_id integer NOT NULL,
    email text NOT NULL UNIQUE,
    password_hash text NOT NULL
) TABLESPACE fastspace;
COMMENT ON TABLE core.users IS 'Registered users';
COMMENT ON COLUMN core.users.email IS 'User email address';
COMMENT ON COLUMN core.users.password_hash IS 'Hashed password';

-- Plans
DROP TABLE IF EXISTS core.plan CASCADE;
CREATE TABLE core.plan (
    id serial PRIMARY KEY,
    name text NOT NULL,
    cost numeric(8,2) NOT NULL
) TABLESPACE fastspace;
COMMENT ON TABLE core.plan IS 'Subscription plans';

-- User profile
DROP TABLE IF EXISTS core.user_profile CASCADE;
CREATE TABLE core.user_profile (
    user_id integer PRIMARY KEY REFERENCES core.users(id),
    language char(2) NOT NULL,
    timezone varchar(50) NOT NULL
) TABLESPACE fastspace;
COMMENT ON TABLE core.user_profile IS 'User preferences';
COMMENT ON COLUMN core.user_profile.language IS 'Language code';
COMMENT ON COLUMN core.user_profile.timezone IS 'Timezone';

-- ---------------------------
-- Monitoring tables
-- ---------------------------

-- Sites
DROP TABLE IF EXISTS monitoring.site CASCADE;
CREATE TABLE monitoring.site (
    id serial PRIMARY KEY,
    url text NOT NULL UNIQUE,
    last_checked_at timestamp
) TABLESPACE fastspace;
COMMENT ON TABLE monitoring.site IS 'Monitored websites';

-- Servers
DROP TABLE IF EXISTS monitoring.server CASCADE;
CREATE TABLE monitoring.server (
    id serial PRIMARY KEY,
    name text,
    ip_address text NOT NULL,
    region char(2) NOT NULL
) TABLESPACE fastspace;
COMMENT ON TABLE monitoring.server IS 'Servers where sites are hosted';

truncate monitoring.checks restart identity cascade;
truncate monitoring.server restart identity cascade;

-- Checks
DROP TABLE IF EXISTS monitoring.checks CASCADE;
CREATE TABLE monitoring.checks (
    id serial PRIMARY KEY,
    site_id integer NOT NULL REFERENCES monitoring.site(id),
    server_id integer NOT NULL REFERENCES monitoring.server(id),
    checked_at timestamp NOT NULL,
    status_code integer,
    status text NOT NULL,
    response_time_ms integer
) TABLESPACE fastspace;
COMMENT ON TABLE monitoring.checks IS 'Monitoring results per check';

-- Alert rules
DROP TABLE IF EXISTS monitoring.alert_rule CASCADE;
CREATE TABLE monitoring.alert_rule (
    id serial PRIMARY KEY,
    user_id integer NOT NULL REFERENCES core.users(id),
    site_id integer NOT NULL REFERENCES monitoring.site(id),
    notification_channel_id integer NOT NULL,
    metric text NOT NULL,
    operator varchar(2) NOT NULL,
    threshold integer NOT NULL
) TABLESPACE slowspace;
COMMENT ON TABLE monitoring.alert_rule IS 'Rules for triggering alerts';

-- Alerts
DROP TABLE IF EXISTS monitoring.alert CASCADE;
CREATE TABLE monitoring.alert (
    id serial PRIMARY KEY,
    user_id integer NOT NULL REFERENCES core.users(id),
    check_id integer NOT NULL REFERENCES monitoring.checks(id),
    alert_rule_id integer NOT NULL REFERENCES monitoring.alert_rule(id),
    type text NOT NULL,
    triggered_at timestamp NOT NULL
) TABLESPACE fastspace;
COMMENT ON TABLE monitoring.alert IS 'Triggered alerts';

-- ---------------------------
-- Integration tables
-- ---------------------------

-- Notification channels
DROP TABLE IF EXISTS integration.notification_channel CASCADE;
CREATE TABLE integration.notification_channel (
    id serial PRIMARY KEY,
    platform text NOT NULL,
    identifier text NOT NULL
) TABLESPACE fastspace;
COMMENT ON TABLE integration.notification_channel IS 'Notification delivery channels';

-- Users <-> Sites mapping
DROP TABLE IF EXISTS integration.users_sites CASCADE;
CREATE TABLE integration.users_sites (
    user_id integer NOT NULL REFERENCES core.users(id),
    site_id integer NOT NULL REFERENCES monitoring.site(id),
    PRIMARY KEY(user_id, site_id)
) TABLESPACE fastspace;
COMMENT ON TABLE integration.users_sites IS 'Mapping of users to monitored sites';


-- Преобразуем timestamp в timestamp with time zone

ALTER TABLE monitoring.alert
    ALTER COLUMN triggered_at TYPE timestamptz
    USING triggered_at AT TIME ZONE 'UTC';

ALTER TABLE monitoring.checks
    ALTER COLUMN checked_at TYPE timestamptz
    USING checked_at AT TIME ZONE 'UTC';

ALTER TABLE monitoring.site
    ALTER COLUMN last_checked_at TYPE timestamptz
    USING last_checked_at AT TIME ZONE 'UTC';


-- Функция для автоматического преобразования password_hash в MD5
CREATE OR REPLACE FUNCTION core.users_md5_password()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.password_hash IS NOT NULL THEN
        NEW.password_hash := MD5(NEW.password_hash);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Триггер для вставки и обновления
CREATE TRIGGER trg_users_md5_password
BEFORE INSERT OR UPDATE ON core.users
FOR EACH ROW
EXECUTE FUNCTION core.users_md5_password();


-- Ограничения для core.checks
ALTER TABLE monitoring.checks
    ADD CONSTRAINT checks_status_check
    CHECK (status IN ('UP', 'DOWN'));

-- Ограничения для monitoring.alert_rule
ALTER TABLE monitoring.alert_rule
    ADD CONSTRAINT alert_rule_operator_check
    CHECK (operator IN ('=', '!=', '<', '<=', '>', '>='));

ALTER TABLE monitoring.alert_rule
    ADD CONSTRAINT alert_rule_metric_check
    CHECK (metric IN ('response_time', 'status_code'));

-- Ограничения для monitoring.alert
ALTER TABLE monitoring.alert
    ADD CONSTRAINT alert_type_check
    CHECK (type IN ('DOWNTIME', 'HIGH_LATENCY', 'OTHER'));

-- Комментарии для core.users
COMMENT ON COLUMN core.users.id IS 'Primary key for users';
COMMENT ON COLUMN core.users.plan_id IS 'Reference to plan';
COMMENT ON COLUMN core.users.email IS 'User email address';
COMMENT ON COLUMN core.users.password_hash IS 'Hashed password (MD5 via trigger)';

-- Комментарии для core.plan
COMMENT ON COLUMN core.plan.id IS 'Primary key for plan';
COMMENT ON COLUMN core.plan.name IS 'Plan name';
COMMENT ON COLUMN core.plan.cost IS 'Plan cost';

-- Комментарии для core.user_profile
COMMENT ON COLUMN core.user_profile.user_id IS 'Reference to user';
COMMENT ON COLUMN core.user_profile.language IS 'Language code';
COMMENT ON COLUMN core.user_profile.timezone IS 'User timezone';

-- Комментарии для monitoring.site
COMMENT ON COLUMN monitoring.site.id IS 'Primary key for site';
COMMENT ON COLUMN monitoring.site.url IS 'Site URL';
COMMENT ON COLUMN monitoring.site.last_checked_at IS 'Timestamp of last check (timestamptz)';

-- Комментарии для monitoring.server
COMMENT ON COLUMN monitoring.server.id IS 'Primary key for server';
COMMENT ON COLUMN monitoring.server.name IS 'Server name';
COMMENT ON COLUMN monitoring.server.ip_address IS 'Server IP address';
COMMENT ON COLUMN monitoring.server.region IS 'Server region code';

-- Комментарии для monitoring.checks
COMMENT ON COLUMN monitoring.checks.id IS 'Primary key for check';
COMMENT ON COLUMN monitoring.checks.site_id IS 'Reference to site';
COMMENT ON COLUMN monitoring.checks.server_id IS 'Reference to server';
COMMENT ON COLUMN monitoring.checks.checked_at IS 'Check timestamp (timestamptz)';
COMMENT ON COLUMN monitoring.checks.status_code IS 'HTTP status code';
COMMENT ON COLUMN monitoring.checks.status IS 'Check status (UP/DOWN)';
COMMENT ON COLUMN monitoring.checks.response_time_ms IS 'Response time in milliseconds';

-- Комментарии для monitoring.alert_rule
COMMENT ON COLUMN monitoring.alert_rule.id IS 'Primary key for alert rule';
COMMENT ON COLUMN monitoring.alert_rule.user_id IS 'Reference to user';
COMMENT ON COLUMN monitoring.alert_rule.site_id IS 'Reference to site';
COMMENT ON COLUMN monitoring.alert_rule.notification_channel_id IS 'Reference to notification channel';
COMMENT ON COLUMN monitoring.alert_rule.metric IS 'Metric to monitor';
COMMENT ON COLUMN monitoring.alert_rule.operator IS 'Comparison operator';
COMMENT ON COLUMN monitoring.alert_rule.threshold IS 'Threshold value';

-- Комментарии для monitoring.alert
COMMENT ON COLUMN monitoring.alert.id IS 'Primary key for alert';
COMMENT ON COLUMN monitoring.alert.user_id IS 'Reference to user';
COMMENT ON COLUMN monitoring.alert.check_id IS 'Reference to check';
COMMENT ON COLUMN monitoring.alert.alert_rule_id IS 'Reference to alert rule';
COMMENT ON COLUMN monitoring.alert.type IS 'Alert type';
COMMENT ON COLUMN monitoring.alert.triggered_at IS 'Timestamp when alert was triggered (timestamptz)';

-- Комментарии для integration.notification_channel
COMMENT ON COLUMN integration.notification_channel.id IS 'Primary key for notification channel';
COMMENT ON COLUMN integration.notification_channel.platform IS 'Platform (email, slack, telegram, webhook)';
COMMENT ON COLUMN integration.notification_channel.identifier IS 'Destination identifier (email, webhook URL, etc.)';

-- Комментарии для integration.users_sites
COMMENT ON COLUMN integration.users_sites.user_id IS 'Reference to user';
COMMENT ON COLUMN integration.users_sites.site_id IS 'Reference to site';

DO $$
DECLARE
    i int;
BEGIN
    FOR i IN 5..404 LOOP
        INSERT INTO core.users(plan_id, email, password_hash)
        VALUES (
            (i % 3) + 1,  -- случайный план от 1 до 3
            'user'||i||'@example.com',
            'password'||i
        );
    END LOOP;
END $$;

-- Генерация профилей пользователей
DO $$
DECLARE
    i int;
    langs text[] := ARRAY['EN','FR','DE','ES','IT'];
    tzs text[] := ARRAY['America/New_York','Europe/Paris','Europe/Berlin','Asia/Tokyo','America/Los_Angeles'];
BEGIN
    FOR i IN 5..404 LOOP
        INSERT INTO core.user_profile(user_id, language, timezone)
        VALUES (
            i,
            langs[(i % array_length(langs,1)) + 1],
            tzs[(i % array_length(tzs,1)) + 1]
        );
    END LOOP;
END $$;

DO $$
DECLARE
    i int;
    base_domains text[] := ARRAY['example','google','github','stackoverflow','yahoo','bing','reddit','medium','amazon','facebook','twitter','linkedin','apple','microsoft','netflix','spotify'];
    suffixes text[] := ARRAY['shop','blog','news','app','service','portal','hub','site'];
    tlds text[] := ARRAY['.com','.net','.org','.io','.co'];
BEGIN
    FOR i IN 5..404 LOOP
        INSERT INTO monitoring.site(url, last_checked_at)
        VALUES (
            'https://' ||
            base_domains[(i % array_length(base_domains,1)) + 1] ||
            '-' ||
            suffixes[(i % array_length(suffixes,1)) + 1] ||
            (i % 100) ||  -- добавляем номер для уникальности
            tlds[(i % array_length(tlds,1)) + 1],
            NOW() - (i % 30) * interval '1 day'
        );
    END LOOP;
END $$;

-- ---------------------------
-- Генерация серверов
-- ---------------------------
DO $$
DECLARE
    i int;
    regions text[] := ARRAY['US','EU','AS','AU','SA'];
BEGIN
    FOR i IN 5..54 LOOP
        INSERT INTO monitoring.server(name, ip_address, region)
        VALUES (
            'Server-'||i,
            '192.168.'|| (i % 254) || '.' || (i % 254),
            regions[(i % array_length(regions,1)) + 1]
        );
    END LOOP;
END $$;

-- ---------------------------
-- Генерация checks
-- ---------------------------
DO $$
DECLARE
    i int;
    site_count int := (SELECT COUNT(*) FROM monitoring.site);
    server_count int := (SELECT COUNT(*) FROM monitoring.server);
    status_options text[] := ARRAY['UP','DOWN'];
BEGIN
    FOR i IN 1..1000 LOOP
        INSERT INTO monitoring.checks(site_id, server_id, checked_at, status_code, status, response_time_ms)
        VALUES (
            (i % site_count) + 1,
            (i % server_count) + 1,
            NOW() - (i % 30) * interval '1 hour',
            CASE WHEN (i % 10 = 0) THEN 503 ELSE 200 END,
            status_options[(i % array_length(status_options,1)) + 1],
            50 + (i % 500)
        );
    END LOOP;
END $$;

-- ---------------------------
-- Генерация alert_rule
-- ---------------------------
DO $$
DECLARE
    i int;
    user_count int := (SELECT COUNT(*) FROM core.users);
    site_count int := (SELECT COUNT(*) FROM monitoring.site);
    channel_count int := (SELECT COUNT(*) FROM integration.notification_channel);
    metrics text[] := ARRAY['response_time','status_code'];
    operators text[] := ARRAY['=','!=','<','<=','>','>='];
BEGIN
    FOR i IN 5..404 LOOP
        INSERT INTO monitoring.alert_rule(user_id, site_id, notification_channel_id, metric, operator, threshold)
        VALUES (
            (i % user_count) + 1,
            (i % site_count) + 1,
            (i % channel_count) + 1,
            metrics[(i % array_length(metrics,1)) + 1],
            operators[(i % array_length(operators,1)) + 1],
            50 + (i % 500)
        );
    END LOOP;
END $$;

truncate monitoring.alert_rule restart identity cascade;
truncate monitoring.alert restart identity cascade;
-- ---------------------------
-- Генерация alerts
-- ---------------------------
DO $$
DECLARE
    i int;
    user_count int := (SELECT COUNT(*) FROM core.users);
    check_count int := (SELECT COUNT(*) FROM monitoring.checks);
    rule_count int := (SELECT COUNT(*) FROM monitoring.alert_rule);
    types text[] := ARRAY['DOWNTIME','HIGH_LATENCY','OTHER'];
BEGIN
    FOR i IN 1..500 LOOP
        INSERT INTO monitoring.alert(user_id, check_id, alert_rule_id, type, triggered_at)
        VALUES (
            (i % user_count) + 1,
            (i % check_count) + 1,
            (i % rule_count) + 1,
            types[(i % array_length(types,1)) + 1],
            NOW() - (i % 100) * interval '1 hour'
        );
    END LOOP;
END $$;

-- ---------------------------
-- Генерация notification_channel
-- ---------------------------
DO $$
DECLARE
    i int;
    platforms text[] := ARRAY['email','slack','telegram','webhook','sms','push'];
BEGIN
    FOR i IN 5..504 LOOP
        INSERT INTO integration.notification_channel(platform, identifier)
        VALUES (
            platforms[(i % array_length(platforms,1)) + 1],
            CASE
                WHEN (i % 6 = 0) THEN 'user'||i||'@example.com'
                WHEN (i % 6 = 1) THEN 'https://hooks.slack.com/services/'||i
                WHEN (i % 6 = 2) THEN '@telegram_user'||i
                WHEN (i % 6 = 3) THEN 'https://webhook.example.com/'||i
                WHEN (i % 6 = 4) THEN '+1234567'||i
                ELSE 'push_token_'||i
            END
        );
    END LOOP;
END $$;

-- ---------------------------
-- Генерация users_sites
-- ---------------------------
DO $$
DECLARE
    i int;
    user_count int := (SELECT COUNT(*) FROM core.users);
    site_count int := (SELECT COUNT(*) FROM monitoring.site);
BEGIN
    FOR i IN 1..500 LOOP
        INSERT INTO integration.users_sites(user_id, site_id)
        VALUES (
            ((i*7) % user_count) + 1,
            ((i*3) % site_count) + 1
        )
        ON CONFLICT DO NOTHING;  -- чтобы не было дубликатов
    END LOOP;
END $$;