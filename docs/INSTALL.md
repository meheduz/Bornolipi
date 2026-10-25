# Installing Bornolipi

Bornolipi is built for macOS 13 Ventura or later on Apple silicon and Intel Macs. So far it has been
tested on macOS 27 on Apple silicon only. Installing takes a few minutes. Bornolipi itself never asks for
an administrator password; macOS's one-time **Open Anyway** approval may ask for an administrator's
password or Touch ID.

> **About the security warning.** Bornolipi is free and open source. It is not signed with a paid Apple
> Developer ID and has not been notarized by Apple, so macOS cannot check it automatically and warns
> you the first time you open it. The steps below use Apple's own **Open Anyway** button to allow
> it. You never need Terminal, and you should never turn off Gatekeeper. The source code is public on
> GitHub, and each release lists a SHA-256 checksum of the disk image.

## 1. Download

1. On the Bornolipi **Releases** page on GitHub, download **Bornolipi-0.1.0.dmg**.
2. Double-click the downloaded file. In the window that opens, drag **Bornolipi** onto **Applications**.

## 2. Allow Bornolipi to open (first time only)

1. Open your **Applications** folder and double-click **Bornolipi**. macOS says it cannot open or verify
   the app. Close the message (**Done**, or **OK** on older macOS); do not click Move to Trash. These
   steps follow current macOS and have not been checked on macOS 13–14.
2. Open **System Settings > Privacy & Security**, then scroll down to the **Security** section.
   You will see a message that Bornolipi was blocked. Click **Open Anyway**.
3. If asked, confirm with your password or Touch ID, then click **Open Anyway** again.

From now on Bornolipi opens normally. The **Open Anyway** button only appears for about an hour after
macOS blocks an app; if you don't see it, open Bornolipi once more and check again.

If macOS later needs the same approval for the keyboard itself, the Bornolipi app tells you and offers
a button that opens Privacy & Security.

## 3. Follow the setup assistant

The assistant installs the keyboard and checks that your Mac recognizes it. macOS then requires you
to turn the keyboard on yourself, once:

1. Click **Open Keyboard Settings**.
2. Next to **Input Sources**, click **Edit…**.
3. Click **+** at the bottom left, choose **Bangla**, select **Bornolipi**, and click **Add**.

The assistant notices when you have done this and moves on to a short typing test. If Bornolipi does
not appear in the list, the assistant explains what to try.

## 4. Start typing

Choose **Bornolipi** from the input menu in the menu bar (the **অ** symbol), press **Control-Space**,
or click **Use Bornolipi Now** in the assistant. Then type in English letters:

| You type | You get |
| --- | --- |
| ami banglay gan gai | আমি বাংলায় গান গাই |
| amar sOnar bangla | আমার সোনার বাংলা |

| Key | What it does |
| --- | --- |
| Space | Finishes the word |
| ↑ ↓, or a click | Picks another suggestion |
| Return | Finishes the word, then starts a new line (or sends, in chat apps) |
| Esc | Keeps the English letters you typed |
| Control-Shift-B | Switches between Bangla and English; a small বাং/EN bubble shows the mode. Bornolipi's menu in the menu bar (অ) has **Bangla** and **English** items that set the mode too |

Your own words, shortcuts and learning options are in the input menu under **Bornolipi > Settings…**,
or click **Keyboard Settings…** in the Bornolipi app.

## Updating

Bornolipi checks for a newer version on GitHub when you open it, at most once a day (turn this off with
**Check for updates automatically** in the Bornolipi app), and you can click **Check Now** at any time.
When the automatic check finds one, a window shows the new version and its release notes, with
**Download Update** and **Later**; after Later, that version is not shown in a window again. **Check
Now** shows the result in the Bornolipi window instead, with **Release Notes…** and **Download**. Bornolipi never downloads or installs
anything by itself. To update:

1. Click **Download Update** (or **Download**). Your browser opens the release page: under
   **Assets**, click **Bornolipi-<version>.dmg**, then open the downloaded file.
2. Drag **Bornolipi** onto **Applications**. Finder says an item named Bornolipi already exists: click
   **Replace**. This replaces only the app; your words, learned choices and settings are kept.
3. Open Bornolipi. Because Bornolipi is not notarized, macOS asks for approval once more, as in step 2
   above (**Open Anyway** in Privacy & Security). The Bornolipi window then says an update for the
   keyboard is ready: click **Update Now**. If you are typing with Bornolipi, the new keyboard takes
   over the next time you switch keyboards, or when you click **Restart Keyboard**.
4. If Bornolipi then types English letters in an app that was open during the update, quit that app
   (Command-Q) and open it again.

Dragging Bornolipi out of any Bornolipi disk image replaces the copy in Applications, so only do it with an
image you mean to install.

## Uninstalling

Open the Bornolipi app and click **Uninstall…**. Choose whether to delete your personal words, learned
choices and settings as well. You can then move the app to the Trash with one click. If Bornolipi is
still listed under Input Sources, select it there and click **−**.

If you already deleted the app: in **System Settings > Keyboard > Input Sources > Edit…**, select
Bornolipi and click **−**. Then in Finder choose **Go > Go to Folder…**, enter
`~/Library/Input Methods`, and move **BornolipiKeyboard.app** to the Trash. Your words and learned choices are in
`~/Library/Application Support/Bornolipi`, the keyboard's settings in
`~/Library/Preferences/io.github.meheduz.inputmethod.Bornolipi.plist` and the app's in
`~/Library/Preferences/io.github.meheduz.Bornolipi.plist`; move them to the Trash too if you want them gone.

## Your data and privacy

The keyboard never connects to the internet. Your typing, personal words and learned choices stay on
your Mac. Password fields always receive plain letters: macOS turns keyboards like Bornolipi off there.

For anything else, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md).
