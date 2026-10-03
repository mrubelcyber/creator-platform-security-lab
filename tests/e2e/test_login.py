def test_login_and_logout(page, base_url, admin_password):
    page.goto(base_url)
    page.wait_for_selector("#loginCard")
    assert page.locator("h1").inner_text() == "Creator Platform"

    page.locator("#username").fill("admin")
    page.locator("#password").fill(admin_password)
    page.locator("#loginForm button").click()

    page.wait_for_selector("#appCard:not(.hidden)")
    assert page.locator("#appCard").is_visible()
    assert page.locator("#creatorRows tr").count() >= 3

    page.locator("#logoutBtn").click()
    page.wait_for_selector("#loginCard:not(.hidden)")
    assert page.locator("#loginCard").is_visible()
