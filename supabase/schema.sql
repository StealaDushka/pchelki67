-- Пчёлки 67: аккаунты (ник + пароль), как в Steal a Dushka 2.
create extension if not exists pgcrypto with schema extensions;

create table public.users (
  nickname   text primary key
             check (char_length(nickname) between 2 and 20 and nickname ~ '^[A-Za-zА-Яа-яЁё0-9_]+$'),
  honey      bigint not null default 0 check (honey >= 0),
  wins       int    not null default 0 check (wins >= 0),
  is_admin   boolean not null default false,
  created_at timestamptz not null default now()
);
create unique index users_nick_lower on public.users (lower(nickname));

create table public.user_secrets (
  nickname  text primary key references public.users(nickname) on delete cascade on update cascade,
  pass_hash text not null
);

create table public.sessions (
  token      uuid primary key default gen_random_uuid(),
  nickname   text not null references public.users(nickname) on delete cascade on update cascade,
  created_at timestamptz not null default now()
);
create index on public.sessions(nickname);

alter table public.users        enable row level security;
alter table public.user_secrets enable row level security;
alter table public.sessions     enable row level security;
create policy read_all on public.users for select to anon, authenticated using (true);
revoke all on public.users, public.user_secrets, public.sessions from anon, authenticated;
grant select on public.users to anon, authenticated;

create or replace function public._auth(p_token uuid) returns text
language plpgsql stable security definer set search_path = public as $$
declare v text;
begin
  select nickname into v from sessions where token = p_token;
  if v is null then raise exception 'Сессия истекла, войди заново' using errcode = 'P0001'; end if;
  return v;
end $$;

create or replace function public._user_json(p_nick text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('nickname', nickname, 'honey', honey, 'wins', wins, 'is_admin', is_admin)
  from users where nickname = p_nick;
$$;

create or replace function public.register_user(p_nick text, p_pass text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare tok uuid;
begin
  p_nick := trim(p_nick);
  if p_nick !~ '^[A-Za-zА-Яа-яЁё0-9_]{2,20}$' then
    raise exception 'Ник: 2–20 символов, только буквы, цифры и _';
  end if;
  if char_length(coalesce(p_pass, '')) < 4 then raise exception 'Пароль минимум 4 символа'; end if;
  if exists (select 1 from users where lower(nickname) = lower(p_nick)) then raise exception 'Ник занят'; end if;
  insert into users(nickname) values (p_nick);
  insert into user_secrets(nickname, pass_hash) values (p_nick, crypt(p_pass, gen_salt('bf')));
  insert into sessions(nickname) values (p_nick) returning token into tok;
  return jsonb_build_object('token', tok, 'user', public._user_json(p_nick));
end $$;

create or replace function public.login_user(p_nick text, p_pass text) returns jsonb
language plpgsql security definer set search_path = public, extensions as $$
declare h text; tok uuid;
begin
  select pass_hash into h from user_secrets where nickname = trim(p_nick);
  if h is null or h <> crypt(p_pass, h) then raise exception 'Неверный ник или пароль'; end if;
  insert into sessions(nickname) values (trim(p_nick)) returning token into tok;
  delete from sessions where nickname = trim(p_nick) and token not in
    (select token from sessions where nickname = trim(p_nick) order by created_at desc limit 5);
  return jsonb_build_object('token', tok, 'user', public._user_json(trim(p_nick)));
end $$;

create or replace function public.me(p_token uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  return public._user_json(public._auth(p_token));
end $$;

create or replace function public.logout(p_token uuid) returns void
language sql security definer set search_path = public as $$
  delete from sessions where token = p_token;
$$;

revoke execute on function public._auth(uuid), public._user_json(text) from public, anon, authenticated;
