-- ══════════════════════════════════════════════════════════════════════════
--  TimetableOS — Supabase PostgreSQL Schema
--  Run this ONCE in the Supabase SQL Editor (https://app.supabase.com)
--  Project → SQL Editor → Paste → Run
-- ══════════════════════════════════════════════════════════════════════════

-- Drop existing tables if re-running
drop table if exists attendance_records cascade;
drop table if exists timetable_entries cascade;
drop table if exists special_slots cascade;
drop table if exists subjects cascade;
drop table if exists students cascade;
drop table if exists faculty cascade;
drop table if exists app_settings cascade;

-- ── FACULTY ──────────────────────────────────────────────────────────────────
create table faculty (
  id            text primary key,
  "employeeId"  text unique not null default '',
  name          text,
  email         text,
  "passwordHash" text,
  "isAdmin"     integer default 0
);

-- ── STUDENTS ─────────────────────────────────────────────────────────────────
create table students (
  id            text primary key,
  "rollNumber"  text unique,
  name          text,
  section       text,
  year          integer,
  batch         integer,
  "passwordHash" text not null default ''
);

-- ── SUBJECTS ─────────────────────────────────────────────────────────────────
create table subjects (
  id                      text primary key,
  name                    text,
  code                    text,
  section                 text,
  year                    integer,
  "facultyId"             text references faculty(id),
  type                    text,
  "periodsPerWeek"        integer,
  "isIncharge"            integer,
  batch                   integer,
  "labDividedIntoBatches" integer,
  preference              text,
  "batch2FacultyId"       text
);

-- ── TIMETABLE_ENTRIES ────────────────────────────────────────────────────────
create table timetable_entries (
  id              text primary key,
  section         text,
  year            integer,
  "dayOfWeek"     integer,
  "periodNumber"  integer,
  "subjectId"     text references subjects(id),
  "facultyId"     text references faculty(id),
  "isLab"         integer default 0,
  batch           integer default 0,
  "specialLabel"  text
);

-- ── ATTENDANCE_RECORDS ───────────────────────────────────────────────────────
create table attendance_records (
  id                  text primary key,
  "studentId"         text references students(id),
  "subjectId"         text references subjects(id),
  "facultyId"         text references faculty(id),
  section             text,
  "periodNumber"      integer,
  date                text,
  "isPresent"         integer,
  "timetableEntryId"  text,
  batch               integer not null default 0,
  "dayOfWeek"         integer not null default 1
);

-- ── SPECIAL_SLOTS ────────────────────────────────────────────────────────────
create table special_slots (
  id              text primary key,
  section         text,
  year            integer,
  "dayOfWeek"     integer,
  "periodNumber"  integer,
  label           text
);

-- ── APP_SETTINGS ─────────────────────────────────────────────────────────────
create table app_settings (
  key   text primary key,
  value text
);

-- ── INDICES ───────────────────────────────────────────────────────────────────
create index idx_students_sec_yr  on students(section, year);
create index idx_subjects_sec_yr  on subjects(section, year);
create index idx_tt_sec_yr        on timetable_entries(section, year);
create index idx_tt_faculty       on timetable_entries("facultyId");
create index idx_att_student      on attendance_records("studentId");
create index idx_att_entry_date   on attendance_records("timetableEntryId", date);
create index idx_att_date         on attendance_records(date);

-- ── ROW LEVEL SECURITY (disable for simplicity — use anon key only internally)
alter table faculty           enable row level security;
alter table students          enable row level security;
alter table subjects          enable row level security;
alter table timetable_entries enable row level security;
alter table attendance_records enable row level security;
alter table special_slots     enable row level security;

-- Allow all operations from the anon key (app controls access via login logic)
create policy "allow_all_faculty"            on faculty            for all using (true) with check (true);
create policy "allow_all_students"           on students           for all using (true) with check (true);
create policy "allow_all_subjects"           on subjects           for all using (true) with check (true);
create policy "allow_all_timetable_entries"  on timetable_entries  for all using (true) with check (true);
create policy "allow_all_attendance_records" on attendance_records  for all using (true) with check (true);
create policy "allow_all_special_slots"      on special_slots      for all using (true) with check (true);
