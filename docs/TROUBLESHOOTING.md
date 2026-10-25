# Troubleshooting

Start by opening the **Bornolipi** app. Its status card says what is wrong and offers a
button to fix it.

| The app says | What to do |
| --- | --- |
| The keyboard is not installed | Click **Install**. |
| The keyboard needs repair | Click **Repair**. Your words and settings are kept. |
| An update for the keyboard is ready | Click **Update Now**. |
| The keyboard is not turned on | Click **Open Keyboard Settings** and add Bornolipi (Input Sources, Edit…, +, Bangla). |
| macOS does not know about the keyboard yet | Click **Repair**. Your words and settings are kept. |
| This copy of Bornolipi is older than the installed keyboard | Open the newer Bornolipi (download the latest release); this copy will not replace a newer keyboard. |
| The keyboard is installed and turned on | It is working. Choose it from the input menu (অ) in the menu bar. |

**After an update, Bornolipi types English letters in an app that was already open.** Quit that app
(Command-Q) and open it again. Some apps (seen with Chrome and Terminal) keep talking to the keyboard
that was running before the update until they are reopened; apps opened afterwards are not affected.

**Bornolipi is not under Bangla when I click +.** Click **Repair** in the app, then use **Restart System
Settings** (or quit and reopen System Settings) and look again. If it is still missing, click **Report a
Problem** in the Bornolipi app. On some Macs the Keyboard settings pane keeps an old list of keyboards
and does not show keyboards installed later. This is a macOS problem: Bornolipi is installed and
registered correctly, and macOS does not let any app add a keyboard for you. Logging out, restarting
and installing for all users did not fix it on the Mac where it was seen, so we do not suggest them
as a fix (details for developers in [DEVELOPMENT.md](DEVELOPMENT.md)).

**I get English letters.** Bornolipi has an English mode: press Control-Shift-B. A small
**বাং** or **EN** bubble shows the mode. The menu bar icon stays Bornolipi's (অ) in both modes: macOS gives
a keyboard one icon, and its menu cannot show the current mode reliably, so it offers **Bangla** and
**English** to choose instead. Password
fields always get English letters; macOS turns keyboards like this off there on purpose, to protect
passwords.

**Letters come out English, but no বাং/EN bubble appeared.** Check that you pressed **control ⌃**,
not the **fn 🌐** key next to it. On many Macs 🌐 opens Emoji & Symbols (System Settings > Keyboard,
"Press 🌐 key to"), which stops Bornolipi in that app until you press 🌐 again.

**Bornolipi stopped typing in every app after Restart Keyboard, an update or a reinstall.** Choose
another keyboard and then Bornolipi again. If letters still stay English, log out and back in: on
macOS 27 the system sometimes does not start the restarted keyboard again until then (seen once
during testing, after the keyboard was removed and reinstalled).

**The very first letter after switching keyboards stays English.** Some apps, such as Safari,
take a moment to switch. Type the word again.

**The suggestion window is in the wrong place.** A few apps do not tell macOS where the text
cursor is, so the window appears near the mouse pointer instead. Typing still works.

**Return sends a chat message without the last word.** Press Space before Return, and please
tell us which app this happens in.

**A word is wrong or missing.** Add it in **Keyboard Settings… > Dictionary > My words**. If a
wrong word keeps coming first, delete it under **Learned choices** in the same place.

**Getting help.** In the Bornolipi app, click **Copy Diagnostic Report** and paste it into
your message. It contains versions and status only, never anything you typed.
