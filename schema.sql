-- SMART ASSESSMENT CBT Tahap 2
-- Jalankan seluruh SQL ini di Supabase SQL Editor.
create extension if not exists pgcrypto;

do $$ begin
  create type public.app_role as enum ('admin','teacher','student');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.question_kind as enum ('mcq','essay');
exception when duplicate_object then null; end $$;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text not null default '',
  role public.app_role not null default 'student',
  class_name text,
  created_at timestamptz not null default now()
);
create table if not exists public.exams (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  subject text not null default '',
  class_name text not null default '',
  duration_minutes int not null default 60 check(duration_minutes between 1 and 600),
  instructions text not null default '',
  start_at timestamptz,
  end_at timestamptz,
  token text not null unique,
  status text not null default 'draft' check(status in ('draft','published','closed')),
  created_by uuid not null references public.profiles(id),
  created_at timestamptz not null default now()
);
create table if not exists public.questions (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.exams(id) on delete cascade,
  position int not null,
  question_text text not null,
  question_type public.question_kind not null default 'mcq',
  options jsonb not null default '{}'::jsonb,
  answer_key text,
  weight numeric(8,2) not null default 1 check(weight > 0),
  created_at timestamptz not null default now(),
  unique(exam_id,position)
);
create table if not exists public.attempts (
  id uuid primary key default gen_random_uuid(),
  exam_id uuid not null references public.exams(id) on delete cascade,
  student_id uuid not null references public.profiles(id),
  status text not null default 'in_progress' check(status in ('in_progress','submitted','graded')),
  score numeric(6,2),
  started_at timestamptz not null default now(),
  submitted_at timestamptz,
  unique(exam_id,student_id)
);
create table if not exists public.answers (
  id uuid primary key default gen_random_uuid(),
  attempt_id uuid not null references public.attempts(id) on delete cascade,
  question_id uuid not null references public.questions(id) on delete cascade,
  answer_text text not null default '',
  is_correct boolean,
  awarded_score numeric(8,2),
  updated_at timestamptz not null default now(),
  unique(attempt_id,question_id)
);

create or replace function public.my_role() returns public.app_role
language sql stable security definer set search_path=public
as $$ select role from public.profiles where id=auth.uid() $$;

alter table public.profiles enable row level security;
alter table public.exams enable row level security;
alter table public.questions enable row level security;
alter table public.attempts enable row level security;
alter table public.answers enable row level security;

drop policy if exists "profile self read" on public.profiles;
create policy "profile self read" on public.profiles for select to authenticated
using (id=auth.uid() or public.my_role()='admin' or public.my_role()='teacher');
-- Perubahan role/kelas dilakukan administrator melalui SQL Editor, bukan dari browser siswa.
drop policy if exists "profile self update" on public.profiles;

drop policy if exists "staff manage exams" on public.exams;
create policy "staff manage exams" on public.exams for all to authenticated
using (public.my_role() in ('admin','teacher') and (created_by=auth.uid() or public.my_role()='admin'))
with check (public.my_role() in ('admin','teacher') and created_by=auth.uid());
-- Siswa tidak diberi SELECT langsung ke tabel ujian karena kolom token harus tetap rahasia.
-- Informasi ujian dan soal hanya dikirim melalui RPC start_exam setelah token divalidasi.

drop policy if exists "staff manage questions" on public.questions;
create policy "staff manage questions" on public.questions for all to authenticated
using (public.my_role() in ('admin','teacher') and exists(select 1 from public.exams e where e.id=exam_id and (e.created_by=auth.uid() or public.my_role()='admin')))
with check (public.my_role() in ('admin','teacher') and exists(select 1 from public.exams e where e.id=exam_id and (e.created_by=auth.uid() or public.my_role()='admin')));
-- Siswa tidak diberi SELECT langsung ke tabel questions agar answer_key tidak bocor.
-- RPC start_exam hanya mengembalikan teks soal dan opsi, tanpa kunci jawaban.

drop policy if exists "student own attempts read" on public.attempts;
create policy "student own attempts read" on public.attempts for select to authenticated
using(student_id=auth.uid() or public.my_role() in ('admin','teacher'));
drop policy if exists "staff attempts read" on public.attempts;
create policy "staff attempts read" on public.attempts for select to authenticated
using(public.my_role() in ('admin','teacher'));
drop policy if exists "student own answers read" on public.answers;
create policy "student own answers read" on public.answers for select to authenticated
using(exists(select 1 from public.attempts a where a.id=attempt_id and a.student_id=auth.uid()) or public.my_role() in ('admin','teacher'));

-- Token tidak dibaca siswa melalui tabel. Validasi dilakukan melalui RPC.
create or replace function public.start_exam(p_token text)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare e public.exams%rowtype; a public.attempts%rowtype; qs jsonb;
begin
 if auth.uid() is null then raise exception 'Silakan masuk terlebih dahulu.'; end if;
 if public.my_role() <> 'student' then raise exception 'Akun ini bukan akun siswa.'; end if;
 select * into e from public.exams where token=upper(trim(p_token)) and status='published';
 if not found then raise exception 'Token tidak valid atau ujian belum diterbitkan.'; end if;
 if e.start_at is not null and now()<e.start_at then raise exception 'Ujian belum dimulai.'; end if;
 if e.end_at is not null and now()>e.end_at then raise exception 'Waktu ujian telah berakhir.'; end if;
 if e.class_name<>'' and exists(select 1 from public.profiles p where p.id=auth.uid() and coalesce(p.class_name,'')<>e.class_name) then
   raise exception 'Ujian ini bukan untuk kelas akun Anda.';
 end if;
 insert into public.attempts(exam_id,student_id) values(e.id,auth.uid())
 on conflict(exam_id,student_id) do update set exam_id=excluded.exam_id
 returning * into a;
 select coalesce(jsonb_agg(jsonb_build_object('id',q.id,'position',q.position,'question_text',q.question_text,'question_type',q.question_type,'options',q.options,'weight',q.weight) order by q.position),'[]'::jsonb)
 into qs from public.questions q where q.exam_id=e.id;
 return jsonb_build_object('attempt_id',a.id,'title',e.title,'instructions',e.instructions,'duration_minutes',e.duration_minutes,'questions',qs);
end $$;

create or replace function public.save_answer(p_attempt_id uuid,p_question_id uuid,p_answer text)
returns boolean language plpgsql security definer set search_path=public
as $$
begin
 if not exists(select 1 from public.attempts where id=p_attempt_id and student_id=auth.uid() and status='in_progress') then
   raise exception 'Percobaan ujian tidak aktif.';
 end if;
 if not exists(select 1 from public.questions q join public.attempts a on a.exam_id=q.exam_id where q.id=p_question_id and a.id=p_attempt_id) then
   raise exception 'Soal tidak sesuai dengan ujian.';
 end if;
 insert into public.answers(attempt_id,question_id,answer_text,updated_at)
 values(p_attempt_id,p_question_id,coalesce(p_answer,''),now())
 on conflict(attempt_id,question_id) do update set answer_text=excluded.answer_text,updated_at=now();
 return true;
end $$;

create or replace function public.submit_exam(p_attempt_id uuid)
returns jsonb language plpgsql security definer set search_path=public
as $$
declare total numeric; earned numeric;
begin
 if not exists(select 1 from public.attempts where id=p_attempt_id and student_id=auth.uid() and status='in_progress') then
   raise exception 'Percobaan ujian tidak aktif atau sudah dikirim.';
 end if;
 update public.answers an set
   is_correct=(upper(trim(an.answer_text))=upper(trim(q.answer_key))),
   awarded_score=case when q.question_type='mcq' and upper(trim(an.answer_text))=upper(trim(q.answer_key)) then q.weight else 0 end
 from public.questions q where an.question_id=q.id and an.attempt_id=p_attempt_id;
 select coalesce(sum(q.weight) filter(where q.question_type='mcq'),0),
        coalesce(sum(case when q.question_type='mcq' and upper(trim(coalesce(an.answer_text,'')))=upper(trim(coalesce(q.answer_key,''))) then q.weight else 0 end),0)
 into total,earned from public.questions q left join public.answers an on an.question_id=q.id and an.attempt_id=p_attempt_id
 where q.exam_id=(select exam_id from public.attempts where id=p_attempt_id);
 update public.attempts set status='submitted',submitted_at=now(),
   score=case when total>0 then round(earned/total*100,2) else null end
 where id=p_attempt_id and student_id=auth.uid();
 return jsonb_build_object('status','submitted','score_pg',case when total>0 then round(earned/total*100,2) else null end);
end $$;

grant execute on function public.start_exam(text) to authenticated;
grant execute on function public.save_answer(uuid,uuid,text) to authenticated;
grant execute on function public.submit_exam(uuid) to authenticated;
grant select on public.profiles to authenticated;
grant insert,update,delete on public.exams to authenticated;
grant select on public.exams to authenticated;
grant select,insert,update,delete on public.questions to authenticated;
grant select on public.attempts,public.answers to authenticated;

-- Buat profil otomatis sebagai siswa saat akun baru mendaftar.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path=public
as $$
begin
 insert into public.profiles(id,full_name,role)
 values(new.id,coalesce(new.raw_user_meta_data->>'full_name','Siswa'), 'student')
 on conflict(id) do nothing;
 return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
for each row execute procedure public.handle_new_user();

-- Admin awal: setelah mendaftar, ubah role akun administrator melalui SQL Editor:
-- update public.profiles set role='admin', full_name='Administrator Sekolah' where id='UUID-AKUN-ADMIN';
-- Tetapkan kelas siswa:
-- update public.profiles set class_name='VIII A' where id='UUID-SISWA';
