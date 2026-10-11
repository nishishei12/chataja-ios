//
//  ChatAjaUITests.swift
//  ChatAjaUITests
//
//  Uji asap (smoke) layar Utas. Syarat jalan: simulator SUDAH login sekali
//  (sesi Firebase tersimpan) dan backend terjangkau. Toggle Ikuti/Suka
//  selalu dikembalikan ke semula, tapi tetap menyentuh data live.

import XCTest

final class ChatAjaUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launch()
    }

    // MARK: - Helpers

    @discardableResult
    func shot(_ name: String) -> XCTAttachment {
        let a = XCTAttachment(screenshot: app.screenshot())
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        return a
    }

    func byId(_ id: String, type: XCUIElement.ElementType = .button) -> XCUIElementQuery {
        app.descendants(matching: type).matching(identifier: id)
    }

    func tapFirst(_ id: String, timeout: TimeInterval = 15, file: StaticString = #filePath, line: UInt = #line) {
        let el = byId(id).firstMatch
        XCTAssertTrue(el.waitForExistence(timeout: timeout), "hilang: \(id)", file: file, line: line)
        el.tap()
        sleep(2)
    }

    /// Ketuk badge follow via label (identifier badge tidak diekspos SwiftUI
    /// ke pohon aksesibilitas; label "Ikuti" yang terbukti ada). Ikuti lalu
    /// kembalikan di kartu yang sama (jangkar frame).
    func tapBadgeFollowUnfollow(file: StaticString = #filePath, line: UInt = #line) {
        let ikuti = app.buttons.matching(NSPredicate(format: "label == 'Ikuti'")).firstMatch
        XCTAssertTrue(ikuti.waitForExistence(timeout: 15), "hilang: badge Ikuti", file: file, line: line)
        let frame = ikuti.frame
        ikuti.tap()
        sleep(3)
        shot("03-setelah-ikuti")
        let berhenti = app.buttons.matching(NSPredicate(format: "label == 'Berhenti mengikuti'"))
            .allElementsBoundByIndex.first(where: {
                abs($0.frame.origin.x - frame.origin.x) < 2 && abs($0.frame.origin.y - frame.origin.y) < 60
            })
        XCTAssertNotNil(berhenti, "badge Berhenti mengikuti tidak ketemu", file: file, line: line)
        berhenti?.tap()
        sleep(3)
        shot("04-setelah-batal-ikuti")
    }

    // MARK: - Drive-through layar Utas

    @MainActor
    func testUtasDriveThrough() throws {
        // 0. Harus sudah login (sesi tersimpan). Tanpa ini tak ada feed.
        if app.buttons["Masuk dengan Google"].waitForExistence(timeout: 8) {
            shot("00-login-terkunci")
            XCTFail("Simulator belum login; masuk dulu sekali lalu ulangi tes.")
            return
        }

        // 1. Feed tampil + composer.
        let composer = app.buttons["Tulis utas baru"]
        XCTAssertTrue(composer.waitForExistence(timeout: 20), "composer tidak muncul")
        XCTAssertTrue(byId("uit-card", type: .any).firstMatch.waitForExistence(timeout: 20), "kartu tidak muncul")
        shot("01-feed")

        // 2. Composer buka-tutup (tanpa posting).
        composer.tap()
        XCTAssertTrue(app.buttons["Batal"].waitForExistence(timeout: 10), "composer tidak terbuka")
        shot("02-composer")
        app.buttons["Batal"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "gagal kembali ke feed")

        // 3. Badge follow: Ikuti lalu kembalikan.
        tapBadgeFollowUnfollow()

        // 4. Suka lalu kembalikan.
        tapFirst("uit-like")
        shot("05-setelah-suka")
        tapFirst("uit-like", timeout: 10)
        shot("06-setelah-batal-suka")

        // 5. Balas -> ThreadView -> kembali.
        tapFirst("uit-comment")
        XCTAssertTrue(app.textFields.firstMatch.waitForExistence(timeout: 15), "komposer thread tidak muncul")
        shot("07-thread")
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "gagal kembali dari thread")

        // 6. Avatar -> profil -> Tutup.
        tapFirst("uit-avatar")
        XCTAssertTrue(byId("uit-profile-follow").firstMatch.waitForExistence(timeout: 15), "profil dari avatar tidak terbuka")
        shot("08-profil-dari-avatar")
        app.buttons["Tutup"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "profil tidak tertutup")

        // 7. Nama penulis -> profil -> tombol Ikuti -> kembalikan -> Tutup.
        tapFirst("uit-username")
        XCTAssertTrue(byId("uit-profile-follow").firstMatch.waitForExistence(timeout: 15), "profil dari nama tidak terbuka")
        shot("09-profil-dari-nama")
        byId("uit-profile-follow").firstMatch.tap()
        sleep(3)
        shot("10-profil-setelah-ikuti")
        byId("uit-profile-follow").firstMatch.tap()
        sleep(3)
        shot("11-profil-setelah-batal-ikuti")

        // 8. Pesan dari profil -> sheet chat -> tutup (tanpa mengirim).
        if byId("uit-profile-message").firstMatch.waitForExistence(timeout: 5) {
            byId("uit-profile-message").firstMatch.tap()
            sleep(4)
            shot("12-chat-dari-profil")
            app.swipeDown()
            sleep(2)
        }
        app.buttons["Tutup"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "gagal kembali ke feed dari profil")

        // 9. Tekan-lama kartu -> menu Ikuti + Kunjungi profil.
        let card = byId("uit-card", type: .any).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "kartu untuk tekan-lama hilang")
        card.press(forDuration: 1.5)
        XCTAssertTrue(app.buttons["Kunjungi profil"].waitForExistence(timeout: 10), "menu tekan-lama tidak muncul")
        shot("13-menu-tekan-lama")
        app.buttons["Kunjungi profil"].tap()
        XCTAssertTrue(byId("uit-profile-follow").firstMatch.waitForExistence(timeout: 15), "profil dari menu tidak terbuka")
        shot("14-profil-dari-menu")
        app.buttons["Tutup"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 10), "gagal kembali ke feed dari menu")

        // 10. Tab Mengikuti lalu kembali ke Public.
        let seg = app.segmentedControls.firstMatch
        XCTAssertTrue(seg.waitForExistence(timeout: 5), "segment tab hilang")
        seg.buttons["Mengikuti"].tap()
        sleep(3)
        shot("15-tab-mengikuti")
        seg.buttons["Public"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 15), "gagal kembali ke tab Public")

        // 11. Scroll lewat ScrollView + screenshot multi-frame.
        let feed = app.scrollViews.firstMatch
        XCTAssertTrue(feed.waitForExistence(timeout: 10), "scroll feed hilang")
        feed.swipeUp()
        sleep(1)
        shot("16-scroll-1")
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric]) {
            feed.swipeUp()
        }
        sleep(1)
        shot("17-scroll-2")

        // 12. Bagikan paling akhir (share sheet sistem) + pemulihan.
        tapFirst("uit-share")
        sleep(3)
        shot("18-share-sheet")
        if app.buttons["Tutup"].waitForExistence(timeout: 5) {
            app.buttons["Tutup"].tap()
        } else {
            app.terminate()
            app.launch()
            XCTAssertTrue(composer.waitForExistence(timeout: 20), "aplikasi tidak pulih setelah share")
        }
        shot("19-feed-akhir")
    }
}
