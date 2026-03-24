options gen2
options rtti
options persistent_heap

require telegram/tbot
require daslib/fio
require strings

[export]
def main() {
    // read token from TELEGRAM_BOT_TOKEN env var or .bot_token file
    var token = ""
    unsafe {
        token = get_env_variable("TELEGRAM_BOT_TOKEN")
    }
    if (empty(token)) {
        fopen(".bot_token", "rb") <| $(f) {
            if (f != null) {
                token = fread(f)
                token = strip(token)
            }
        }
    }
    if (empty(token)) {
        print("No bot token found. Set TELEGRAM_BOT_TOKEN env var or create .bot_token file\n")
        return
    }
    telegram_set_configuration(configuration(token = token))
    telegram_set_log_api_calls(true)

    // test getMe
    print("=== getMe ===\n")
    var me <- telegram_getMe()
    let err1 = telegram_get_last_error()
    if (!empty(err1)) {
        print("ERROR: {err1}\n")
        return
    }
    print("Bot id:       {me.id}\n")
    print("Bot username: {me.username}\n")
    print("Bot name:     {me.first_name}\n")
    print("Is bot:       {me.is_bot}\n")
    print("sprint_json:  {sprint_json(me, false)}\n")

    // test getUpdates (short poll, no wait)
    print("\n=== getUpdates ===\n")
    var updates <- telegram_getUpdates(get_updates(timeout = 0l, limit = 5l))
    let err2 = telegram_get_last_error()
    if (!empty(err2)) {
        print("ERROR: {err2}\n")
        return
    }
    print("Got {length(updates)} update(s)\n")
    for (u in updates) {
        print("  update_id={u.update_id}")
        if (u.message != null) {
            assume msg = *u.message
            print(" from={msg._from.first_name} text=\"{msg.text}\"")
        }
        print("\n")
    }
    print("\nAll tests passed!\n")
}
