# Honoured Native Bridge v1

The native shells host `https://honour-your-word.lovable.app` inside a WebView and expose a small, whitelisted message bridge.

## Web -> Native

Messages are JSON objects:

```json
{
  "bridgeVersion": 1,
  "type": "APP_READY",
  "payload": {}
}
```

Supported foundation messages:

- `APP_READY`
- `CHECK_ACCESS`
- `GET_PLATFORM_INFO`
- `START_PURCHASE` (reserved for billing step)
- `RESTORE_PURCHASES` (reserved for billing step)
- `START_SESSION` (reserved for trial step)

## Native -> Web

Native dispatches a browser event named `honoured:native`:

```js
window.addEventListener('honoured:native', event => {
  console.log(event.detail)
})
```

Foundation events:

- `NATIVE_READY`
- `PLATFORM_INFO`
- `ACCESS_STATUS`
- `ERROR`

All platform-specific capabilities must be invoked through an explicit message type. Do not expose a generic native method executor to the WebView.
