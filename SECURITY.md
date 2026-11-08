# Security policy

Copicol sees everything you copy, so security and privacy reports are taken seriously.

## Supported versions

Only the [latest release](https://github.com/romainrg/Copicol/releases/latest) receives security fixes.

## Reporting a vulnerability

**Please do not open a public issue.** Report the problem privately instead:

- preferably through GitHub: [report a vulnerability](https://github.com/romainrg/Copicol/security/advisories/new) (Security tab › Advisories);
- or by email to romaingallien.rg@gmail.com.

Please include:

- the Copicol and macOS versions;
- a description of the problem and its impact;
- the steps to reproduce it, or a proof of concept;
- whether the problem is already public.

Copicol is maintained on a volunteer basis. You can expect an acknowledgement within 7 days and an assessment within 30 days. You will be kept informed, credited in the release notes if you wish, and consulted on the disclosure date once a fix is available.

## Scope

In scope, for example:

- content marked as concealed or transient (passwords) being recorded, or copies made in excluded apps being captured;
- the clipboard history leaving the Mac other than through the opt-in iCloud sync, or becoming readable by other apps;
- an item being pasted into the wrong application;
- clipboard contents being written to logs;
- code execution or a sandbox escape triggered by copied content (images, rich text, links).

Out of scope:

- attacks that require an already compromised user account or administrator access;
- the Accessibility permission itself, which Copicol requests by design in order to paste;
- the Gatekeeper warning shown on first launch of builds that are not notarized.
