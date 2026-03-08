# dasTelegram

Telegram Bot API bindings for [daslang](https://dascript.org/).

Zero-DOM JSON pipeline — uses `sprint_json` for requests and `sscan_json` for responses. No `read_json`/`from_JV` overhead.

## Requirements

- daslang with dasHV module enabled (`DAS_HV_DISABLED=OFF`)
- `sscan_json` / `sprint_json` builtins (daslang >= 0.5)

## Install

```
daspkg install github.com/borisbat/dasTelegram
```

Or clone manually into your project's `modules/dasTelegram/`.

## Usage

```das
options gen2
options rtti
options persistent_heap

require telegram/tbot
require fio

[export]
def main() {
    var token = ""
    unsafe {
        token = get_env_variable("TELEGRAM_BOT_TOKEN")
    }
    telegram_set_configuration(configuration(token = token))

    // get bot info
    var me <- telegram_getMe()
    print("Bot: {me.username}\n")

    // echo bot loop
    var offset = 0l
    while (true) {
        var updates <- telegram_getUpdates(get_updates(offset = offset, timeout = 30l))
        for (u in updates) {
            offset = u.update_id + 1l
            if (u.message != null) {
                unsafe {
                    let msg & = *u.message
                    if (!empty(msg.text)) {
                        telegram_sendMessage(send_message(chat_id = "{msg.chat.id}", text = msg.text))
                    }
                }
            }
        }
    }
}
```

## Regenerating API types

The `telegram/tbotapi.das` file is generated from the [Telegram Bot API spec](https://github.com/PaulSonOfLars/telegram-bot-api-spec). To regenerate:

1. Download `api.json` from the spec repo
2. Place it in `telegram/api.json`
3. Run: `daslang telegram/generate.das --`

## Files

- `telegram/tbot.das` — bot API wrapper (configuration, HTTP calls, JSON pipeline)
- `telegram/tbotapi.das` — generated struct types with `@optional`/`@rename` annotations
- `telegram/generate.das` — code generator
- `.das_module` — module registration for `require telegram/tbot`
- `.das_package` — daspkg manifest
- `examples/echo_bot.das` — echo bot example
- `examples/test_api.das` — API smoke test
