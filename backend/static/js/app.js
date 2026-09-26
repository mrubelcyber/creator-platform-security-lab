const $ = id => document.getElementById(id);
let creators = [];

async function api(url, options = {}) {
  const response = await fetch(url, {
    headers: {"Content-Type": "application/json", ...(options.headers || {})},
    ...options
  });
  const data = await response.json();
  if (!response.ok) throw new Error(data.error || "Request failed");
  return data;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, c => ({
    "&":"&amp;", "<":"&lt;", ">":"&gt;",
    '"':"&quot;", "'":"&#039;"
  }[c]));
}

function render() {
  $("creatorRows").innerHTML = creators.map(c => `
    <tr>
      <td>${escapeHtml(c.name)}</td>
      <td>${escapeHtml(c.platform)}</td>
      <td>${Number(c.followers).toLocaleString()}</td>
      <td>
        <button onclick="editCreator(${c.id})">Edit</button>
        <button class="secondary" onclick="deleteCreator(${c.id})">Delete</button>
      </td>
    </tr>`).join("");

  $("creatorCount").textContent = creators.length;
  $("followerCount").textContent =
    creators.reduce((total, c) => total + Number(c.followers), 0).toLocaleString();
}

async function loadCreators() {
  creators = await api("/api/creators");
  render();
}

async function checkSession() {
  const status = await api("/api/session");
  $("loginCard").classList.toggle("hidden", status.authenticated);
  $("appCard").classList.toggle("hidden", !status.authenticated);
  if (status.authenticated) await loadCreators();
}

$("loginForm").addEventListener("submit", async event => {
  event.preventDefault();
  try {
    await api("/api/login", {
      method: "POST",
      body: JSON.stringify({
        username: $("username").value,
        password: $("password").value
      })
    });
    $("loginMessage").textContent = "";
    await checkSession();
  } catch (error) {
    $("loginMessage").textContent = error.message;
  }
});

$("creatorForm").addEventListener("submit", async event => {
  event.preventDefault();
  const id = $("creatorId").value;
  const payload = {
    name: $("name").value,
    platform: $("platform").value,
    followers: Number($("followers").value)
  };

  try {
    await api(id ? `/api/creators/${id}` : "/api/creators", {
      method: id ? "PUT" : "POST",
      body: JSON.stringify(payload)
    });
    resetForm();
    await loadCreators();
  } catch (error) {
    $("message").textContent = error.message;
  }
});

function editCreator(id) {
  const creator = creators.find(c => c.id === id);
  $("creatorId").value = creator.id;
  $("name").value = creator.name;
  $("platform").value = creator.platform;
  $("followers").value = creator.followers;
  $("saveBtn").textContent = "Save Changes";
  $("cancelBtn").classList.remove("hidden");
}
window.editCreator = editCreator;

async function deleteCreator(id) {
  if (!confirm("Delete this creator?")) return;
  try {
    await api(`/api/creators/${id}`, {method: "DELETE"});
    await loadCreators();
  } catch (error) {
    $("message").textContent = error.message;
  }
}
window.deleteCreator = deleteCreator;

function resetForm() {
  $("creatorForm").reset();
  $("creatorId").value = "";
  $("saveBtn").textContent = "Add Creator";
  $("cancelBtn").classList.add("hidden");
  $("message").textContent = "";
}

$("cancelBtn").addEventListener("click", resetForm);
$("logoutBtn").addEventListener("click", async () => {
  await api("/api/logout", {method: "POST"});
  await checkSession();
});

checkSession();
