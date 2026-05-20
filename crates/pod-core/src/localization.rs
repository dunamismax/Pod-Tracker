use chrono::{Datelike, LocalResult, NaiveDate, NaiveTime, TimeZone, Timelike, Utc};
use chrono_tz::Tz;
use time::OffsetDateTime;

pub const DEFAULT_LOCALE: &str = "en-US";
pub const DEFAULT_TIMEZONE: &str = "UTC";
pub const DEFAULT_DATE_TIME_FORMAT: &str = "locale_default";

const SUPPORTED_LOCALES: &[(&str, &str)] = &[("en-US", "English (United States)")];

const SUPPORTED_TIMEZONES: &[(&str, &str)] = &[
    ("UTC", "UTC"),
    ("America/New_York", "Eastern Time"),
    ("America/Chicago", "Central Time"),
    ("America/Denver", "Mountain Time"),
    ("America/Phoenix", "Arizona Time"),
    ("America/Los_Angeles", "Pacific Time"),
    ("Europe/London", "London"),
    ("Europe/Paris", "Central Europe"),
];

const SUPPORTED_DATE_TIME_FORMATS: &[(&str, &str)] = &[
    ("locale_default", "Locale default"),
    ("iso_24h", "ISO-like 24-hour"),
];

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct UserPreferences {
    pub locale: String,
    pub timezone: String,
    pub date_time_format: String,
}

impl Default for UserPreferences {
    fn default() -> Self {
        Self {
            locale: DEFAULT_LOCALE.to_owned(),
            timezone: DEFAULT_TIMEZONE.to_owned(),
            date_time_format: DEFAULT_DATE_TIME_FORMAT.to_owned(),
        }
    }
}

impl UserPreferences {
    pub fn validate(
        locale: &str,
        timezone: &str,
        date_time_format: &str,
    ) -> Result<Self, PreferenceError> {
        if !is_supported_locale(locale) {
            return Err(PreferenceError::UnsupportedLocale);
        }
        if !is_supported_timezone(timezone) || timezone.parse::<Tz>().is_err() {
            return Err(PreferenceError::UnsupportedTimezone);
        }
        if !is_supported_date_time_format(date_time_format) {
            return Err(PreferenceError::UnsupportedDateTimeFormat);
        }

        Ok(Self {
            locale: locale.to_owned(),
            timezone: timezone.to_owned(),
            date_time_format: date_time_format.to_owned(),
        })
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PreferenceError {
    UnsupportedLocale,
    UnsupportedTimezone,
    UnsupportedDateTimeFormat,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum DateTimeInputError {
    InvalidShape,
    UnsupportedTimezone,
    NonexistentLocalTime,
}

pub fn supported_locales() -> &'static [(&'static str, &'static str)] {
    SUPPORTED_LOCALES
}

pub fn supported_timezones() -> &'static [(&'static str, &'static str)] {
    SUPPORTED_TIMEZONES
}

pub fn supported_date_time_formats() -> &'static [(&'static str, &'static str)] {
    SUPPORTED_DATE_TIME_FORMATS
}

pub fn is_supported_locale(value: &str) -> bool {
    SUPPORTED_LOCALES.iter().any(|(code, _)| *code == value)
}

pub fn is_supported_timezone(value: &str) -> bool {
    SUPPORTED_TIMEZONES.iter().any(|(code, _)| *code == value)
}

pub fn is_supported_date_time_format(value: &str) -> bool {
    SUPPORTED_DATE_TIME_FORMATS
        .iter()
        .any(|(code, _)| *code == value)
}

pub fn parse_datetime_local_in_timezone(
    value: &str,
    timezone: &str,
) -> Result<OffsetDateTime, DateTimeInputError> {
    let tz = timezone
        .parse::<Tz>()
        .map_err(|_| DateTimeInputError::UnsupportedTimezone)?;
    let (date, time) = value
        .trim()
        .split_once('T')
        .ok_or(DateTimeInputError::InvalidShape)?;
    let mut date_parts = date.split('-');
    let year = date_parts
        .next()
        .and_then(|part| part.parse::<i32>().ok())
        .ok_or(DateTimeInputError::InvalidShape)?;
    let month = date_parts
        .next()
        .and_then(|part| part.parse::<u32>().ok())
        .ok_or(DateTimeInputError::InvalidShape)?;
    let day = date_parts
        .next()
        .and_then(|part| part.parse::<u32>().ok())
        .ok_or(DateTimeInputError::InvalidShape)?;
    if date_parts.next().is_some() {
        return Err(DateTimeInputError::InvalidShape);
    }

    let mut time_parts = time.split(':');
    let hour = time_parts
        .next()
        .and_then(|part| part.parse::<u32>().ok())
        .ok_or(DateTimeInputError::InvalidShape)?;
    let minute = time_parts
        .next()
        .and_then(|part| part.parse::<u32>().ok())
        .ok_or(DateTimeInputError::InvalidShape)?;
    if time_parts.next().is_some() {
        return Err(DateTimeInputError::InvalidShape);
    }

    let date = NaiveDate::from_ymd_opt(year, month, day).ok_or(DateTimeInputError::InvalidShape)?;
    let time = NaiveTime::from_hms_opt(hour, minute, 0).ok_or(DateTimeInputError::InvalidShape)?;
    let local = date.and_time(time);
    let zoned = match tz.from_local_datetime(&local) {
        LocalResult::Single(value) => value,
        LocalResult::Ambiguous(earlier, _) => earlier,
        LocalResult::None => return Err(DateTimeInputError::NonexistentLocalTime),
    };

    OffsetDateTime::from_unix_timestamp(zoned.timestamp())
        .and_then(|value| value.replace_nanosecond(zoned.timestamp_subsec_nanos()))
        .map_err(|_| DateTimeInputError::InvalidShape)
}

pub fn datetime_local_value(value: OffsetDateTime, preferences: &UserPreferences) -> String {
    let local = to_local_datetime(value, &preferences.timezone).unwrap_or_else(|| {
        to_local_datetime(value, DEFAULT_TIMEZONE).expect("UTC timezone is valid")
    });
    format!(
        "{:04}-{:02}-{:02}T{:02}:{:02}",
        local.year(),
        local.month(),
        local.day(),
        local.hour(),
        local.minute()
    )
}

pub fn display_datetime(value: OffsetDateTime, preferences: &UserPreferences) -> String {
    let local = to_local_datetime(value, &preferences.timezone).unwrap_or_else(|| {
        to_local_datetime(value, DEFAULT_TIMEZONE).expect("UTC timezone is valid")
    });
    match preferences.date_time_format.as_str() {
        "iso_24h" => local.format("%Y-%m-%d %H:%M %Z").to_string(),
        _ => local.format("%b %-d, %Y %-I:%M %p %Z").to_string(),
    }
}

fn to_local_datetime(
    value: OffsetDateTime,
    timezone: &str,
) -> Option<chrono::DateTime<chrono_tz::Tz>> {
    let tz = timezone.parse::<Tz>().ok()?;
    let utc = chrono::DateTime::<Utc>::from_timestamp(value.unix_timestamp(), value.nanosecond())?;
    Some(utc.with_timezone(&tz))
}

#[cfg(test)]
mod tests {
    use super::{
        UserPreferences, datetime_local_value, display_datetime, parse_datetime_local_in_timezone,
    };
    use time::OffsetDateTime;

    #[test]
    fn parses_datetime_local_in_named_timezone() {
        let utc = parse_datetime_local_in_timezone("2026-06-01T19:30", "America/New_York")
            .expect("valid local datetime");

        assert_eq!(utc.unix_timestamp(), 1_780_356_600);
    }

    #[test]
    fn rejects_nonexistent_dst_local_time() {
        assert!(parse_datetime_local_in_timezone("2026-03-08T02:30", "America/New_York").is_err());
    }

    #[test]
    fn formats_datetime_with_user_preference() {
        let preferences =
            UserPreferences::validate("en-US", "America/New_York", "iso_24h").expect("prefs");
        let value = OffsetDateTime::from_unix_timestamp(1_780_356_600).expect("timestamp");

        assert_eq!(
            datetime_local_value(value, &preferences),
            "2026-06-01T19:30"
        );
        assert_eq!(
            display_datetime(value, &preferences),
            "2026-06-01 19:30 EDT"
        );
    }
}
