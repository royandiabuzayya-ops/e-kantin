-- Catatan Tani — Skema Database Komunitas (Supabase)
-- Jalankan seluruh isi file ini di: Supabase Dashboard > SQL Editor > New query > Run
--
-- CATATAN: versi ini menggantikan draft awal (kolom user_id/follower_id/following_id
-- sekarang merujuk ke public.profiles, bukan langsung ke auth.users, supaya aplikasi
-- bisa menampilkan nama pengguna di setiap kasus/komentar). Aman dijalankan ulang —
-- baris DROP di bawah akan membersihkan versi lama dulu jika sempat dijalankan.

drop table if exists public.follows cascade;
drop table if exists public.comments cascade;
drop table if exists public.cases cascade;
drop table if exists public.profiles cascade;

-- 1) PROFIL PENGGUNA
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null,
  created_at timestamptz not null default now()
);
alter table public.profiles enable row level security;
create policy "profiles_select_all" on public.profiles for select using (true);
create policy "profiles_insert_own" on public.profiles for insert with check (auth.uid() = id);
create policy "profiles_update_own" on public.profiles for update using (auth.uid() = id);

-- 2) KASUS: masalah + solusi yang dibagikan
create table public.cases (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  judul text not null,
  kategori text not null default 'lainnya',
  tanaman text,
  deskripsi_masalah text not null,
  solusi text,
  status text not null default 'terbuka',
  foto text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.cases enable row level security;
create policy "cases_select_authenticated" on public.cases for select using (auth.role() = 'authenticated');
create policy "cases_insert_own" on public.cases for insert with check (auth.uid() = user_id);
create policy "cases_update_own" on public.cases for update using (auth.uid() = user_id);
create policy "cases_delete_own" on public.cases for delete using (auth.uid() = user_id);
create index cases_created_at_idx on public.cases (created_at desc);
create index cases_kategori_idx on public.cases (kategori);

-- 3) KOMENTAR
create table public.comments (
  id uuid primary key default gen_random_uuid(),
  case_id uuid not null references public.cases(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  isi text not null,
  created_at timestamptz not null default now()
);
alter table public.comments enable row level security;
create policy "comments_select_authenticated" on public.comments for select using (auth.role() = 'authenticated');
create policy "comments_insert_own" on public.comments for insert with check (auth.uid() = user_id);
create policy "comments_delete_own" on public.comments for delete using (auth.uid() = user_id);
create index comments_case_id_idx on public.comments (case_id);

-- 4) IKUTI PENGGUNA
create table public.follows (
  follower_id uuid not null references public.profiles(id) on delete cascade,
  following_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, following_id),
  constraint no_self_follow check (follower_id <> following_id)
);
alter table public.follows enable row level security;
create policy "follows_select_authenticated" on public.follows for select using (auth.role() = 'authenticated');
create policy "follows_insert_own" on public.follows for insert with check (auth.uid() = follower_id);
create policy "follows_delete_own" on public.follows for delete using (auth.uid() = follower_id);

-- Selesai. Setelah dijalankan, keempat tabel (profiles, cases, comments, follows)
-- akan muncul di menu Table Editor Supabase, lengkap dengan aturan keamanan
-- (setiap orang hanya bisa mengubah/menghapus miliknya sendiri, tapi semua
-- pengguna yang sudah masuk/login bisa membaca).


-- =========================================================================
-- MIGRASI TAMBAHAN: balas komentar, notifikasi, pesan pribadi
-- (CATATAN: bagian ini SUDAH diterapkan otomatis ke project Anda lewat
-- koneksi Supabase — disertakan di sini hanya sebagai arsip/riwayat skema,
-- TIDAK perlu dijalankan ulang secara manual.)
-- =========================================================================

-- 1) Balas komentar (threaded reply)
alter table public.comments add column if not exists parent_id uuid references public.comments(id) on delete cascade;
create index if not exists comments_parent_id_idx on public.comments (parent_id);

-- 2) Pesan pribadi (DM)
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references public.profiles(id) on delete cascade,
  recipient_id uuid not null references public.profiles(id) on delete cascade,
  isi text not null,
  is_read boolean not null default false,
  created_at timestamptz not null default now(),
  constraint no_self_message check (sender_id <> recipient_id)
);
alter table public.messages enable row level security;
create policy "messages_select_own" on public.messages for select using (auth.uid() = sender_id or auth.uid() = recipient_id);
create policy "messages_insert_own" on public.messages for insert with check (auth.uid() = sender_id);
create policy "messages_update_recipient" on public.messages for update using (auth.uid() = recipient_id);
create index if not exists messages_sender_idx on public.messages (sender_id, created_at);
create index if not exists messages_recipient_idx on public.messages (recipient_id, created_at);

-- 3) Notifikasi — hanya bisa diisi lewat trigger SECURITY DEFINER (tidak lewat insert klien)
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  actor_id uuid references public.profiles(id) on delete set null,
  type text not null check (type in ('comment','reply','dm')),
  case_id uuid references public.cases(id) on delete cascade,
  comment_id uuid references public.comments(id) on delete cascade,
  message_id uuid references public.messages(id) on delete cascade,
  is_read boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.notifications enable row level security;
create policy "notifications_select_own" on public.notifications for select using (auth.uid() = user_id);
create policy "notifications_update_own" on public.notifications for update using (auth.uid() = user_id);
create index if not exists notifications_user_unread_idx on public.notifications (user_id, is_read, created_at desc);

-- 4) Trigger: notifikasi otomatis saat ada komentar baru / balasan
create or replace function public.handle_new_comment()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  case_owner uuid; parent_owner uuid;
begin
  select user_id into case_owner from public.cases where id = new.case_id;
  if case_owner is not null and case_owner <> new.user_id then
    insert into public.notifications(user_id, actor_id, type, case_id, comment_id) values (case_owner, new.user_id, 'comment', new.case_id, new.id);
  end if;
  if new.parent_id is not null then
    select user_id into parent_owner from public.comments where id = new.parent_id;
    if parent_owner is not null and parent_owner <> new.user_id and parent_owner <> case_owner then
      insert into public.notifications(user_id, actor_id, type, case_id, comment_id) values (parent_owner, new.user_id, 'reply', new.case_id, new.id);
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists on_comment_created on public.comments;
create trigger on_comment_created after insert on public.comments for each row execute function public.handle_new_comment();

-- 5) Trigger: notifikasi otomatis saat ada pesan pribadi baru
create or replace function public.handle_new_message()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.notifications(user_id, actor_id, type, message_id) values (new.recipient_id, new.sender_id, 'dm', new.id);
  return new;
end; $$;
drop trigger if exists on_message_created on public.messages;
create trigger on_message_created after insert on public.messages for each row execute function public.handle_new_message();

-- 6) Kunci fungsi trigger agar tidak bisa dipanggil langsung lewat API publik
revoke execute on function public.handle_new_comment() from anon, authenticated;
revoke execute on function public.handle_new_message() from anon, authenticated;

-- 7) Realtime, agar badge notifikasi & chat bisa update tanpa perlu refresh manual
alter publication supabase_realtime add table public.notifications;
alter publication supabase_realtime add table public.messages;


-- =========================================================================
-- MIGRASI TAMBAHAN: peran/profesi pengguna (Petani, Pedagang Sarana
-- Pertanian, Penyuluh Pertanian, Akademisi/Peneliti, Lainnya)
-- (CATATAN: sudah diterapkan otomatis ke project Anda — arsip saja.)
-- =========================================================================
alter table public.profiles add column if not exists role text not null default 'petani';
create index if not exists profiles_role_idx on public.profiles (role);


-- =========================================================================
-- FITUR TAMBAHAN: tab Berita (berita pertanian & tautan harga komoditas)
-- (CATATAN: bagian ini TIDAK memakai tabel database. Beritanya diambil lewat
-- Edge Function bernama "berita" yang sudah di-deploy ke project ini lewat
-- koneksi Supabase, jadi tidak perlu SQL apapun untuk fitur ini.)
-- =========================================================================
-- Edge Function "berita" (Deno, publik/tanpa login):
--   - Mengambil RSS berita pertanian resmi (AgroIndonesia, disaring dari
--     ANTARA News/ekonomi), diproses jadi JSON di server (menghindari
--     masalah CORS di browser), dengan cache 15 menit di memori function.
--   - Endpoint: {SUPABASE_URL}/functions/v1/berita
-- Harga Komoditas: karena situs resmi (Panel Harga Pangan Badan Pangan
-- Nasional & PIHPS Bank Indonesia) tidak menyediakan API publik yang stabil
-- (keduanya aplikasi JS, salah satunya bahkan pernah dalam pemeliharaan
-- saat fitur ini dibangun), tab Berita menyediakan tautan langsung ke kedua
-- situs resmi tersebut alih-alih menampilkan angka yang berisiko salah/basi.
