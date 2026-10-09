# Action Bar Saver Ultimate for WoW 3.3.5a — Export and import profiles between accounts in just a few clicks without overwriting your existing settings.

Action Bar Saver is an addon that allows you to restore your action bars in a single click. For example, if you have two Warriors and have already configured all your macros and abilities on one of them, you don't need to manually rearrange everything on the second one. Simply save a profile for the first Warrior using /abs save warrior (or any other profile name), and then restore it on the second Warrior with /abs restore warrior.

In the original Action Bar Saver for WoW 3.3.5a, transferring settings between different accounts was extremely problematic. This was because the addon's settings were tied to the account rather than the character. Therefore, if you had two accounts with different classes, transferring settings from one account would always overwrite the settings of the other. For instance, if you have a Warrior on Account A but not on Account B, moving settings from Account B to Account A would cause your Warrior's settings to disappear, since ABS profiles are linked to specific classes.

The Ultimate version solves this problem: transferring settings now works just like in WeakAuras — via an export string that can be imported in a single click.

**Important**: To ensure a correct export and import, make sure your macros have unique names — duplicate macro names are not allowed.

# How to Export -> Import:
Suppose you want to transfer settings from Character 1 to Character 2:

1. Log into Character 1.
2. Type /abs save <your profile name>.
3. Type /abs export <your profile name>.
4. Copy the content from the window that appears.
5. Log into Character 2.
6. Type /abs import <your profile name>.
7. Paste the content from your clipboard.
8. Click the Import button.
9. Type /abs restore <your profile name> (the same name used in step 6).

Type /abs to see all commands

# How to install: Extract ActionBarSaver folder to [C:\World of Warcraft 3.3.5a]\Interface\AddOns

# Screenshots:

<img width="757" height="507" alt="ABS export" src="https://github.com/user-attachments/assets/2d1f8705-63bc-4a03-b344-93836fa44ebd" />
<img width="767" height="507" alt="ABS import" src="https://github.com/user-attachments/assets/6a7e5afa-6021-4121-a6ca-109d385f9c4b" />
