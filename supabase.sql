-- Bdayverse Supabase setup
-- Run this entire script in Supabase Dashboard > SQL Editor.

create table if not exists public.surprises (
  id text primary key,
  name text not null,
  jokes jsonb not null default '[]'::jsonb,
  lines jsonb not null default '[]'::jsonb,
  sign text not null default '',
  photos jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default now()
);

alter table public.surprises enable row level security;

grant usage on schema public to anon, authenticated;
grant insert on table public.surprises to anon, authenticated;

drop policy if exists "Public can create birthday surprises" on public.surprises;
create policy "Public can create birthday surprises"
on public.surprises for insert
to anon, authenticated
with check (
  id ~ '^b[a-f0-9]{32}$'
  and length(name) <= 24
  and jsonb_typeof(jokes) = 'array'
  and jsonb_typeof(lines) = 'array'
  and jsonb_typeof(photos) = 'array'
);

-- Do not add a public SELECT policy. The function below only returns the
-- specific surprise requested by its unguessable share ID.
create or replace function public.get_surprise(surprise_id text)
returns jsonb
language sql
security definer
set search_path = public
as $$
  select jsonb_build_object(
    'name', name,
    'jokes', jokes,
    'lines', lines,
    'sign', sign,
    'photos', photos
  )
  from public.surprises
  where id = surprise_id
  limit 1;
$$;

revoke all on function public.get_surprise(text) from public;
grant execute on function public.get_surprise(text) to anon, authenticated;

-- Refresh PostgREST so the new table and RPC are immediately discoverable.
notify pgrst, 'reload schema';

-- Public bucket lets recipients load photos from a shared birthday link.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('birthday-photos', 'birthday-photos', true, 2097152, array['image/jpeg'])
on conflict (id) do update set public = true, file_size_limit = 2097152, allowed_mime_types = array['image/jpeg'];

drop policy if exists "Visitors can upload birthday photos" on storage.objects;
create policy "Visitors can upload birthday photos"
on storage.objects for insert
to anon, authenticated
with check (
  bucket_id = 'birthday-photos'
  and name ~ '^b[a-f0-9]{32}/[0-7]\.jpg$'
);

drop policy if exists "Anyone can view birthday photos" on storage.objects;
create policy "Anyone can view birthday photos"
on storage.objects for select
to anon, authenticated
using (bucket_id = 'birthday-photos');