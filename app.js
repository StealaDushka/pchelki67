// Публичный ключ Supabase: его можно держать в коде сайта.
// Пароли и сессии лежат в закрытых таблицах, клиент только вызывает серверные функции.
const SUPABASE_URL = "https://tkyamcshnblsxbqyvqba.supabase.co";
const SUPABASE_KEY = "sb_publishable_k9B2AicjW42dXvndeJ9GJA_bOKcKT4j";
const TOKEN_KEY = "pchelki_token";

const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
const $ = (s) => document.querySelector(s);

let sessionToken = null;
let user = null;

function show(name) {
  document.querySelectorAll(".screen").forEach((el) => el.classList.remove("active"));
  $("#screen-" + name).classList.add("active");
}
function say(text, kind = "") {
  const el = $("#auth-msg");
  el.textContent = text;
  el.className = "msg " + kind;
}
const cleanError = (e) => ((e && e.message) || "Ошибка").replace(/^.*?ERROR:\s*/, "");

function saveToken(t) { try { t ? localStorage.setItem(TOKEN_KEY, t) : localStorage.removeItem(TOKEN_KEY); } catch (e) {} }
function readToken() { try { return localStorage.getItem(TOKEN_KEY); } catch (e) { return null; } }

// ---------- вход и регистрация ----------
$("#form-auth").addEventListener("submit", async (e) => {
  e.preventDefault();
  const action = e.submitter ? e.submitter.dataset.action : "login";
  const nick = $("#username").value.trim();
  const pass = $("#password").value.trim();
  if (!nick || !pass) return say("Заполните всё!", "error");

  const buttons = e.target.querySelectorAll("button");
  buttons.forEach((b) => (b.disabled = true));
  say(action === "register" ? "Создаём пчёлку…" : "Летим…");

  const fn = action === "register" ? "register_user" : "login_user";
  const { data, error } = await sb.rpc(fn, { p_nick: nick, p_pass: pass });
  buttons.forEach((b) => (b.disabled = false));
  if (error || !data) return say(cleanError(error), "error");
  onLoggedIn(data);
});

function onLoggedIn(data) {
  sessionToken = data.token;
  user = data.user;
  saveToken(sessionToken);
  $("#password").value = "";
  say("");
  renderHome();
}

// ---------- улей ----------
function renderHome() {
  $("#home-nick").textContent = user.nickname;
  $("#home-honey").textContent = user.honey;
  $("#home-wins").textContent = user.wins;
  show("home");
}

$("#btn-logout").addEventListener("click", () => {
  if (sessionToken) sb.rpc("logout", { p_token: sessionToken });
  sessionToken = null;
  user = null;
  saveToken(null);
  $("#username").value = "";
  show("auth");
});

// ---------- автовход по сохранённому токену ----------
(async () => {
  const tk = readToken();
  if (tk) {
    const { data, error } = await sb.rpc("me", { p_token: tk });
    if (!error && data) {
      sessionToken = tk;
      user = data;
      return renderHome();
    }
    saveToken(null);
  }
  show("auth");
})();
