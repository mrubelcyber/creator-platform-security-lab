def login(page, base_url, admin_password):
    page.goto(base_url)

    page.locator("#username").fill("admin")
    page.locator("#password").fill(admin_password)
    page.locator("#loginForm button").click()

    page.wait_for_selector("#appCard:not(.hidden)")


def test_creator_crud(page, base_url, admin_password):
    login(page, base_url, admin_password)

    # -------------------------
    # CREATE
    # -------------------------
    page.locator("#name").fill("Playwright Demo")
    page.locator("#platform").fill("YouTube")
    page.locator("#followers").fill("1000")
    page.locator("#saveBtn").click()

    row = page.locator("tr", has_text="Playwright Demo")
    row.wait_for()

    assert row.is_visible()
    assert "1,000" in row.inner_text()

    # -------------------------
    # UPDATE
    # -------------------------
    row.locator("button", has_text="Edit").click()

    # Verify Edit mode was activated
    page.locator("#creatorId").wait_for(state="attached")

    assert page.locator("#creatorId").input_value() != ""
    assert page.locator("#saveBtn").inner_text() == "Save Changes"

    # Change followers from 1,000 to 2,500
    page.locator("#followers").fill("2500")

    # Verify that a PUT request is actually sent
    with page.expect_response(
        lambda response:
            "/api/creators/" in response.url
            and response.request.method == "PUT"
    ) as response_info:
        page.locator("#saveBtn").click()

    response = response_info.value

    # API update must succeed
    assert response.status == 200

    # Verify updated data appears in the table
    updated_row = page.locator(
        "tr",
        has_text="Playwright Demo"
    )

    updated_row.wait_for()

    assert "2,500" in updated_row.inner_text()

    # -------------------------
    # DELETE
    # -------------------------
    page.once(
        "dialog",
        lambda dialog: dialog.accept()
    )

    updated_row.locator(
        "button",
        has_text="Delete"
    ).click()

    # Wait until the creator disappears
    page.wait_for_function(
        "() => !document.body.innerText.includes('Playwright Demo')"
    )

    assert page.locator(
        "tr",
        has_text="Playwright Demo"
    ).count() == 0
