# Code signing policy

Free code signing provided by [SignPath.io](https://about.signpath.io), certificate by [SignPath Foundation](https://signpath.org).

Windows releases of ScreenRest (`ScreenRest.exe` and `ScreenRest-Setup-<version>.exe`) are built from this repository by
[GitHub Actions](.github/workflows/build.yml) and signed through SignPath. Only files built by that workflow from
the public source code are signed. The Microsoft Store version (`.msix`) is signed by Microsoft when it is published.

## Team roles

| Role | Member |
|---|---|
| Author, committer and reviewer | [Jilbert Mejia (@jsmejia27)](https://github.com/jsmejia27) |
| Approver (approves each release signing request) | [Jilbert Mejia (@jsmejia27)](https://github.com/jsmejia27) |

All team members use multi-factor authentication for GitHub and SignPath.

## Privacy

This program will not transfer any information to other networked systems. ScreenRest works fully offline:
your settings and break history stay in `%APPDATA%\ScreenRest` on your own PC.

## Setting it up (maintainer notes)

1. Apply at <https://signpath.org/apply> with this repository. SignPath must approve the project first.
2. In SignPath, create the project with slug `ScreenRest`, connect the GitHub trusted build system, and add two
   artifact configurations by pasting [`.signpath/artifact-configurations/app.xml`](.signpath/artifact-configurations/app.xml)
   (slug `app`) and [`installer.xml`](.signpath/artifact-configurations/installer.xml) (slug `installer`).
   Use the signing policies `test-signing` and `release-signing` (SignPath's defaults).
3. In GitHub: Settings > Secrets and variables > Actions, add the secret `SIGNPATH_API_TOKEN` (a SignPath CI user token)
   and the variable `SIGNPATH_ORGANIZATION_ID`. From then on, every build is signed; tags (`v1.2.0`) use release signing,
   which you approve in SignPath.
