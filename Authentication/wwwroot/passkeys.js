"use strict";
import { setMessage } from "./auth-ui.js";

const passkeyButtons = [...document.querySelectorAll("button[data-passkey]")];
const supported = window.isSecureContext && typeof PublicKeyCredential !== "undefined"
  && typeof PublicKeyCredential.parseCreationOptionsFromJSON === "function"
  && typeof PublicKeyCredential.parseRequestOptionsFromJSON === "function"
  && typeof PublicKeyCredential.prototype.toJSON === "function";

for (const button of passkeyButtons) {
  const form = button.closest("form");
  const status = form.querySelector("[data-passkey-status]");
  if (!supported) {
    setMessage(status, "Passkey недоступен в этом браузере. Используйте другой способ входа.");
    continue;
  }
  button.disabled = false;
  button.addEventListener("click", async () => {
    form.querySelector("[data-passkey-error]")?.remove();
    const email = form.elements.namedItem("email");
    if (email && !email.reportValidity()) return;
    const name = form.elements.namedItem("name");
    if (name && !name.reportValidity()) return;
    const mode = button.dataset.passkey;
    const endpoint = mode === "enroll" ? "/account/passkeys" : `/passkeys/${mode}`;
    const fields = new FormData(form);
    // Пароли не нужны для passkey и не отправляются даже если уже введены в соседние поля.
    fields.delete("password");
    fields.delete("confirmPassword");
    const controller = new AbortController();
    const abort = () => controller.abort();
    window.addEventListener("pagehide", abort, { once: true });
    const timeout = setTimeout(abort, 180000);
    passkeyButtons.forEach(item => { item.disabled = true; });
    setMessage(status, "Подтвердите действие на устройстве…");
    let browserContext = null;
    try {
      const options = await post(`${endpoint}/options`, fields, controller.signal);
      browserContext = {
        mode,
        activation: navigator.userActivation?.isActive ?? "unknown",
        visible: document.visibilityState === "visible",
        focused: document.hasFocus()
      };
      const credential = mode === "login"
        ? await navigator.credentials.get({
          publicKey: PublicKeyCredential.parseRequestOptionsFromJSON(options), signal: controller.signal
        })
        : await navigator.credentials.create({
          publicKey: PublicKeyCredential.parseCreationOptionsFromJSON(options), signal: controller.signal
        });
      if (!credential) throw new Error("Не удалось получить passkey. Повторите попытку.");
      fields.set("credential", JSON.stringify(credential.toJSON()));
      const result = await post(endpoint, fields, controller.signal);
      const target = new URL(result.redirect, window.location.origin);
      if (target.origin !== window.location.origin) throw new Error("Не удалось продолжить вход.");
      window.location.assign(target.href);
    } catch (error) {
      if (error instanceof DOMException && Object.hasOwn(browserErrorMessages, error.name)) {
        setMessage(status, browserErrorMessages[error.name]);
        showBrowserError(form, error, browserContext);
      } else {
        setMessage(status, error.name === "AbortError"
          ? "Действие отменено или время ожидания истекло. Можно повторить попытку."
          : error.message || "Не удалось использовать passkey. Повторите попытку.");
      }
    } finally {
      clearTimeout(timeout);
      window.removeEventListener("pagehide", abort);
      passkeyButtons.forEach(item => { item.disabled = false; });
    }
  });
}

// NotAllowedError также означает отказ платформы. Он не доказывает отмену пользователем.
const browserErrorMessages = {
  NotAllowedError: "Не удалось завершить действие с passkey. Если окно подтверждения не появилось, откройте сайт в Safari и повторите попытку.",
  SecurityError: "Браузер не разрешил использовать passkey для этого сайта. Откройте сайт в Safari и повторите попытку.",
  InvalidStateError: "Не удалось создать passkey. Возможно, этот ключ уже подключён к аккаунту. Используйте существующий ключ или другой способ сохранения.",
  NotSupportedError: "Этот браузер или устройство не поддерживает выбранный способ сохранения passkey."
};

function showBrowserError(form, error, context) {
  const details = document.createElement("details");
  details.dataset.passkeyError = error.name;
  details.className = "passkey-error-details";
  const summary = document.createElement("summary");
  setMessage(summary, "Подробности ошибки");
  const description = document.createElement("pre");
  // Только текст штатного DOMException из allowlist, без options, FormData и credential.
  // Не отправляем диагностику на сервер и не сохраняем в storage/console.
  const message = `${error.name}: ${error.message}`.slice(0, 1024);
  description.textContent = context
    ? `${message}\nWebAuthn: ${context.mode}\nUser activation: ${context.activation}\nPage visible: ${context.visible}\nPage focused: ${context.focused}`
    : message;
  details.append(summary, description);
  form.append(details);
}

async function post(path, fields, signal) {
  const response = await fetch(path, {
    method: "POST", body: fields, credentials: "same-origin", mode: "same-origin",
    redirect: "error", headers: { "Accept": "application/json" }, signal
  });
  if (response.status === 429) throw new Error("Слишком много попыток. Подождите минуту.");
  if (!response.ok) {
    const problem = await response.json().catch(() => null);
    throw new Error(problem?.title || "Не удалось выполнить действие. Повторите попытку.");
  }
  return response.json();
}
