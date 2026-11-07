const english = {
  "Аккаунт FitnessTracker": "FitnessTracker account",
  "Перейти к содержимому": "Skip to content",
  "Тема оформления": "Appearance",
  "Светлая тема": "Light theme",
  "Тёмная тема": "Dark theme",
  "Язык интерфейса": "Language",
  "О FitnessTracker": "About FitnessTracker",
  "Твои тренировки, питание и прогресс —": "Your workouts, nutrition and progress —",
  "в одном месте": "all in one place",
  "Тренировки": "Workouts",
  "Программы и планы": "Programs and plans",
  "Питание": "Nutrition",
  "Дневник и баланс КБЖУ": "Food diary and macros",
  "Прогресс": "Progress",
  "Статистика и цели": "Statistics and goals",
  "Резервные копии": "Backups",
  "Твоя история всегда рядом": "Keep your history close",
  "Твой ритм. Твой прогресс.": "Your pace. Your progress.",
  "Вход в аккаунт": "Sign in",
  "Войди, чтобы сохранять резервные копии тренировок и продолжать в своём ритме.": "Sign in to back up your workouts and keep moving at your own pace.",
  "Электронная почта": "Email address",
  "Пароль": "Password",
  "Показать пароль": "Show password",
  "Скрыть пароль": "Hide password",
  "Войти по паролю": "Sign in with password",
  "Войти с passkey": "Sign in with passkey",
  "или": "or",
  "Продолжить с Apple": "Continue with Apple",
  "Продолжить с Google": "Continue with Google",
  "Продолжить с Яндекс ID": "Continue with Yandex ID",
  "В разработке": "Coming soon",
  "Создать аккаунт": "Create account",
  "Тренировки на устройстве доступны без входа.": "Workouts on your device are available without an account.",
  "Начни планировать тренировки, следить за питанием и сохранять свой прогресс.": "Start planning workouts, tracking nutrition and saving your progress.",
  "От 12 до 128 символов": "12 to 128 characters",
  "Минимум 4 разных символа": "At least 4 different characters",
  "Подтвердите пароль": "Confirm password",
  "Пароли не совпадают.": "Passwords do not match.",
  "Создать аккаунт с passkey": "Create account with passkey",
  "Уже есть аккаунт?": "Already have an account?",
  "Войти": "Sign in",
  "Без писем и кодов подтверждения.": "No confirmation emails or codes.",
  "Ваш аккаунт": "Your account",
  "Способы входа": "Sign-in methods",
  "Пароль подключён.": "Password enabled.",
  "Удалить passkey": "Remove passkey",
  "Название passkey": "Passkey name",
  "Например, мой iPhone": "For example, my iPhone",
  "Добавить passkey": "Add passkey",
  "Отключить Apple": "Disconnect Apple",
  "Отключить Google": "Disconnect Google",
  "Отключить Yandex": "Disconnect Yandex",
  "Подключить Apple": "Connect Apple",
  "Подключить Google": "Connect Google",
  "Подключить Яндекс ID": "Connect Yandex ID",
  "Последний способ входа отключить нельзя.": "You must keep at least one sign-in method.",
  "После отключения способа входа потребуется снова войти в приложение на всех устройствах.": "Disconnecting a sign-in method requires signing in again on all devices.",
  "Вернуться в приложение": "Return to the app",
  "Выйти в браузере": "Sign out in this browser",
  "Удалить аккаунт и все серверные копии можно в настройках приложения.": "You can delete your account and all server backups in the app settings.",
  "Укажите email и одинаковые пароли длиной от 12 до 128 символов.": "Enter an email address and matching passwords of 12 to 128 characters.",
  "Не удалось зарегистрироваться. Проверьте данные или попробуйте войти.": "Unable to create your account. Check your details or try signing in.",
  "Не удалось войти. Проверьте email и пароль или попробуйте позже.": "Unable to sign in. Check your email and password or try again later.",
  "Passkey недоступен в этом браузере. Используйте другой способ входа.": "Passkeys are unavailable in this browser. Use another sign-in method.",
  "Подтвердите действие на устройстве…": "Confirm on your device…",
  "Не удалось получить passkey. Повторите попытку.": "Unable to get a passkey. Please try again.",
  "Не удалось продолжить вход.": "Unable to continue signing in.",
  "Действие отменено или время ожидания истекло. Можно повторить попытку.": "Cancelled or timed out. You can try again.",
  "Не удалось использовать passkey. Повторите попытку.": "Unable to use the passkey. Please try again.",
  "Слишком много попыток. Подождите минуту.": "Too many attempts. Please wait a minute.",
  "Не удалось выполнить действие. Повторите попытку.": "Unable to complete this action. Please try again.",
  "Укажите корректный email.": "Enter a valid email address.",
  "Не удалось подтвердить passkey. Повторите попытку.": "Unable to verify the passkey. Please try again."
};

// Только настройки оформления. Credentials и содержимое полей не сохраняются.
function readPreference(key) {
  try { return localStorage.getItem(key); }
  catch { return null; }
}

function savePreference(key, value) {
  try { localStorage.setItem(key, value); return true; }
  catch { return false; }
}

export function translate(source) {
  return document.documentElement.lang === "en" ? english[source] ?? source : source;
}

export function setMessage(element, source) {
  element.dataset.localize = source;
  element.textContent = translate(source);
}

function localize() {
  document.title = translate("Аккаунт FitnessTracker");
  for (const element of document.querySelectorAll("[data-localize], .provider-tooltip, [data-localize-errors] li")) {
    const source = element.dataset.localize || element.textContent.trim();
    setMessage(element, source);
  }
  for (const [attribute, dataKey] of [["aria-label", "localizeLabel"], ["placeholder", "localizePlaceholder"]]) {
    for (const element of document.querySelectorAll(`[data-${dataKey.replace(/[A-Z]/g, letter => `-${letter.toLowerCase()}`)}]`)) {
      const source = element.dataset[dataKey] || element.getAttribute(attribute);
      element.dataset[dataKey] = source;
      element.setAttribute(attribute, translate(source));
    }
  }
}

const systemTheme = matchMedia("(prefers-color-scheme: dark)");
let chosenTheme = readPreference("fitness-auth-theme");
if (!["light", "dark"].includes(chosenTheme)) chosenTheme = null;

function applyTheme(theme) {
  document.documentElement.dataset.theme = theme;
  for (const button of document.querySelectorAll("[data-theme-choice]")) {
    button.setAttribute("aria-pressed", String(button.dataset.themeChoice === theme));
  }
}

applyTheme(chosenTheme ?? (systemTheme.matches ? "dark" : "light"));
systemTheme.addEventListener("change", event => {
  if (!chosenTheme) applyTheme(event.matches ? "dark" : "light");
});
for (const button of document.querySelectorAll("[data-theme-choice]")) {
  button.addEventListener("click", () => {
    chosenTheme = button.dataset.themeChoice;
    applyTheme(chosenTheme);
    savePreference("fitness-auth-theme", chosenTheme);
  });
}

const languagePicker = document.querySelector("[data-language]");
const savedLanguage = readPreference("fitness-auth-language");
document.documentElement.lang = savedLanguage === "en" ? "en" : "ru";
languagePicker.value = document.documentElement.lang;
languagePicker.addEventListener("change", () => {
  document.documentElement.lang = languagePicker.value === "en" ? "en" : "ru";
  savePreference("fitness-auth-language", document.documentElement.lang);
  localize();
  updatePasswordRules();
});

for (const button of document.querySelectorAll("[data-password-toggle]")) {
  const input = document.getElementById(button.dataset.passwordToggle);
  button.hidden = false;
  button.addEventListener("click", () => {
    const visible = input.type === "password";
    input.type = visible ? "text" : "password";
    button.setAttribute("aria-pressed", String(visible));
    button.dataset.localizeLabel = visible ? "Скрыть пароль" : "Показать пароль";
    button.setAttribute("aria-label", translate(button.dataset.localizeLabel));
  });
}

const registration = document.querySelector("[data-registration]");
function updatePasswordRules() {
  if (!registration) return;
  const password = registration.elements.namedItem("password");
  const confirmation = registration.elements.namedItem("confirmPassword");
  // String.length/split используют UTF-16 code units, как Length/char в Identity.
  const rules = { length: password.value.length >= 12 && password.value.length <= 128,
    unique: new Set(password.value.split("")).size >= 4 };
  for (const element of document.querySelectorAll("[data-password-rule]")) {
    element.dataset.state = password.value.length ? (rules[element.dataset.passwordRule] ? "valid" : "invalid") : "neutral";
  }
  confirmation.setCustomValidity(confirmation.value && confirmation.value !== password.value
    ? translate("Пароли не совпадают.") : "");
}
registration?.addEventListener("input", updatePasswordRules);
updatePasswordRules();
localize();
document.querySelector("[data-appearance-controls]").hidden = false;
