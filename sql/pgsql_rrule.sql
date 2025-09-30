-- Enum types
CREATE TYPE rrule_freq AS ENUM ('SECONDLY', 'MINUTELY', 'HOURLY', 'DAILY', 'WEEKLY', 'MONTHLY', 'YEARLY');
CREATE TYPE rrule_weekday AS ENUM ('SU', 'MO', 'TU', 'WE', 'TH', 'FR', 'SA');

-- Composite types
CREATE TYPE rrule_weekdaynum AS (num int, weekday rrule_weekday);
CREATE TYPE rrule AS (
    freq rrule_freq,
    interval int,
    wkst rrule_weekday,
    count int,
    until timestamptz,
    bysetpos int[],
    bymonth int[],
    byweekno int[],
    byyearday int[],
    bymonthday int[],
    byday rrule_weekdaynum[],
    byhour int[],
    byminute int[],
    bysecond int[]
);

-- Weekday mapping
CREATE FUNCTION rrule_weekday_to_int(day rrule_weekday) RETURNS int AS $$
BEGIN
    CASE day
        WHEN 'SU' THEN RETURN 0;
        WHEN 'MO' THEN RETURN 1;
        WHEN 'TU' THEN RETURN 2;
        WHEN 'WE' THEN RETURN 3;
        WHEN 'TH' THEN RETURN 4;
        WHEN 'FR' THEN RETURN 5;
        WHEN 'SA' THEN RETURN 6;
    END CASE;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Parse weekdaynum
CREATE FUNCTION rrule_weekdaynum(raw text) RETURNS rrule_weekdaynum AS $$
DECLARE
    result rrule_weekdaynum;
    num_part text;
    weekday_part text;
BEGIN
    num_part := regexp_replace(raw, '[^0-9-]', '', 'g');
    weekday_part := regexp_replace(raw, '[0-9-]', '', 'g');
    result.num := CASE WHEN num_part = '' THEN NULL ELSE num_part::int END;
    result.weekday := weekday_part::rrule_weekday;
    RETURN result;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Parse RRULE string
CREATE FUNCTION rrule(raw text) RETURNS rrule AS $$
DECLARE
    parsed rrule;
    part text;
    key text;
    value text;
    values text[];
    ivalues int[];
BEGIN
    SELECT * INTO parsed FROM rrule;

    FOREACH part IN ARRAY regexp_split_to_array(raw, ';') LOOP
        key := upper(split_part(part, '=', 1));
        value := split_part(part, '=', 2);

        CASE key
            WHEN 'FREQ' THEN parsed.freq := upper(value)::rrule_freq;
            WHEN 'INTERVAL' THEN parsed.interval := value::int;
            WHEN 'COUNT' THEN parsed.count := value::int;
            WHEN 'UNTIL' THEN parsed.until := value::timestamptz;
            WHEN 'WKST' THEN parsed.wkst := upper(value)::rrule_weekday;
            WHEN 'BYSETPOS' THEN
                ivalues := ARRAY(SELECT unnest(regexp_split_to_array(value, ','))::int);
                parsed.bysetpos := ivalues;
            WHEN 'BYMONTH' THEN
                ivalues := ARRAY(SELECT unnest(regexp_split_to_array(value, ','))::int);
                parsed.bymonth := ivalues;
            WHEN 'BYWEEKNO' THEN
                ivalues := ARRAY(SELECT unnest(regexp_split_to_array(value, ','))::int);
                parsed.byweekno := ivalues;
            WHEN 'BYYEARDAY' THEN
                ivalues := ARRAY(SELECT unnest(regexp_split_to_array(value, ','))::int);
                parsed.byyearday := ivalues;
            WHEN 'BYMONTHDAY' THEN
                ivalues := ARRAY(SELECT unnest(regexp_split_to_array(value, ','))::int);
                parsed.bymonthday := ivalues;
            WHEN 'BYDAY' THEN
                values := regexp_split_to_array(value, ',');
                parsed.byday := ARRAY(SELECT rrule_weekdaynum(v) FROM unnest(values) v);
            WHEN 'BYHOUR' THEN
                ivalues := ARRAY(SELECT unnest(regexp_split_to_array(value, ','))::int);
                parsed.byhour := ivalues;
            WHEN 'BYMINUTE' THEN
                ivalues := ARRAY(SELECT unnest(regexp_split_to_array(value, ','))::int);
                parsed.byminute := ivalues;
            WHEN 'BYSECOND' THEN
                ivalues := ARRAY(SELECT unnest(regexp_split_to_array(value, ','))::int);
                parsed.bysecond := ivalues;
            ELSE
                RAISE EXCEPTION 'Unknown RRULE part: %', key;
        END CASE;
    END LOOP;

    -- Defaults
    parsed.interval := COALESCE(parsed.interval, 1);

    RETURN parsed;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

-- Expand RRULE
CREATE FUNCTION rrule_expand(rule rrule, dtstart timestamptz, until timestamptz)
RETURNS SETOF timestamptz AS $$
DECLARE
    current timestamptz := dtstart;
    count int := 0;
BEGIN
    IF rule.freq = 'WEEKLY' THEN
        LOOP
            EXIT WHEN rule.count IS NOT NULL AND count >= rule.count;
            EXIT WHEN rule.until IS NOT NULL AND current > rule.until;
            EXIT WHEN until IS NOT NULL AND current > until;

            -- Defaults corrected
            rule.byhour := COALESCE(rule.byhour, array[extract(hour from dtstart)]);
            rule.byminute := COALESCE(rule.byminute, array[extract(minute from dtstart)]);
            rule.bysecond := COALESCE(rule.bysecond, array[extract(second from dtstart)]);

            FOREACH h IN ARRAY rule.byhour LOOP
                FOREACH m IN ARRAY rule.byminute LOOP
                    FOREACH s IN ARRAY rule.bysecond LOOP
                        RETURN NEXT date_trunc('second', current) + make_interval(hours => h, mins => m, secs => s);
                        count := count + 1;
                    END LOOP;
                END LOOP;
            END LOOP;

            current := current + make_interval(weeks => rule.interval);
        END LOOP;
    ELSE
        RAISE EXCEPTION 'RRULE expansion for % not implemented yet', rule.freq;
    END IF;
END;
$$ LANGUAGE plpgsql;
