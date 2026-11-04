"use strict";

const passkeyButtons = [...document.querySelectorAll("button[data-passkey]")];
const supported = window.isSecureContext && typeof PublicKeyCredential !== "undefined"
  && typeof PublicKeyCredential.parseCreationOptionsFromJSON === "function"
  && typeof PublicKeyCredential.parseRequestOptionsFromJSON === "function"
  && typeof PublicKeyCredential.prototype.toJSON === "function";

for (const button of passkeyButtons) {
  const form = button.closest("form");
  const status = form.querySelector("[data-passkey-status]");
  if (!supported) {
    status.textContent = "Passkey недоступен в этом браузере. Используйте другой способ входа.";
    continue;
  }
  button.disabled = false;
  button.addEventListener("click", async () => {
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
    status.textContent = "Подтвердите действие на устройстве…";
    try {
      const options = await post(`${endpoint}/options`, fields, controller.signal);
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
      status.textContent = error.name === "NotAllowedError" || error.name === "AbortError"
        ? "Действие отменено или время ожидания истекло. Можно повторить попытку."
        : error.message || "Не удалось использовать passkey. Повторите попытку.";
    } finally {
      clearTimeout(timeout);
      window.removeEventListener("pagehide", abort);
      passkeyButtons.forEach(item => { item.disabled = false; });
    }
  });
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
