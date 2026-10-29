# Browser native bridge

Date: 2026-10-28. Execution is authorized in chat. Tracking stays in Later. No public release is authorized.

## Decision

Use Chrome native messaging for one save operation. Embed a signed Swift helper inside Nextshot. The helper exits after its receipt. No permanent helper, local web server, general automation URL, or network listener is required.

The helper quietly opens its exact parent app only for an import. A handshake never launches the app. Browser capture, save, and export remain independent. The browser stores its result before native delivery.

Use a narrow `kAEGetURL` Apple Event. Its URL contains only an unpredictable transfer identifier and request digest. The helper targets the exact installed app process. Request and reply audit tokens authenticate both signed executables through Security.framework. The app checks the embedded helper identifier, team, and path. The helper checks its parent app identifier, team, and path. This uses no socket or general URL automation capability.

Runtime correction on October 28: an anonymous XPC endpoint cannot be archived with `NSKeyedArchiver`. The attempted discovery-file transport fails with Cocoa error 4866. No XPC endpoint file is used. A standalone probe confirms that `kAEGetURL` works with `neverInteract` and returns a 32-byte sender audit token. The SDK defines `keySenderAuditTokenAttr` as read-only. The signed helper and actual Chrome native-message trials both complete. Both directions validate their peer audit token. The helper also sets `kAEDoNotPromptForUserConsent`. If consent is required, delivery fails safely without a prompt.

A user-only inbox holds one bounded request during delivery. The URL carries no media or page path. Files use exclusive creation and no-follow opens. Swift validates the request digest before import. The helper deletes the temporary file after the operation.

Chrome enforces the registered extension allowlist. The command-line origin is a sanity check. It does not authenticate a local caller. Any local user can already write their own round files. The helper offers only validated local import, with no command execution, upload, arbitrary path, or privileged action. The bridge does not claim to protect against software that already runs as the same user.

## Contract and publication

The request binds protocol version 1, channel, import UUID, SHA-256 digest, and the exact payload bytes. Swift validates independently. It checks byte limits, names, actual image dimensions, supported assets, mark geometry, and bounded evidence lists.

The app alone mutates native rounds through `FeedbackRoundStore`. Ordinary captures join its active round. A Rolling Round creates an ended round. It leaves the active marker unchanged.

Native browser imports use schema 2. Native-only rounds continue writing schema 1. Existing schema-1 apps hide schema 2 through the existing compatibility guard. The browser's external `nextshot.browser/1` format remains separate.

The committed capture records import ID and digest. A retry repairs derived files and returns the original capture index. A new ended round is fully staged before its directory is published. Assets are written before the authoritative `feedback.json` update. An acknowledgement is sent only after publication. No queued state is labeled imported.

Browser evidence stays in a local sidecar. Native exports retain that sidecar and selected media. Export metadata names the resized images separately. Original element coordinates remain tied to their recorded browser dimensions.

## Packaging and limits

The development host permits only extension `ghmidcmcjigfckaiopacgpfaffofgjel`. Its native host name is `com.drewschulz.nextshot.dev.browser`. Release registration requires a separate extension identity and is not enabled by this pilot command.

Use `runtime.sendNativeMessage` instead of a permanent port. [Chrome documents](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging) that it starts one helper for each message. The pilot caps payload bytes below Chrome's message limit. A transfer failure keeps the browser save usable.

The `browserBridge` native flag starts off in both channels. Native messaging is an optional browser permission. The first development trial enables only the Dev flag and the fixed Dev helper.
