-- MG Physio Center: Supabase schema + Row Level Security
-- Run this in Supabase Dashboard > SQL Editor.
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  phone text,
  role text not null default 'patient' check (role in ('owner','doctor','patient')),
  created_at timestamptz not null default now()
);

create table if not exists public.appointments (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.profiles(id) on delete cascade,
  doctor_id uuid references public.profiles(id) on delete set null,
  service text not null,
  preferred_date date,
  preferred_time text,
  therapist_preference text,
  notes text,
  status text not null default 'pending' check (status in ('pending','confirmed','rejected','completed')),
  created_at timestamptz not null default now()
);

create table if not exists public.session_notes (
  id uuid primary key default gen_random_uuid(),
  appointment_id uuid not null references public.appointments(id) on delete cascade,
  patient_id uuid not null references public.profiles(id) on delete cascade,
  doctor_id uuid not null references public.profiles(id) on delete cascade,
  session_number integer not null check (session_number > 0),
  notes text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.profiles(id) on delete cascade,
  rating integer not null check (rating between 1 and 5),
  comment text,
  status text not null default 'pending' check (status in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public
as $$
begin
  insert into public.profiles(id, full_name, phone, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name',''), coalesce(new.raw_user_meta_data->>'phone',''), 'patient')
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

create or replace function public.current_profile_role()
returns text language sql stable security definer set search_path = public
as $$ select role from public.profiles where id = auth.uid(); $$;
create or replace function public.is_owner()
returns boolean language sql stable security definer set search_path = public
as $$ select coalesce(public.current_profile_role() = 'owner', false); $$;

alter table public.profiles enable row level security;
alter table public.appointments enable row level security;
alter table public.session_notes enable row level security;
alter table public.reviews enable row level security;

-- Profiles: users see their own record; owner sees all; doctor sees assigned patients.
drop policy if exists profiles_select_scoped on public.profiles;
create policy profiles_select_scoped on public.profiles for select to authenticated
using (id = auth.uid() or public.is_owner() or exists (
  select 1 from public.appointments a
  where a.patient_id = profiles.id and a.doctor_id = auth.uid()
));
drop policy if exists profiles_update_self_or_owner on public.profiles;
create policy profiles_update_self_or_owner on public.profiles for update to authenticated
using (id = auth.uid() or public.is_owner())
with check (public.is_owner() or (id = auth.uid() and role = public.current_profile_role()));

-- Appointments: patient owns own; assigned doctor reads; owner manages all.
drop policy if exists appointments_select_scoped on public.appointments;
create policy appointments_select_scoped on public.appointments for select to authenticated
using (patient_id = auth.uid() or doctor_id = auth.uid() or public.is_owner());
drop policy if exists appointments_insert_patient on public.appointments;
create policy appointments_insert_patient on public.appointments for insert to authenticated
with check (patient_id = auth.uid() and doctor_id is null and status = 'pending');
drop policy if exists appointments_update_owner on public.appointments;
create policy appointments_update_owner on public.appointments for update to authenticated
using (public.is_owner()) with check (public.is_owner());

-- Session notes: assigned doctor writes; owner and assigned doctor read.
drop policy if exists session_notes_select_scoped on public.session_notes;
create policy session_notes_select_scoped on public.session_notes for select to authenticated
using (public.is_owner() or doctor_id = auth.uid() or patient_id = auth.uid());
drop policy if exists session_notes_insert_assigned_doctor on public.session_notes;
create policy session_notes_insert_assigned_doctor on public.session_notes for insert to authenticated
with check (
  doctor_id = auth.uid() and exists (
    select 1 from public.appointments a
    where a.id = appointment_id and a.doctor_id = auth.uid() and a.patient_id = session_notes.patient_id
  )
);

-- Reviews: patient submits and sees own; owner reviews all.
drop policy if exists reviews_select_scoped on public.reviews;
create policy reviews_select_scoped on public.reviews for select to authenticated
using (patient_id = auth.uid() or public.is_owner());
drop policy if exists reviews_insert_patient on public.reviews;
create policy reviews_insert_patient on public.reviews for insert to authenticated
with check (patient_id = auth.uid() and status = 'pending');
drop policy if exists reviews_update_owner on public.reviews;
create policy reviews_update_owner on public.reviews for update to authenticated
using (public.is_owner()) with check (public.is_owner());

-- Restrict browser privileges to the operations used by this app.
grant usage on schema public to authenticated;
grant select on public.profiles, public.appointments, public.session_notes, public.reviews to authenticated;
grant insert on public.appointments, public.session_notes, public.reviews to authenticated;
grant update on public.appointments, public.reviews to authenticated;
grant update (full_name, phone, role) on public.profiles to authenticated;

-- IMPORTANT: after the OWNER has signed up in the website, replace the email below and run this:
-- update public.profiles set role = 'owner'
-- where id = (select id from auth.users where email = 'OWNER_EMAIL_HERE');
-- Create a doctor account through Supabase Authentication, then run:
-- update public.profiles set role = 'doctor'
-- where id = (select id from auth.users where email = 'DOCTOR_EMAIL_HERE');

-- Enable Realtime events for appointments (ignore duplicate membership errors if already added).
do $$ begin
  alter publication supabase_realtime add table public.appointments;
exception when duplicate_object then null;
when others then null;
end $$;
