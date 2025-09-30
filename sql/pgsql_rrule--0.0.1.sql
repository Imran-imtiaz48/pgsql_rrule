-- ==========================================
-- RRULE Implementation in PostgreSQL
-- Based on RFC-5545
-- ==========================================

-- -------------------------
-- ENUM Types
-- -------------------------
CREATE TYPE rrule_freq AS ENUM (
    'SECONDLY',
    'MINUTELY',
    'HOURLY',
    'DAILY',
    'WEEKLY',
    'MONTHLY',
    'YEARLY'
);

CREATE TYPE rrule_weekday AS ENUM ('SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA');

-- -------------------------
-- Weekday Functions
-- -------------------------
CREATE FUNCTION rrule_weekday(dow integer) RETURNS rrule_weekday
    LANGUAGE sql IMMUTABLE
AS $$
VALUES(CASE dow
    WHEN 0 THEN 'SU'::rrule_weekday
    WHEN 1 THEN 'MO'::rrule_weekday
    WHEN 2 THEN 'TU'::rrule_weekday
    WHEN 3 THEN 'WE'::rrule_weekday
    WHEN 4 THEN 'TH'::rrule_weekday
    WHEN 5 THEN 'FR'::rrule_weekday
    WHEN 6 THEN 'SA'::rrule_weekday
END);
$$;

CREATE FUNCTION dow(day rrule_weekday) RETURNS integer
    LANGUAGE sql IMMUTABLE
AS $$
VALUES(CASE day
    WHEN 'SU' THEN 0
    WHEN 'MO' THEN 1
    WHEN 'TU' THEN 2
    WHEN 'WE' THEN 3
    WHEN 'TH' THEN 4
    WHEN 'FR' THEN 5
    WHEN 'SA' THEN 6
END);
$$;

-- -------------------------
-- Weekday Number Type
-- -------------------------
CREATE TYPE rrule_weekdaynum AS (week integer, day rrule_weekday);

CREATE FUNCTION rrule_weekdaynum(raw text) RETURNS rrule_weekdaynum
    LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
    parsed rrule_weekdaynum;
BEGIN
    parsed.week = substring(raw from '^((?:\+|-)?\d+)?\w\w$');
    IF parsed.week IS NOT NULL AND parsed.week NOT BETWEEN -53 AND -1 AND parsed.week NOT BETWEEN 1 AND 53 THEN
        RAISE EXCEPTION 'Invalid weekdaynum=%.', raw;
    END IF;
    parsed.day = upper(substring(raw from '^(?:(?:\+|-)?\d+)?(\w\w)$'));
    IF parsed.day IS NULL THEN RAISE EXCEPTION 'Invalid weekdaynum=%.', raw; END IF;
    RETURN parsed;
END;
$$;

-- -------------------------
-- Main RRULE Type
-- -------------------------
CREATE TYPE rrule AS (
    freq rrule_freq,
    until text,
    count integer,
    "interval" integer,
    bysecond integer[],
    byminute integer[],
    byhour integer[],
    byday rrule_weekdaynum[],
    bymonthday integer[],
    byyearday integer[],
    byweekno integer[],
    bymonth integer[],
    bysetpos integer[],
    wkst rrule_weekday
);

-- -------------------------
-- Parser Function
-- -------------------------
CREATE FUNCTION rrule(raw text) RETURNS rrule
    LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
    parsed rrule;
    part text;
    field text;
    value text;
    ivalues integer[];
BEGIN
    FOREACH part IN ARRAY regexp_split_to_array(raw, ';') LOOP
        field = substring(part from '^(\w+)=');
        IF field IS NULL THEN
            RAISE EXCEPTION 'Malformed rrule part %.', part;
        END IF;
        value = substring(part from '^\w+=(.*)');

        CASE upper(field)
        WHEN 'FREQ' THEN
            parsed.freq = upper(value);

        WHEN 'UNTIL' THEN
            IF value !~ '^\d{8}(?:T\d{6}Z?)?$' THEN RAISE EXCEPTION 'Invalid UNTIL=%.', value; END IF;
            parsed.until = value;

        WHEN 'COUNT' THEN
            IF value !~ '^\d+$' THEN RAISE EXCEPTION 'Invalid COUNT=%.', value; END IF;
            parsed.count = value;

        WHEN 'INTERVAL' THEN
            IF value !~ '^\d+$' THEN RAISE EXCEPTION 'Invalid INTERVAL=%.', value; END IF;
            parsed.interval = value;

        WHEN 'BYSECOND' THEN
            ivalues = regexp_split_to_array(value, ',');
            IF 0 > ANY(ivalues) OR 60 < ANY(ivalues) THEN RAISE EXCEPTION 'Invalid BYSECOND=%.', value; END IF;
            parsed.bysecond = ivalues;

        WHEN 'BYMINUTE' THEN
            ivalues = regexp_split_to_array(value, ',');
            IF 0 > ANY(ivalues) OR 59 < ANY(ivalues) THEN RAISE EXCEPTION 'Invalid BYMINUTE=%.', value; END IF;
            parsed.byminute = ivalues;

        WHEN 'BYHOUR' THEN
            ivalues = regexp_split_to_array(value, ',');
            IF 0 > ANY(ivalues) OR 23 < ANY(ivalues) THEN RAISE EXCEPTION 'Invalid BYHOUR=%.', value; END IF;
            parsed.byhour = ivalues;

        WHEN 'BYDAY' THEN
            FOREACH value IN ARRAY regexp_split_to_array(value, ',') LOOP
                parsed.byday = array_append(parsed.byday, rrule_weekdaynum(value));
            END LOOP;

        WHEN 'BYMONTHDAY' THEN
            ivalues = regexp_split_to_array(value, ',');
            IF -31 > ANY(ivalues) OR 31 < ANY(ivalues) OR 0 = ANY(ivalues) THEN RAISE EXCEPTION 'Invalid BYMONTHDAY=%.', value; END IF;
            parsed.bymonthday = ivalues;

        WHEN 'BYYEARDAY' THEN
            ivalues = regexp_split_to_array(value, ',');
            IF -366 > ANY(ivalues) OR 366 < ANY(ivalues) OR 0 = ANY(ivalues) THEN RAISE EXCEPTION 'Invalid BYYEARDAY=%.', value; END IF;
            parsed.byyearday = ivalues;

        WHEN 'BYWEEKNO' THEN
            ivalues = regexp_split_to_array(value, ',');
            IF -53 > ANY(ivalues) OR 53 < ANY(ivalues) OR 0 = ANY(ivalues) THEN RAISE EXCEPTION 'Invalid BYWEEKNO=%.', value; END IF;
            parsed.byweekno = ivalues;

        WHEN 'BYMONTH' THEN
            ivalues = regexp_split_to_array(value, ',');
            IF 1 > ANY(ivalues) OR 12 < ANY(ivalues) THEN RAISE EXCEPTION 'Invalid BYMONTH=%.', value; END IF;
            parsed.bymonth = ivalues;

        WHEN 'BYSETPOS' THEN
            ivalues = regexp_split_to_array(value, ',');
            IF -366 > ANY(ivalues) OR 366 < ANY(ivalues) OR 0 = ANY(ivalues) THEN RAISE EXCEPTION 'Invalid BYSETPOS=%.', value; END IF;
            parsed.bysetpos = ivalues;

        WHEN 'WKST' THEN
            parsed.wkst = upper(value);

        ELSE
            RAISE EXCEPTION 'Invalid rrule part %.', field;
        END CASE;
    END LOOP;

    IF parsed.freq IS NULL THEN
        RAISE EXCEPTION 'Invalid rrule missing FREQ.';
    END IF;
    RETURN parsed;
END;
$$;

-- -------------------------
-- Expander Functions
-- -------------------------
CREATE FUNCTION rrule_expand(rule rrule, dtstart date, until date) RETURNS TABLE(occurrence date)
    LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
    rule.byhour = NULL;
    rule.byminute = NULL;
    rule.bysecond = NULL;
    rule.until = rule.until::date;

    RETURN QUERY SELECT rrule_expand(rule, dtstart::timestamp, until::timestamp)::date;
END;
$$;

CREATE FUNCTION rrule_expand(rule rrule, dtstart timestamp without time zone, until timestamp without time zone)
    RETURNS TABLE(occurrence timestamp without time zone)
    LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
    wkst rrule_weekday = COALESCE(rule.wkst, 'MO');
    wksti integer;
BEGIN
    until = LEAST(until, rule.until::timestamp);
    wksti = dow(wkst);

    CASE rule.freq
    WHEN 'WEEKLY' THEN
        rule.interval = COALESCE(rule.interval, 1);
        rule.byday = COALESCE(rule.byday, array[
            (NULL,rrule_weekday(extract(dow from dtstart)::integer))::rrule_weekdaynum]);
        rule.byhour = COALESCE(rule.byhour, array[extract(hour from dtstart)]);
        rule.byminute = COALESCE(rule.byminute, array[extract(minute from dtstart)]);
        rule.bysecond = COALESCE(rule.bysecond, array[extract(second from dtstart)]);

        RETURN QUERY
            SELECT ts FROM (
                SELECT
                    week +
                        (dow(day) - wksti)*INTERVAL '1d' +
                        hour*INTERVAL '1h' +
                        minute*INTERVAL '1m' +
                        second*INTERVAL '1s' ts
                FROM
                    generate_series(
                        date_trunc('week', dtstart),
                        date_trunc('week', until),
                        INTERVAL '1w'*rule.interval) week,
                    (SELECT day FROM unnest(rule.byday)) day(day),
                    unnest(rule.byhour) hour,
                    unnest(rule.byminute) minute,
                    unnest(rule.bysecond) second
                ORDER BY 1
            ) ts(ts)
            WHERE
                (rule.bymonth IS NULL OR extract(month from ts) = ANY(rule.bymonth)) AND
                ts <@ tsrange(dtstart, until)
            LIMIT rule.count;

    ELSE
        RAISE EXCEPTION 'Expansion of % rrules is not implemented.', rule.freq;
    END CASE;
END;
$$;

-- -------------------------
-- Convenience Functions
-- -------------------------
CREATE FUNCTION get_occurrences(raw text, dtstart date, until date)
    RETURNS date[]
    LANGUAGE SQL
    IMMUTABLE
AS $$
SELECT array_agg(occurrence) FROM rrule_expand(rrule(raw), dtstart, until);
$$;

CREATE FUNCTION get_occurrences(raw text, dtstart timestamp, until timestamp)
    RETURNS timestamp[]
    LANGUAGE SQL
    IMMUTABLE
AS $$
SELECT array_agg(occurrence) FROM rrule_expand(rrule(raw), dtstart, until);
$$;

-- ==========================================
-- END SCRIPT
-- ==========================================
